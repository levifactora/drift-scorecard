import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let analysisWidth = 480

func requireFile(_ path: String) throws {
    guard FileManager.default.fileExists(atPath: path) else { throw ScorecardError.fileNotFound(path) }
}

public func loadPicture(_ path: String) throws -> CGImage {
    try requireFile(path)
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ScorecardError.unreadableImage(path)
    }
    return image
}

/// Evenly spaced frames. Stays just inside the ends, where video decoders are least reliable.
public func sampleTimes(duration: Double, count: Int = defaultFrameCount) -> [(label: String, seconds: Double)] {
    let inset = min(0.1, duration / 10)
    return (0..<count).map { index in
        if index == 0 { return ("Start", inset) }
        if index == count - 1 { return ("End", duration - inset) }
        let fraction = Double(index) / Double(count - 1)
        return (fraction == 0.5 ? "Middle" : "\(Int((fraction * 100).rounded()))%", duration * fraction)
    }
}

/// Apple's on-device image comparison. 0 is identical; higher is less alike.
public func overallLookDistance(_ first: CGImage, _ second: CGImage) throws -> Double {
    func featurePrint(_ image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let observation = request.results?.first else { throw CocoaError(.fileReadUnknown) }
        return observation
    }
    var distance: Float = 0
    try featurePrint(first).computeDistance(&distance, to: featurePrint(second))
    return Double(distance)
}

public func loadVideoFrames(_ path: String, count: Int = defaultFrameCount) throws -> [(label: String, seconds: Double, image: CGImage)] {
    try requireFile(path)
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = CMTimeGetSeconds(asset.duration)
    guard duration.isFinite, duration > 0 else {
        throw ScorecardError.unreadableVideo(path)
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    return try sampleTimes(duration: duration, count: count).map { sample in
        // A frame that cannot be read must stop the run: skipping it could let a bad video pass.
        guard let image = try? generator.copyCGImage(at: CMTime(seconds: sample.seconds, preferredTimescale: 600), actualTime: nil) else {
            throw ScorecardError.frameUnavailable(path, sample.seconds)
        }
        return (sample.label, sample.seconds, image)
    }
}

/// Redraws a picture at a fixed size in sRGB, over white so transparent areas are consistent.
public func normalize(_ image: CGImage, width: Int, height: Int) -> PixelImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
    }
    return PixelImage(width: width, height: height, rgba: bytes)
}

public func encodeJPEG(_ image: PixelImage) -> Data {
    let provider = CGDataProvider(data: Data(image.rgba) as CFData)!
    let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return output as Data
}

public struct ScorecardRun {
    public let card: Scorecard
    public let reference: PixelImage
    public let frames: [PixelImage]
}

/// Loads both files and scores the video. Frames are compared at the reference picture's shape.
public func runScorecard(referencePath: String, videoPath: String, thresholds: Thresholds, frameCount: Int = defaultFrameCount) throws -> ScorecardRun {
    let referenceImage = try loadPicture(referencePath)
    let loaded = try loadVideoFrames(videoPath, count: frameCount)

    let height = max(8, Int((Double(analysisWidth) * Double(referenceImage.height) / Double(referenceImage.width)).rounded()))
    let reference = normalize(referenceImage, width: analysisWidth, height: height)
    let frames = try loaded.map {
        SampledFrame(label: $0.label, seconds: $0.seconds, image: normalize($0.image, width: analysisWidth, height: height),
                     overallLook: try overallLookDistance(referenceImage, $0.image))
    }

    var warnings: [String] = []
    let referenceShape = Double(referenceImage.width) / Double(referenceImage.height)
    let videoShape = Double(loaded[0].image.width) / Double(loaded[0].image.height)
    if abs(referenceShape / videoShape - 1) > 0.01 {
        warnings.append("The reference and the video have different shapes, so frames were stretched to match. Background scores may be lower than they should be.")
    }

    let card = try score(referenceFile: URL(fileURLWithPath: referencePath).lastPathComponent,
                         videoFile: URL(fileURLWithPath: videoPath).lastPathComponent,
                         reference: reference, frames: frames, thresholds: thresholds, warnings: warnings)
    return ScorecardRun(card: card, reference: reference, frames: frames.map(\.image))
}
