import Foundation

public struct ClipOutcome: Codable, Equatable {
    public let file: String
    public let card: Scorecard?
    public let error: String?
    public init(file: String, card: Scorecard?, error: String?) {
        self.file = file
        self.card = card
        self.error = error
    }
    /// A clip that could not be read is never a pass.
    public var verdict: Verdict { card?.verdict ?? .unsure }
}

public func listVideos(in folder: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder)
        .filter { ["mp4", "mov", "m4v"].contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        .map { (folder as NSString).appendingPathComponent($0) }
}

/// Turns videos and folders into a list of videos. `batch` is true unless the input is one video.
public func expandInputs(_ inputs: [String]) throws -> (videos: [String], batch: Bool) {
    var videos: [String] = []
    var sawFolder = false
    for input in inputs {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input, isDirectory: &isFolder) else { throw ScorecardError.fileNotFound(input) }
        if isFolder.boolValue {
            sawFolder = true
            videos += try listVideos(in: input)
        } else {
            videos.append(input)
        }
    }
    guard !videos.isEmpty else { throw ScorecardError.badArguments("No videos were found. Supported types are MP4, MOV and M4V.") }
    return (videos, sawFolder || videos.count > 1)
}

/// The value furthest from a perfect match, for one clip and one measure.
func worstValue(_ card: Scorecard, _ metric: String) -> Double? {
    let values = card.frames.flatMap { $0.checks.filter { $0.metric == metric }.map(\.value) }
    switch metric {
    case "Background": return values.min()
    case "Overall look": return values.max()
    default: return values.max { abs($0 - 100) < abs($1 - 100) }
    }
}

public func runBatch(referencePath: String, videos: [String], thresholds: Thresholds, frameCount: Int, outputDirectory: String) -> [ClipOutcome] {
    videos.enumerated().map { index, video in
        let name = URL(fileURLWithPath: video).lastPathComponent
        do {
            let run = try runScorecard(referencePath: referencePath, videoPath: video, thresholds: thresholds, frameCount: frameCount)
            try saveReports(run, to: "\(outputDirectory)/clips/\(index + 1)", backLink: "../../report.html")
            return ClipOutcome(file: name, card: run.card, error: nil)
        } catch {
            return ClipOutcome(file: name, card: nil, error: error.localizedDescription)
        }
    }
}

private let verdictIcons: [Verdict: String] = [.pass: "✓", .unsure: "?", .fail: "✕"]

public func batchText(_ outcomes: [ClipOutcome]) -> String {
    var lines = ["DRIFT SCORECARD", ""]
    for outcome in outcomes {
        lines.append(outcome.verdict.rawValue.uppercased().padding(toLength: 9, withPad: " ", startingAt: 0) + outcome.file)
        if let error = outcome.error { lines.append("    - \(error)") }
    }
    func count(_ verdict: Verdict) -> Int { outcomes.filter { $0.verdict == verdict }.count }
    lines += ["", "Passed \(count(.pass)), unsure \(count(.unsure)), failed \(count(.fail)), of \(outcomes.count) clips."]
    return lines.joined(separator: "\n")
}

