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

private func dataURL(_ jpeg: Data) -> String { "data:image/jpeg;base64," + jpeg.base64EncodedString() }

let reportCSS = """
:root { --bg:#fbfaf7; --ink:#1f2328; --muted:#646b75; --line:#dcd9d1; --pass:#17693c; --fail:#b02a22; --unsure:#8a5a00; --series:#2a78d6; --band:rgba(100,107,117,.10); }
@media (prefers-color-scheme: dark) { :root { --bg:#17191c; --ink:#ecebe7; --muted:#a3a9b2; --line:#34383e; --pass:#62cf92; --fail:#ff8d84; --unsure:#f0c063; --series:#3987e5; --band:rgba(163,169,178,.12); } }
* { box-sizing:border-box; } body { margin:0 auto; max-width:900px; padding:32px 16px; background:var(--bg); color:var(--ink); font:16px/1.5 -apple-system,system-ui,sans-serif; }
h1 { margin:0; font-size:1.6rem; } h2 { margin-top:2rem; font-size:1.05rem; } .files { color:var(--muted); margin:.25rem 0 1rem; overflow-wrap:anywhere; }
.verdict { font-size:2.5rem; font-weight:700; margin:.5rem 0; } .pass { color:var(--pass); } .fail { color:var(--fail); font-weight:600; } .unsure { color:var(--unsure); font-weight:600; }
.wrap { overflow-x:auto; } table { width:100%; border-collapse:collapse; font-variant-numeric:tabular-nums; }
th,td { padding:.55rem .5rem; border-bottom:1px solid var(--line); text-align:left; } small { display:block; color:var(--muted); font-weight:400; } a { color:inherit; }
.frames { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:12px; } figure { margin:0; } img { width:100%; display:block; border-radius:4px; } figcaption { font-size:.875rem; margin-top:.25rem; }
.charts { display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:16px; } .chart h3 { margin:0 0 4px; font-size:.9rem; } .chart svg { width:100%; height:auto; display:block; } .chart text { fill:var(--muted); font-size:11px; font-variant-numeric:tabular-nums; }
.hit { fill:var(--line); opacity:0; } .hit:hover { opacity:.55; } .limit { stroke:var(--muted); stroke-width:1; stroke-dasharray:4 3; fill:none; } .limit-band { fill:var(--band); } .line { fill:none; stroke:var(--series); stroke-width:2; stroke-linejoin:round; stroke-linecap:round; pointer-events:none; } .mark { stroke:var(--bg); stroke-width:2; pointer-events:none; } .ok { fill:var(--series); } .near { fill:#fab219; } .out { fill:#d03b3b; }
.note { color:var(--muted); font-size:.875rem; } #tip { position:fixed; z-index:9; pointer-events:none; background:var(--ink); color:var(--bg); padding:4px 8px; border-radius:4px; font-size:.8rem; max-width:260px; }
.chips { list-style:none; display:flex; flex-wrap:wrap; gap:2px; padding:0; } .chip { display:flex; flex-direction:column; align-items:center; justify-content:center; width:40px; height:40px; border-radius:4px; text-decoration:none; font-size:.8rem; font-weight:600; line-height:1.05; } .s-pass { background:#0ca30c; color:#fff; } .s-fail { background:#d03b3b; color:#fff; } .s-unsure { background:#fab219; color:#0b0b0b; } .chip:hover,.chip:focus-visible { outline:2px solid var(--ink); outline-offset:1px; }
"""

