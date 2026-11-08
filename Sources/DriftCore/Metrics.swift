import Foundation

/// A picture as raw red/green/blue/alpha bytes. Row 0 is the top of the picture.
public struct PixelImage {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "pixel buffer does not match its size")
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public struct ColorStats: Equatable {
    /// Average colorfulness, 0 (grey) to 1 (pure color).
    public let saturation: Double
    /// Average lightness, 0 (black) to 255 (white).
    public let brightness: Double
}

/// Averages each pixel's saturation, (max - min) / max, and brightness, (R + G + B) / 3.
public func colorStats(_ image: PixelImage) -> ColorStats {
    var saturationTotal = 0.0
    var brightnessTotal = 0.0
    for i in stride(from: 0, to: image.rgba.count, by: 4) {
        let r = Double(image.rgba[i]), g = Double(image.rgba[i + 1]), b = Double(image.rgba[i + 2])
        let high = max(r, g, b), low = min(r, g, b)
        saturationTotal += high > 0 ? (high - low) / high : 0
        brightnessTotal += (r + g + b) / 3
    }
    let count = max(1.0, Double(image.width * image.height))
    return ColorStats(saturation: saturationTotal / count, brightness: brightnessTotal / count)
}

/// Where the background is assumed to be: a band across the top of the frame,
/// which subjects rarely cover, split into a grid so a moved or missing object counts.
public struct BackgroundRegion {
    public var heightFraction = 0.35
    public var columns = 4
    public var rows = 2
    public init() {}
}

/// 64-bin color histogram (4 levels per channel) for each grid cell, as fractions of that cell.
func cellHistograms(_ image: PixelImage, region: BackgroundRegion) -> [[Double]] {
    let bandHeight = Int(Double(image.height) * region.heightFraction)
    var histograms: [[Double]] = []
    for row in 0..<region.rows {
        for column in 0..<region.columns {
            var bins = [Double](repeating: 0, count: 64)
            var count = 0.0
            for y in (row * bandHeight / region.rows)..<((row + 1) * bandHeight / region.rows) {
                for x in (column * image.width / region.columns)..<((column + 1) * image.width / region.columns) {
                    let i = (y * image.width + x) * 4
                    let bin = Int(image.rgba[i] >> 6) << 4 | Int(image.rgba[i + 1] >> 6) << 2 | Int(image.rgba[i + 2] >> 6)
                    bins[bin] += 1
                    count += 1
                }
            }
            histograms.append(count > 0 ? bins.map { $0 / count } : bins)
        }
    }
    return histograms
}

/// 0 to 1: how much of each grid cell's colors match the same cell in the reference, averaged.
/// Both images must be the same size.
public func backgroundSimilarity(_ reference: PixelImage, _ frame: PixelImage, region: BackgroundRegion = BackgroundRegion()) -> Double {
    precondition(reference.width == frame.width && reference.height == frame.height, "images must be the same size")
    let a = cellHistograms(reference, region: region)
    let b = cellHistograms(frame, region: region)
    var total = 0.0
    for (cellA, cellB) in zip(a, b) {
        total += zip(cellA, cellB).reduce(0.0) { $0 + min($1.0, $1.1) }
    }
    return total / Double(a.count)
}
