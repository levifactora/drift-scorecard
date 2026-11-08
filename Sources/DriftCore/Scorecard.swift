import Foundation

public enum ScorecardError: LocalizedError, Equatable {
    case fileNotFound(String)
    case unreadableImage(String)
    case unreadableVideo(String)
    case frameUnavailable(String, Double)
    case referenceTooFlat(String)
    case badArguments(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "Could not find the file: \(path)"
        case .unreadableImage(let path): return "This file could not be opened as a picture: \(path)"
        case .unreadableVideo(let path): return "This file could not be opened as a video: \(path)"
        case .frameUnavailable(let path, let seconds):
            return "Could not read the frame at \(String(format: "%.2f", seconds)) seconds of \(path), so the video was not scored."
        case .referenceTooFlat(let message): return message
        case .badArguments(let message): return message
        }
    }
}

/// Allowed ranges. Saturation and brightness are percent of the reference (100 = identical).
/// Background is percent similarity. A value exactly on a limit passes.
public struct Thresholds: Codable, Equatable {
    public var saturationMin = 85.0
    public var saturationMax = 115.0
    public var brightnessMin = 90.0
    public var brightnessMax = 110.0
    public var backgroundMin = 70.0
    public init() {}
}

public struct Check: Codable, Equatable {
    public let metric: String
    public let value: Double
    public let min: Double
    public let max: Double
    public let passed: Bool
}

public struct FrameResult: Codable, Equatable {
    public let label: String
    public let seconds: Double
    public let checks: [Check]
    public var passed: Bool { checks.allSatisfy(\.passed) }
}

public struct Scorecard: Codable, Equatable {
    public let referenceFile: String
    public let videoFile: String
    public let thresholds: Thresholds
    public let frames: [FrameResult]
    public let warnings: [String]
    public let passed: Bool
}

public struct SampledFrame {
    public let label: String
    public let seconds: Double
    public let image: PixelImage
    public init(label: String, seconds: Double, image: PixelImage) {
        self.label = label
        self.seconds = seconds
        self.image = image
    }
}

/// Reports show one decimal, so judging on the rounded value keeps the number and the verdict in agreement.
private func oneDecimal(_ value: Double) -> Double { (value * 10).rounded() / 10 }

private func check(_ metric: String, _ value: Double, _ low: Double, _ high: Double) -> Check {
    let rounded = oneDecimal(value)
    return Check(metric: metric, value: rounded, min: low, max: high, passed: rounded >= low && rounded <= high)
}

/// Scores already-loaded frames against an already-loaded reference of the same size.
public func score(referenceFile: String, videoFile: String, reference: PixelImage, frames: [SampledFrame],
                  thresholds: Thresholds, warnings: [String] = []) throws -> Scorecard {
    let base = colorStats(reference)
    guard base.saturation >= 0.005 else {
        throw ScorecardError.referenceTooFlat("The reference picture has almost no color (it is black, white or grey), so saturation cannot be compared as a percentage of it.")
    }
    guard base.brightness >= 1 else {
        throw ScorecardError.referenceTooFlat("The reference picture is completely black, so brightness cannot be compared as a percentage of it.")
    }
    let results = frames.map { frame -> FrameResult in
        let stats = colorStats(frame.image)
        return FrameResult(label: frame.label, seconds: frame.seconds, checks: [
            check("Saturation", stats.saturation / base.saturation * 100, thresholds.saturationMin, thresholds.saturationMax),
            check("Brightness", stats.brightness / base.brightness * 100, thresholds.brightnessMin, thresholds.brightnessMax),
            check("Background", backgroundSimilarity(reference, frame.image) * 100, thresholds.backgroundMin, 100),
        ])
    }
    return Scorecard(referenceFile: referenceFile, videoFile: videoFile, thresholds: thresholds, frames: results,
                     warnings: warnings, passed: !results.isEmpty && results.allSatisfy(\.passed))
}

public struct Options: Equatable {
    public var referencePath = ""
    public var videoPath = ""
    public var outputDirectory = "drift-report"
    public var thresholds = Thresholds()
    public var showHelp = false
    public init() {}
}

public let usage = """
Usage: drift-scorecard <reference-picture> <video> [options]

Compares the start, middle and end of a video with a reference picture.
Saturation and brightness are percent of the reference (100 = identical).
Background is percent similarity (100 = identical).

Options (defaults in brackets):
  --saturation-min N   lowest allowed saturation [85]
  --saturation-max N   highest allowed saturation [115]
  --brightness-min N   lowest allowed brightness [90]
  --brightness-max N   highest allowed brightness [110]
  --background-min N   lowest allowed background similarity [70]
  --out FOLDER         where to save the report [drift-report]
  --help               show this message

Exit status: 0 = pass, 1 = fail, 2 = could not run.
"""

public func parseArguments(_ arguments: [String]) throws -> Options {
    var options = Options()
    var files: [String] = []
    var index = 0

    func nextValue(_ flag: String) throws -> String {
        index += 1
        guard index < arguments.count else { throw ScorecardError.badArguments("\(flag) needs a value after it.") }
        return arguments[index]
    }
    func number(_ flag: String) throws -> Double {
        let text = try nextValue(flag)
        guard let value = Double(text), value.isFinite, value >= 0 else {
            throw ScorecardError.badArguments("\(flag) needs a number of 0 or more, but got \"\(text)\".")
        }
        return value
    }

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--saturation-min": options.thresholds.saturationMin = try number(argument)
        case "--saturation-max": options.thresholds.saturationMax = try number(argument)
        case "--brightness-min": options.thresholds.brightnessMin = try number(argument)
        case "--brightness-max": options.thresholds.brightnessMax = try number(argument)
        case "--background-min": options.thresholds.backgroundMin = try number(argument)
        case "--out": options.outputDirectory = try nextValue(argument)
        case "--help", "-h": options.showHelp = true
        default:
            if argument.hasPrefix("--") { throw ScorecardError.badArguments("Unknown option: \(argument)") }
            files.append(argument)
        }
        index += 1
    }
    if options.showHelp { return options }

    guard files.count == 2 else {
        throw ScorecardError.badArguments("Please give exactly two files: the reference picture, then the video.\n\n\(usage)")
    }
    options.referencePath = files[0]
    options.videoPath = files[1]

    let t = options.thresholds
    guard t.saturationMin <= t.saturationMax else { throw ScorecardError.badArguments("--saturation-min cannot be higher than --saturation-max.") }
    guard t.brightnessMin <= t.brightnessMax else { throw ScorecardError.badArguments("--brightness-min cannot be higher than --brightness-max.") }
    guard t.backgroundMin <= 100 else { throw ScorecardError.badArguments("--background-min cannot be higher than 100.") }
    return options
}