let reportScript = #"""
<script>
(function () {
  var tip = document.getElementById("tip");
  if (!tip) return;
  document.addEventListener("mousemove", function (event) {
    var hit = event.target.closest && event.target.closest("[data-tip]");
    if (!hit) { tip.hidden = true; return; }
    tip.textContent = hit.dataset.tip;
    tip.hidden = false;
    tip.style.left = Math.max(4, Math.min(window.innerWidth - tip.offsetWidth - 4, event.clientX + 12)) + "px";
    tip.style.top = Math.max(4, event.clientY - tip.offsetHeight - 10) + "px";
  });
})();
</script>
"""#

public struct ChartPoint {
    public let label: String
    public let value: Double
    public init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

/// One measure against its limits. Each measure has its own chart because their scales differ.
public func miniChart(title: String, points: [ChartPoint], low: Double?, high: Double?, margin: Double, unit: String) -> String {
    guard !points.isEmpty else { return "" }
    let width = 300.0, height = 150.0, left = 38.0, right = 10.0, top = 10.0, bottom = 24.0
    let limits = [low, high].compactMap { $0 }
    let all = points.map(\.value) + limits
    let span = max(all.max()! - all.min()!, 0.01)
    let lowest = all.min()! - span * 0.08, highest = all.max()! + span * 0.08
    func x(_ index: Int) -> Double { points.count == 1 ? (left + width - right) / 2 : left + (width - left - right) * Double(index) / Double(points.count - 1) }
    func y(_ value: Double) -> Double { top + (height - top - bottom) * (highest - value) / (highest - lowest) }
    func show(_ value: Double) -> String { unit == "%" ? String(format: "%.0f%%", value) : String(format: "%.2f", value) }
    func detail(_ value: Double) -> String { unit == "%" ? String(format: "%.1f%%", value) : String(format: "%.2f", value) }
    func state(_ value: Double) -> String {
        let inside = (low.map { value >= $0 } ?? true) && (high.map { value <= $0 } ?? true)
        if inside { return "ok" }
        let close = (low.map { value >= $0 - margin - 1e-9 } ?? true) && (high.map { value <= $0 + margin + 1e-9 } ?? true)
        return close ? "near" : "out"
    }
    let words = ["ok": "within limits", "near": "just outside the limit", "out": "outside the limit"]
    let f = { (v: Double) in String(format: "%.1f", v) }

    let bandTop = y(high ?? highest), bandBottom = y(low ?? lowest)
    var body = "<rect class=\"limit-band\" x=\"\(f(left))\" y=\"\(f(bandTop))\" width=\"\(f(width - left - right))\" height=\"\(f(max(0, bandBottom - bandTop)))\"></rect>"
    for value in limits {
        body += "<line class=\"limit\" x1=\"\(f(left))\" x2=\"\(f(width - right))\" y1=\"\(f(y(value)))\" y2=\"\(f(y(value)))\"></line><text x=\"\(f(left - 5))\" y=\"\(f(y(value) + 4))\" text-anchor=\"end\">\(show(value))</text>"
    }
    let step = points.count > 1 ? (width - left - right) / Double(points.count - 1) : width - left - right
    for (index, point) in points.enumerated() {
        let tip = "\(point.label): \(detail(point.value)), \(words[state(point.value)]!)"
        body += "<rect class=\"hit\" x=\"\(f(x(index) - step / 2))\" y=\"\(f(top))\" width=\"\(f(step))\" height=\"\(f(height - top - bottom))\" data-tip=\"\(escapeHTML(tip))\"></rect>"
    }
    body += "<polyline class=\"line\" points=\"" + points.indices.map { "\(f(x($0))),\(f(y(points[$0].value)))" }.joined(separator: " ") + "\"></polyline>"
    for (index, point) in points.enumerated() {
        let state = state(point.value), cx = x(index), cy = y(point.value)
        // Shape as well as color marks a problem, so it does not depend on seeing red or yellow.
        body += state == "ok" ? "<circle class=\"mark ok\" cx=\"\(f(cx))\" cy=\"\(f(cy))\" r=\"4\"></circle>"
            : "<rect class=\"mark \(state)\" x=\"\(f(cx - 4.5))\" y=\"\(f(cy - 4.5))\" width=\"9\" height=\"9\" transform=\"rotate(45 \(f(cx)) \(f(cy)))\"></rect>"
    }
    body += "<text x=\"\(f(left))\" y=\"\(f(height - 7))\">\(escapeHTML(points.first!.label))</text><text x=\"\(f(width - right))\" y=\"\(f(height - 7))\" text-anchor=\"end\">\(escapeHTML(points.last!.label))</text>"
    let outside = points.filter { state($0.value) != "ok" }.count
    let summary = "\(title) across \(points.count) points; \(outside) outside the limits."
    return "<div class=\"chart\"><h3>\(escapeHTML(title))</h3><svg viewBox=\"0 0 300 150\" role=\"img\" aria-label=\"\(escapeHTML(summary))\">\(body)</svg></div>"
}

public let chartNote = "<p class=\"note\">Shaded area is the allowed range. A circle is within limits; a diamond is outside, yellow if only just. Exact numbers are in the table below.</p><div id=\"tip\" hidden></div>"

private func clipCharts(_ card: Scorecard) -> String {
    guard card.frames.count > 1, let first = card.frames.first else { return "" }
    let charts = first.checks.indices.map { index -> String in
        let sample = first.checks[index]
        let points = card.frames.map { ChartPoint(label: $0.label, value: $0.checks[index].value) }
        let look = sample.metric == "Overall look", background = sample.metric == "Background"
        return miniChart(title: sample.metric, points: points, low: look ? nil : sample.min, high: background ? nil : sample.max,
                         margin: unsureMargins[sample.metric] ?? 0, unit: look ? "" : "%")
    }.joined()
    return "<h2>Drift over time</h2><div class=\"charts\">\(charts)</div>\(chartNote)"
}

public func htmlReport(_ card: Scorecard, referenceJPEG: Data, frameJPEGs: [Data], backLink: String? = nil) -> String {
    let word = verdictWord(card.verdict)
    func cls(_ verdict: Verdict) -> String { verdict.rawValue }

    let headers = card.frames.first?.checks.map { "<th>\(escapeHTML($0.metric))<small>allowed: \(escapeHTML(allowed($0)))</small></th>" }.joined() ?? ""
    let rows = card.frames.map { frame -> String in
        let cells = frame.checks.map { "<td class=\"\($0.passed ? "pass" : $0.near ? "unsure" : "fail")\">\(format($0))</td>" }.joined()
        return "<tr><th scope=\"row\">\(escapeHTML(frame.label)) <small>\(String(format: "%.1f", frame.seconds))s</small></th>\(cells)<td class=\"\(cls(frame.verdict))\">\(verdictWord(frame.verdict))</td></tr>"
    }.joined(separator: "\n")

    let figures = zip(card.frames, frameJPEGs).map { frame, jpeg in
        "<figure><img src=\"\(dataURL(jpeg))\" alt=\"\(escapeHTML(frame.label)) frame\"><figcaption>\(escapeHTML(frame.label)) · <span class=\"\(cls(frame.verdict))\">\(verdictWord(frame.verdict))</span></figcaption></figure>"
    }.joined(separator: "\n")

    func list(_ title: String, _ items: [String]) -> String {
        items.isEmpty ? "" : "<h2>\(title)</h2><ul>" + items.map { "<li>\(escapeHTML($0))</li>" }.joined() + "</ul>"
    }
    let back = backLink.map { "<p class=\"note\"><a href=\"\(escapeHTML($0))\">All clips</a></p>" } ?? ""
    let unsureNote = card.verdict == .unsure ? "<p class=\"note\">Only just outside a limit, so a person should look.</p>" : ""

    return """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Drift Scorecard</title>
    <style>\(reportCSS)</style></head><body>
    \(back)<h1>Drift scorecard</h1>
    <p class="files">Reference: \(escapeHTML(card.referenceFile))<br>Video: \(escapeHTML(card.videoFile))</p>
    <p class="verdict \(cls(card.verdict))">\(word)</p>\(unsureNote)
    \(list(card.verdict == .unsure ? "Close to a limit" : "Why it failed", failureReasons(card)))
    \(list("Warnings", card.warnings))
    \(clipCharts(card))
    <h2>Measurements</h2>
    <div class="wrap"><table><thead><tr><th>Frame</th>\(headers)<th>Result</th></tr></thead><tbody>
    \(rows)
    </tbody></table></div>
    <h2>What was compared</h2>
    <div class="frames">
    <figure><img src="\(dataURL(referenceJPEG))" alt="Reference picture"><figcaption>Reference</figcaption></figure>
    \(figures)
    </div>
    \(reportScript)
    </body></html>
    """
}

/// Writes report.html and report.json into the folder.
public func saveReports(_ run: ScorecardRun, to directory: String, backLink: String? = nil) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try jsonReport(run.card).write(to: folder.appendingPathComponent("report.json"))
    let html = htmlReport(run.card, referenceJPEG: encodeJPEG(run.reference), frameJPEGs: run.frames.map(encodeJPEG), backLink: backLink)
    try html.write(to: folder.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
}
