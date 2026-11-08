import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let sampleWidth = 640
private let sampleHeight = 360
private let framesPerSecond = 24
private let sampleSeconds = 3

public enum SampleDrift { case none, color, background }

/// Draws a made-up room: wall, window, shelf, floor and a moving ball. `progress` runs 0 to 1.
private func drawScene(_ context: CGContext, progress: Double, drift: SampleDrift) {
    let width = CGFloat(sampleWidth), height = CGFloat(sampleHeight)
    let change = drift == .background ? CGFloat(progress) : 0

    context.saveGState()
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)

    func fill(_ rect: CGRect, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
        context.fill(rect)
    }

    fill(CGRect(x: 0, y: 0, width: width, height: height * 0.68), 0.30 + 0.45 * change, 0.60 - 0.45 * change, 0.62 + 0.10 * change)
    fill(CGRect(x: 60 + 380 * change, y: 24, width: 120, height: 92), 0.72, 0.88, 0.98)
    fill(CGRect(x: 410 - 370 * change, y: 54, width: 170, height: 12), 0.48, 0.32, 0.18)
    fill(CGRect(x: 420 - 370 * change, y: 20, width: 24, height: 34), 0.82, 0.25, 0.22)
    fill(CGRect(x: 452 - 370 * change, y: 26, width: 24, height: 28), 0.95, 0.75, 0.22)
    fill(CGRect(x: 0, y: height * 0.68, width: width, height: height * 0.32), 0.74, 0.52, 0.30)

    context.setFillColor(CGColor(srgbRed: 0.92, green: 0.42, blue: 0.20, alpha: 1))
    context.fillEllipse(in: CGRect(x: 90 + 400 * CGFloat(progress), y: height * 0.62, width: 80, height: 80))
    context.restoreGState()
}

/// Makes colors progressively stronger and darker. Pixels are 4 bytes each; the last byte is never touched.
private func applyColorDrift(_ pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, progress: Double) {
    let saturation = 1 + 0.9 * progress
    let brightness = 1 - 0.3 * progress
    for y in 0..<sampleHeight {
        let row = pixels + y * bytesPerRow
        for x in 0..<sampleWidth {
            let pixel = row + x * 4
            let channels = [Double(pixel[0]), Double(pixel[1]), Double(pixel[2])]
            let grey = channels.reduce(0, +) / 3
            for channel in 0..<3 {
                pixel[channel] = UInt8(min(255, max(0, (grey + (channels[channel] - grey) * saturation) * brightness)))
            }
        }
    }
}

private func writeReferencePicture(to url: URL) throws {
    let context = CGContext(data: nil, width: sampleWidth, height: sampleHeight, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawScene(context, progress: 0, drift: .none)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

private func writeVideo(to url: URL, drift: SampleDrift) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: sampleWidth,
        AVVideoHeightKey: sampleHeight,
        // Label the color encoding so the video decodes back to the colors that were drawn.
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: sampleWidth,
        kCVPixelBufferHeightKey as String: sampleHeight,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)

    let frameCount = framesPerSecond * sampleSeconds
    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData { usleep(1000) }
        guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        var created: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
        guard let buffer = created else { throw CocoaError(.fileWriteUnknown) }

        let progress = Double(frame) / Double(frameCount - 1)
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let context = CGContext(data: base, width: sampleWidth, height: sampleHeight, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        drawScene(context, progress: progress, drift: drift)
        if drift == .color {
            applyColorDrift(base.assumingMemoryBound(to: UInt8.self), bytesPerRow: bytesPerRow, progress: progress)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(framesPerSecond))) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }

    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

/// Creates reference.png, steady.mp4, color-drift.mp4 and background-drift.mp4 in the folder.
public func makeSamples(in directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try writeReferencePicture(to: folder.appendingPathComponent("reference.png"))
    try writeVideo(to: folder.appendingPathComponent("steady.mp4"), drift: .none)
    try writeVideo(to: folder.appendingPathComponent("color-drift.mp4"), drift: .color)
    try writeVideo(to: folder.appendingPathComponent("background-drift.mp4"), drift: .background)
}