public func batchHTML(_ outcomes: [ClipOutcome], referenceFile: String, thresholds: Thresholds) -> String {
    func count(_ verdict: Verdict) -> Int { outcomes.filter { $0.verdict == verdict }.count }
    let chips = outcomes.enumerated().map { index, outcome -> String in
        let text = escapeHTML("Clip \(index + 1), \(outcome.file): \(outcome.verdict.rawValue)")
        let target = outcome.card == nil ? "#row-\(index + 1)" : "clips/\(index + 1)/report.html"
        return "<li><a class=\"chip s-\(outcome.verdict.rawValue)\" href=\"\(target)\" title=\"\(text)\" aria-label=\"\(text)\"><span aria-hidden=\"true\">\(index + 1)</span><span aria-hidden=\"true\">\(verdictIcons[outcome.verdict]!)</span></a></li>"
    }.joined()

    let metrics = ["Saturation", "Brightness", "Background", "Overall look"]
    let measured = outcomes.enumerated().filter { $0.element.card != nil }
    var charts = ""
    if measured.count > 1 {
        charts = metrics.map { metric -> String in
            let points = measured.compactMap { index, outcome -> ChartPoint? in
                worstValue(outcome.card!, metric).map { ChartPoint(label: "Clip \(index + 1)", value: $0) }
            }
            let look = metric == "Overall look"
            let low: Double?, high: Double?
            switch metric {
            case "Saturation": (low, high) = (thresholds.saturationMin, thresholds.saturationMax)
            case "Brightness": (low, high) = (thresholds.brightnessMin, thresholds.brightnessMax)
            case "Background": (low, high) = (thresholds.backgroundMin, nil)
            default: (low, high) = (nil, thresholds.overallLookMax)
            }
            return miniChart(title: metric, points: points, low: low, high: high, margin: unsureMargins[metric] ?? 0, unit: look ? "" : "%")
        }.joined()
        charts = "<h2>Drift across clips</h2><p class=\"note\">Each point is that clip's worst frame.</p><div class=\"charts\">\(charts)</div>\(chartNote)"
    }

    let rows = outcomes.enumerated().map { index, outcome -> String in
        let number = index + 1
        let name = escapeHTML(outcome.file)
        let link = outcome.card == nil ? name : "<a href=\"clips/\(number)/report.html\">\(name)</a>"
        func cell(_ metric: String) -> String {
            guard let card = outcome.card, let value = worstValue(card, metric) else { return "<td>n/a</td>" }
            return "<td>" + (metric == "Overall look" ? String(format: "%.2f", value) : String(format: "%.1f%%", value)) + "</td>"
        }
        let error = outcome.error.map { "<small>\(escapeHTML($0))</small>" } ?? ""
        return "<tr id=\"row-\(number)\"><th scope=\"row\">\(number)</th><td>\(link)\(error)</td>\(metrics.map(cell).joined())<td class=\"\(outcome.verdict.rawValue)\">\(outcome.verdict.rawValue.uppercased())</td></tr>"
    }.joined(separator: "\n")

    return """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Drift Scorecard</title><style>\(reportCSS)</style></head><body>
    <h1>Drift scorecard</h1>
    <p class="files">Reference: \(escapeHTML(referenceFile))</p>
    <p>Passed \(count(.pass)) · Unsure \(count(.unsure)) · Failed \(count(.fail)) · \(outcomes.count) clips</p>
    <ol class="chips">\(chips)</ol>
    \(charts)
    <h2>Every clip</h2>
    <div class="wrap"><table><thead><tr><th>#</th><th>Clip</th>\(metrics.map { "<th>\($0)<small>worst frame</small></th>" }.joined())<th>Result</th></tr></thead><tbody>
    \(rows)
    </tbody></table></div>
    \(reportScript)
    </body></html>
    """
}

public func saveBatch(_ outcomes: [ClipOutcome], referenceFile: String, thresholds: Thresholds, to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(outcomes).write(to: folder.appendingPathComponent("report.json"))
    try batchHTML(outcomes, referenceFile: referenceFile, thresholds: thresholds).write(to: folder.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}

public enum ClipDecision: String, Codable { case keep, redo }

/// Reads lines such as "keep clip_01.mp4". A later line for the same clip replaces an earlier one.
public func parseDecisions(_ text: String) throws -> [String: ClipDecision] {
    var decisions: [String: ClipDecision] = [:]
    for raw in text.components(separatedBy: .newlines) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let decision = ClipDecision(rawValue: parts[0].lowercased()) else {
            throw ScorecardError.badArguments("This decisions line could not be read: \(line)")
        }
        decisions[parts[1].trimmingCharacters(in: .whitespaces)] = decision
    }
    return decisions
}

public struct Evaluation: Equatable {
    public var keptPass = 0, keptUnsure = 0, keptFail = 0
    public var redoPass = 0, redoUnsure = 0, redoFail = 0
    public var total: Int { keptPass + keptUnsure + keptFail + redoPass + redoUnsure + redoFail }
    public var kept: Int { keptPass + keptUnsure + keptFail }
    public var redone: Int { redoPass + redoUnsure + redoFail }
    public var clearlyRight: Int { keptPass + redoFail }
    public var clearlyWrong: Int { keptFail + redoPass }
    public var unsure: Int { keptUnsure + redoUnsure }
}

public func evaluate(_ outcomes: [ClipOutcome], decisions: [String: ClipDecision]) throws -> Evaluation {
    var result = Evaluation()
    for outcome in outcomes {
        guard let decision = decisions[outcome.file] else { continue }
        switch (decision, outcome.verdict) {
        case (.keep, .pass): result.keptPass += 1
        case (.keep, .unsure): result.keptUnsure += 1
        case (.keep, .fail): result.keptFail += 1
        case (.redo, .pass): result.redoPass += 1
        case (.redo, .unsure): result.redoUnsure += 1
        case (.redo, .fail): result.redoFail += 1
        }
    }
    guard result.total > 0 else { throw ScorecardError.badArguments("None of the decisions matched a checked clip. Use the exact file names.") }
    return result
}

public func evaluationText(_ e: Evaluation) -> String {
    let blunt = max(e.kept, e.redone)
    return """
    ACCURACY AGAINST YOUR DECISIONS
    Clips you kept (\(e.kept)):   passed \(e.keptPass), unsure \(e.keptUnsure), failed \(e.keptFail)
    Clips you redid (\(e.redone)): failed \(e.redoFail), unsure \(e.redoUnsure), passed \(e.redoPass)

    Clearly right: \(e.clearlyRight) of \(e.total)
    Clearly wrong: \(e.clearlyWrong) of \(e.total)
    Left to a person: \(e.unsure) of \(e.total)
    Giving every clip your most common decision would get \(blunt) of \(e.total) right.
    """
}
