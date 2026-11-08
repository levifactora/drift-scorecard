import Foundation

private func format(_ value: Double) -> String { String(format: "%.1f%%", value) }

private func limit(_ value: Double) -> String {
    value == value.rounded() ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
}

private func allowed(_ check: Check) -> String {
    check.metric == "Background" ? "at least \(limit(check.min))" : "\(limit(check.min)) to \(limit(check.max))"
}

/// One plain sentence for each failed check.
public func failureReasons(_ card: Scorecard) -> [String] {
    card.frames.flatMap { frame in
        frame.checks.filter { !$0.passed }.map { check in
            let measure = check.metric == "Background" ? "similarity to the reference" : "of the reference"
            return "\(frame.label) frame: \(check.metric.lowercased()) is \(format(check.value)) \(measure); allowed is \(allowed(check))."
        }
    }
}

public func textReport(_ card: Scorecard) -> String {
    var lines = [
        "DRIFT SCORECARD",
        "Reference: \(card.referenceFile)",
        "Video:     \(card.videoFile)",
        "",
        "Frame            Saturation  Brightness  Background  Result",
    ]
    for frame in card.frames {
        let name = "\(frame.label) (\(String(format: "%.1f", frame.seconds))s)".padding(toLength: 17, withPad: " ", startingAt: 0)
        let cells = frame.checks.map { format($0.value).padding(toLength: 12, withPad: " ", startingAt: 0) }.joined()
        lines.append(name + cells + (frame.passed ? "PASS" : "FAIL"))
    }
    if let first = card.frames.first {
        let cells = first.checks.map { allowed($0).replacingOccurrences(of: "at least ", with: ">= ").replacingOccurrences(of: " to ", with: "-").replacingOccurrences(of: "%", with: "") }
        lines += ["", "Allowed: saturation \(cells[0]), brightness \(cells[1]), background \(cells[2]) (percent)"]
    }
    let reasons = failureReasons(card)
    if !reasons.isEmpty { lines += ["", "Why it failed:"] + reasons.map { "  - \($0)" } }
    if !card.warnings.isEmpty { lines += ["", "Warnings:"] + card.warnings.map { "  - \($0)" } }
    lines += ["", "OVERALL: \(card.passed ? "PASS" : "FAIL")"]
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

private func dataURL(_ jpeg: Data) -> String { "data:image/jpeg;base64," + jpeg.base64EncodedString() }

public func htmlReport(_ card: Scorecard, referenceJPEG: Data, frameJPEGs: [Data]) -> String {
    let verdict = card.passed ? "PASS" : "FAIL"
    let verdictClass = card.passed ? "pass" : "fail"

    let headers = card.frames.first?.checks.map { "<th>\(escapeHTML($0.metric))<small>allowed: \(escapeHTML(allowed($0)))</small></th>" }.joined() ?? ""
    let rows = card.frames.map { frame -> String in
        let cells = frame.checks.map { "<td class=\"\($0.passed ? "pass" : "fail")\">\(format($0.value))</td>" }.joined()
        let result = frame.passed ? "pass" : "fail"
        return "<tr><th scope=\"row\">\(escapeHTML(frame.label)) <small>\(String(format: "%.1f", frame.seconds))s</small></th>\(cells)<td class=\"\(result)\">\(result.uppercased())</td></tr>"
    }.joined(separator: "\n")

    let figures = zip(card.frames, frameJPEGs).map { frame, jpeg in
        "<figure><img src=\"\(dataURL(jpeg))\" alt=\"\(escapeHTML(frame.label)) frame\"><figcaption>\(escapeHTML(frame.label)) · <span class=\"\(frame.passed ? "pass" : "fail")\">\(frame.passed ? "PASS" : "FAIL")</span></figcaption></figure>"
    }.joined(separator: "\n")

    func list(_ title: String, _ items: [String]) -> String {
        items.isEmpty ? "" : "<h2>\(title)</h2><ul>" + items.map { "<li>\(escapeHTML($0))</li>" }.joined() + "</ul>"
    }

    return """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Drift Scorecard</title>
    <style>
    :root { --bg:#fbfaf7; --ink:#1f2328; --muted:#646b75; --line:#dcd9d1; --pass:#17693c; --fail:#b02a22; }
    @media (prefers-color-scheme: dark) { :root { --bg:#17191c; --ink:#ecebe7; --muted:#a3a9b2; --line:#34383e; --pass:#62cf92; --fail:#ff8d84; } }
    * { box-sizing:border-box; } body { margin:0 auto; max-width:900px; padding:32px 16px; background:var(--bg); color:var(--ink); font:16px/1.5 -apple-system,system-ui,sans-serif; }
    h1 { margin:0; font-size:1.6rem; } h2 { margin-top:2rem; font-size:1.05rem; } .files { color:var(--muted); margin:.25rem 0 1rem; overflow-wrap:anywhere; }
    .verdict { font-size:2.5rem; font-weight:700; margin:.5rem 0; } .pass { color:var(--pass); } .fail { color:var(--fail); font-weight:600; }
    .wrap { overflow-x:auto; } table { width:100%; border-collapse:collapse; font-variant-numeric:tabular-nums; }
    th,td { padding:.55rem .5rem; border-bottom:1px solid var(--line); text-align:left; } small { display:block; color:var(--muted); font-weight:400; }
    .frames { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:12px; } figure { margin:0; } img { width:100%; display:block; border-radius:4px; } figcaption { font-size:.875rem; margin-top:.25rem; }
    </style></head><body>
    <h1>Drift scorecard</h1>
    <p class="files">Reference: \(escapeHTML(card.referenceFile))<br>Video: \(escapeHTML(card.videoFile))</p>
    <p class="verdict \(verdictClass)">\(verdict)</p>
    \(list("Why it failed", failureReasons(card)))
    \(list("Warnings", card.warnings))
    <h2>Measurements</h2>
    <div class="wrap"><table><thead><tr><th>Frame</th>\(headers)<th>Result</th></tr></thead><tbody>
    \(rows)
    </tbody></table></div>
    <h2>What was compared</h2>
    <div class="frames">
    <figure><img src="\(dataURL(referenceJPEG))" alt="Reference picture"><figcaption>Reference</figcaption></figure>
    \(figures)
    </div>
    </body></html>
    """
}

/// Writes report.html and report.json into the folder.
public func saveReports(_ run: ScorecardRun, to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try jsonReport(run.card).write(to: folder.appendingPathComponent("report.json"))
    let html = htmlReport(run.card, referenceJPEG: encodeJPEG(run.reference), frameJPEGs: run.frames.map(encodeJPEG))
    try html.write(to: folder.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}
