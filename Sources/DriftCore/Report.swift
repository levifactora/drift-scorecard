import Foundation

private func format(_ check: Check) -> String {
    check.metric == "Overall look" ? String(format: "%.2f", check.value) : String(format: "%.1f%%", check.value)
}

private func limit(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
}

private func allowed(_ check: Check) -> String {
    switch check.metric {
    case "Overall look": return String(format: "at most %.2f", check.max)
    case "Background": return "at least \(limit(check.min))"
    default: return "\(limit(check.min)) to \(limit(check.max))"
    }
}

/// One plain sentence for each check outside its limit.
public func failureReasons(_ card: Scorecard) -> [String] {
    card.frames.flatMap { frame in
        frame.checks.filter { !$0.passed }.map { check in
            let measure: String
            switch check.metric {
            case "Overall look": measure = "difference from the reference"
            case "Background": measure = "similarity to the reference"
            default: measure = "of the reference"
            }
            return "\(frame.label) frame: \(check.metric.lowercased()) is \(format(check)) \(measure); allowed is \(allowed(check))\(check.near ? " (only just outside)" : "")."
        }
    }
}

func verdictWord(_ verdict: Verdict) -> String { verdict.rawValue.uppercased() }

public func textReport(_ card: Scorecard) -> String {
    let names = card.frames.first?.checks.map(\.metric) ?? []
    var lines = [
        "DRIFT SCORECARD",
        "Reference: \(card.referenceFile)",
        "Video:     \(card.videoFile)",
        "",
        "Frame            " + names.map { $0.padding(toLength: 14, withPad: " ", startingAt: 0) }.joined() + "Result",
    ]
    for frame in card.frames {
        let name = "\(frame.label) (\(String(format: "%.1f", frame.seconds))s)".padding(toLength: 17, withPad: " ", startingAt: 0)
        let cells = frame.checks.map { format($0).padding(toLength: 14, withPad: " ", startingAt: 0) }.joined()
        lines.append(name + cells + verdictWord(frame.verdict))
    }
    if let first = card.frames.first {
        lines += ["", "Allowed: " + first.checks.map { "\($0.metric.lowercased()) \(allowed($0))" }.joined(separator: ", ")]
    }
    let reasons = failureReasons(card)
    if !reasons.isEmpty { lines += ["", card.verdict == .unsure ? "Close to a limit:" : "Why it failed:"] + reasons.map { "  - \($0)" } }
    if !card.warnings.isEmpty { lines += ["", "Warnings:"] + card.warnings.map { "  - \($0)" } }
    lines += ["", "OVERALL: \(verdictWord(card.verdict))" + (card.verdict == .unsure ? " (a person should look)" : "")]
    return lines.joined(separator: "\n")
}

public func jsonReport(_ card: Scorecard) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(card)
}

public func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}

/// Writes report.html and report.json into the folder.
public func saveReports(_ run: ScorecardRun, to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try jsonReport(run.card).write(to: folder.appendingPathComponent("report.json"))
    let clip = makeReportClip(file: run.card.videoFile, card: run.card, error: nil, images: run.frames.map(encodeJPEG))
    let html = interactiveHTML(clips: [clip], referenceFile: run.card.referenceFile, referenceJPEG: encodeJPEG(run.reference), thresholds: run.card.thresholds)
    try html.write(to: folder.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}
