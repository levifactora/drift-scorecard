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
    /// Largest allowed difference in overall look. 0 is identical; higher is less alike.
    public var overallLookMax = 0.45
    public init() {}
}

public struct Check: Codable, Equatable {
    public let metric: String
    public let value: Double
    public let min: Double
    public let max: Double
    public let passed: Bool
    /// Outside the limit, but only just. Treated as unsure rather than a clear failure.
    public let near: Bool
}

public enum Verdict: String, Codable { case pass, unsure, fail }

func verdict(of checks: [Check]) -> Verdict {
    if checks.contains(where: { !$0.passed && !$0.near }) { return .fail }
    return checks.allSatisfy(\.passed) ? .pass : .unsure
}

public struct FrameResult: Codable, Equatable {
    public let label: String
    public let seconds: Double
    public let checks: [Check]
    public var passed: Bool { checks.allSatisfy(\.passed) }
    public var verdict: Verdict { DriftCore.verdict(of: checks) }
}

public struct Scorecard: Codable, Equatable {
    public let referenceFile: String
    public let videoFile: String
    public let thresholds: Thresholds
    public let frames: [FrameResult]
    public let warnings: [String]
    public let passed: Bool
    public let verdict: Verdict
}

public struct SampledFrame {
    public let label: String
    public let seconds: Double
    public let image: PixelImage
    public let overallLook: Double?
    public init(label: String, seconds: Double, image: PixelImage, overallLook: Double? = nil) {
        self.label = label
        self.seconds = seconds
        self.image = image
        self.overallLook = overallLook
    }
}

/// Reports show one decimal, so judging on the rounded value keeps the number and the verdict in agreement.
private func oneDecimal(_ value: Double) -> Double { (value * 10).rounded() / 10 }

/// How far outside a limit still counts as unsure.
public let unsureMargins: [String: Double] = ["Saturation": 3, "Brightness": 3, "Background": 5, "Overall look": 0.03]

private func check(_ metric: String, rounded: Double, _ low: Double, _ high: Double) -> Check {
    let margin = unsureMargins[metric] ?? 0
    let passed = rounded >= low && rounded <= high
    return Check(metric: metric, value: rounded, min: low, max: high, passed: passed, near: !passed && rounded >= low - margin - 1e-9 && rounded <= high + margin + 1e-9)
}

private func check(_ metric: String, _ value: Double, _ low: Double, _ high: Double) -> Check {
    check(metric, rounded: oneDecimal(value), low, high)
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
        var checks = [
            check("Saturation", stats.saturation / base.saturation * 100, thresholds.saturationMin, thresholds.saturationMax),
            check("Brightness", stats.brightness / base.brightness * 100, thresholds.brightnessMin, thresholds.brightnessMax),
            check("Background", backgroundSimilarity(reference, frame.image) * 100, thresholds.backgroundMin, 100),
        ]
        if let look = frame.overallLook {
            checks.append(check("Overall look", rounded: (look * 100).rounded() / 100, 0, thresholds.overallLookMax))
        }
        return FrameResult(label: frame.label, seconds: frame.seconds, checks: checks)
    }
    return Scorecard(referenceFile: referenceFile, videoFile: videoFile, thresholds: thresholds, frames: results,
                     warnings: warnings, passed: !results.isEmpty && results.allSatisfy(\.passed),
                     verdict: results.isEmpty ? .unsure : verdict(of: results.flatMap(\.checks)))
}

public struct Options: Equatable {
    public var referencePath = ""
    public var videoPath = ""
    public var videoPaths: [String] = []
    public var frameCount = defaultFrameCount
    public var decisionsPath: String?
    public var outputDirectory = "drift-report"
    public var thresholds = Thresholds()
    public var showHelp = false
    public init() {}
}

public let defaultFrameCount = 5

/// Named starting limits. Anything you set yourself overrides them.
public func presetThresholds(_ name: String) -> Thresholds? {
    var thresholds = Thresholds()
    switch name {
    case "standard": return thresholds
    case "cartoon":
        // Chosen from one episode of one 3D-style cartoon series. Treat as a starting point.
        thresholds.backgroundMin = 60
        thresholds.overallLookMax = 0.40
        return thresholds
    default: return nil
    }
}

public let usage = """
Usage: drift-scorecard <reference-picture> <video-or-folder>... [options]

Compares evenly spaced frames from each video with a reference picture.
Saturation and brightness are percent of the reference (100 = identical).
Background is percent similarity (100 = identical).
Overall look is a difference score (0 = identical, higher = less alike).
A result just outside a limit is UNSURE, meaning a person should look.

Options (defaults in brackets):
  --preset NAME        starting limits: standard or cartoon [standard]
  --saturation-min N   lowest allowed saturation [85]
  --saturation-max N   highest allowed saturation [115]
  --brightness-min N   lowest allowed brightness [90]
  --brightness-max N   highest allowed brightness [110]
  --background-min N   lowest allowed background similarity [70]
  --overall-look-max N highest allowed overall look difference [0.45]
  --frames N           frames to check in each video, 3 to 25 [\(defaultFrameCount)]
  --decisions FILE     compare results with your own keep/redo decisions
  --out FOLDER         where to save the report [drift-report]
  --help               show this message

A decisions file has one line per clip, such as: keep clip_01.mp4

Exit status: 0 = every clip passed, 1 = a clip failed or is unsure, 2 = could not run.
"""

public func parseArguments(_ arguments: [String]) throws -> Options {
    var options = Options()
    var files: [String] = []
    var index = 0
    if let at = arguments.firstIndex(of: "--preset"), at + 1 < arguments.count {
        guard let preset = presetThresholds(arguments[at + 1]) else {
            throw ScorecardError.badArguments("Unknown preset \"\(arguments[at + 1])\". Choose standard or cartoon.")
        }
        options.thresholds = preset
    }

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
        case "--overall-look-max": options.thresholds.overallLookMax = try number(argument)
        case "--preset": _ = try nextValue(argument)
        case "--decisions": options.decisionsPath = try nextValue(argument)
        case "--frames":
            let text = try nextValue(argument)
            guard let count = Int(text), (3...25).contains(count) else { throw ScorecardError.badArguments("--frames needs a whole number from 3 to 25, but got \"\(text)\".") }
            options.frameCount = count
        case "--out": options.outputDirectory = try nextValue(argument)
        case "--help", "-h": options.showHelp = true
        default:
            if argument.hasPrefix("--") { throw ScorecardError.badArguments("Unknown option: \(argument)") }
            files.append(argument)
        }
        index += 1
    }
    if options.showHelp { return options }

    guard files.count >= 2 else {
        throw ScorecardError.badArguments("Please give the reference picture, then at least one video or folder.\n\n\(usage)")
    }
    options.referencePath = files[0]
    options.videoPaths = Array(files.dropFirst())
    options.videoPath = files[1]

    let t = options.thresholds
    guard t.saturationMin <= t.saturationMax else { throw ScorecardError.badArguments("--saturation-min cannot be higher than --saturation-max.") }
    guard t.brightnessMin <= t.brightnessMax else { throw ScorecardError.badArguments("--brightness-min cannot be higher than --brightness-max.") }
    guard t.backgroundMin <= 100 else { throw ScorecardError.badArguments("--background-min cannot be higher than 100.") }
    return options
}
