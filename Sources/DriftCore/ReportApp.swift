import CryptoKit
import Foundation

public struct ReportFrame: Codable, Equatable {
    public let label: String
    public let seconds: Double
    public let image: String
    public let values: [String: Double]
}

public struct ReportClip: Codable, Equatable {
    public let file: String
    public let verdict: Verdict
    public let error: String?
    public let warnings: [String]
    public let frames: [ReportFrame]
}

/// Combines a clip's results and frame pictures into what the report shows.
public func makeReportClip(file: String, card: Scorecard?, error: String?, images: [Data]) -> ReportClip {
    let frames = (card?.frames ?? []).enumerated().map { index, frame -> ReportFrame in
        let image = images.indices.contains(index) ? "data:image/jpeg;base64," + images[index].base64EncodedString() : ""
        return ReportFrame(label: frame.label, seconds: frame.seconds, image: image,
                           values: Dictionary(uniqueKeysWithValues: frame.checks.map { ($0.metric, $0.value) }))
    }
    return ReportClip(file: file, verdict: card?.verdict ?? .unsure, error: error, warnings: card?.warnings ?? [], frames: frames)
}

struct ReportPayload: Codable {
    let id: String
    let referenceFile: String
    let referenceImage: String
    let thresholds: Thresholds
    let presets: [String: Thresholds]
    let margins: [String: Double]
    let clips: [ReportClip]
}

/// Builds the self-contained interactive report. All text reaches the page as data and is shown with escaping.
public func interactiveHTML(clips: [ReportClip], referenceFile: String, referenceJPEG: Data?, thresholds: Thresholds) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let summary = clips.map { [$0.file, $0.verdict.rawValue] + $0.frames.map { "\($0.values.sorted { $0.key < $1.key })" } }
    let identity = (try? encoder.encode(summary)) ?? Data()
    let id = SHA256.hash(data: identity).prefix(8).map { String(format: "%02x", $0) }.joined()
    let payload = ReportPayload(id: id, referenceFile: referenceFile,
                                referenceImage: referenceJPEG.map { "data:image/jpeg;base64," + $0.base64EncodedString() } ?? "",
                                thresholds: thresholds,
                                presets: ["Standard": presetThresholds("standard")!, "Cartoon": presetThresholds("cartoon")!],
                                margins: unsureMargins, clips: clips)
    let json = ((try? encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
        .replacingOccurrences(of: "<", with: "\\u003c")
    return """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Drift Scorecard</title><style>\(appCSS)</style></head><body>
    \(appMarkup)
    <script id="data" type="application/json">\(json)</script>
    <script>\(appScript)</script>
    </body></html>
    """
}

let appMarkup = #"""
<header class="top">
  <div class="brand"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 17c4 0 4-9 9-9s4 5 9 3"/></svg><span>Drift Scorecard</span></div>
  <div class="top-actions">
    <button class="ghost" id="help-open" title="Keyboard shortcuts">Shortcuts</button>
    <button class="ghost" id="theme" title="Change theme">Auto</button>
  </div>
</header>
<main>
  <section class="hero">
    <div class="hero-text"><p class="eyebrow" id="ref-name"></p><h1 id="headline"></h1><p class="sub" id="subline"></p></div>
    <img id="ref-image" alt="Reference picture">
  </section>
  <section class="tiles" aria-live="polite">
    <button class="tile" data-filter="pass"><span class="icon s-pass" aria-hidden="true">✓</span><b id="n-pass">0</b><span>Passed</span></button>
    <button class="tile" data-filter="unsure"><span class="icon s-unsure" aria-hidden="true">?</span><b id="n-unsure">0</b><span>Unsure</span></button>
    <button class="tile" data-filter="fail"><span class="icon s-fail" aria-hidden="true">✕</span><b id="n-fail">0</b><span>Failed</span></button>
  </section>
  <div class="bar" id="bar" aria-hidden="true"><i class="s-pass"></i><i class="s-unsure"></i><i class="s-fail"></i></div>
  <ol class="chips" id="chips" aria-label="Clips in order"></ol>

  <section class="panel" id="limits-panel">
    <div class="panel-head"><div><h2>Live limits</h2><p class="muted">Drag to see every result update instantly. Your files are not changed.</p></div>
      <div class="seg" id="presets" role="group" aria-label="Preset limits"></div></div>
    <div class="sliders" id="sliders"></div>
    <div class="row"><button class="ghost" id="reset">Reset to this run</button><button class="ghost" id="copy-limits">Copy these limits</button></div>
  </section>

  <section class="panel hidden" id="accuracy-panel">
    <div class="panel-head"><div><h2>Accuracy against your decisions</h2><p class="muted" id="accuracy-note"></p></div></div>
    <div class="stats" id="accuracy"></div>
  </section>

  <section class="panel" id="charts-panel">
    <div class="panel-head"><div><h2>Drift across clips</h2><p class="muted">Each point is that clip's worst frame. Click a point to open the clip.</p></div></div>
    <div class="charts" id="charts"></div>
    <p class="muted key-line">Shaded area is the allowed range. Circle: within limits. Diamond: outside, yellow if only just.</p>
  </section>

  <section id="browse">
    <div class="toolbar">
      <div class="seg" id="filters" role="group" aria-label="Filter clips"></div>
      <input id="search" type="search" placeholder="Search clips" aria-label="Search clips">
      <select id="sort" aria-label="Sort clips">
        <option value="order">Original order</option><option value="worst">Biggest problems first</option>
        <option value="Saturation">Saturation</option><option value="Brightness">Brightness</option><option value="Background">Background</option><option value="Overall look">Overall look</option>
      </select>
      <div class="seg" id="views" role="group" aria-label="View"><button data-view="grid" aria-pressed="true">Cards</button><button data-view="table" aria-pressed="false">Table</button></div>
      <div class="menu"><button class="ghost" id="export-csv">CSV</button><button class="ghost" id="export-decisions">Decisions</button></div>
    </div>
    <p class="muted" id="result-count" role="status"></p>
    <div class="grid" id="grid"></div>
    <div class="wrap hidden" id="table-wrap"><table><thead id="thead"></thead><tbody id="tbody"></tbody></table></div>
  </section>
</main>

<dialog id="detail" aria-labelledby="d-title">
  <div class="d-head"><div class="d-title"><span class="badge" id="d-badge"></span><h2 id="d-title"></h2></div>
    <div class="d-nav"><button class="ghost" id="d-prev" aria-label="Previous clip">←</button><span class="muted" id="d-pos"></span><button class="ghost" id="d-next" aria-label="Next clip">→</button><button class="ghost" id="d-close" aria-label="Close">✕</button></div></div>
  <div class="d-body">
    <div class="d-stage">
      <div class="compare" id="compare">
        <img id="c-frame" alt=""><div class="c-top" id="c-top"><img id="c-ref" alt="Reference picture"></div>
        <div class="c-handle" id="c-handle" aria-hidden="true"><span>⇆</span></div>
        <span class="c-tag left">Reference</span><span class="c-tag right" id="c-label"></span>
        <input id="c-range" type="range" min="0" max="100" value="50" aria-label="Compare reference with frame">
      </div>
      <div class="strip" id="strip" role="group" aria-label="Frames"></div>
      <div class="charts small" id="d-charts"></div>
    </div>
    <aside class="d-side">
      <div class="seg wide" role="group" aria-label="Your decision"><button id="keep" aria-pressed="false">Keep <kbd>1</kbd></button><button id="redo" aria-pressed="false">Redo <kbd>2</kbd></button></div>
      <h3>This frame</h3><table class="mini"><tbody id="d-values"></tbody></table>
      <h3 id="d-reason-title"></h3><ul id="d-reasons"></ul>
    </aside>
  </div>
</dialog>

<dialog id="help" aria-labelledby="help-title">
  <h2 id="help-title">Keyboard shortcuts</h2>
  <dl><dt><kbd>/</kbd></dt><dd>Search</dd><dt><kbd>J</kbd> <kbd>K</kbd></dt><dd>Next or previous clip</dd><dt><kbd>←</kbd> <kbd>→</kbd></dt><dd>Previous or next frame</dd><dt><kbd>1</kbd> <kbd>2</kbd></dt><dd>Keep or redo</dd><dt><kbd>Esc</kbd></dt><dd>Close</dd></dl>
  <button class="ghost" id="help-close">Close</button>
</dialog>
<div id="tip" hidden></div><div id="toast" role="status" hidden></div>
"""#

let appCSS = #"""
:root{--bg:#f6f5f1;--surface:#fff;--surface2:#efede7;--ink:#17191d;--muted:#666c76;--line:#e2dfd7;--series:#2a78d6;--band:rgba(90,98,110,.11);--pass:#17693c;--unsure:#8a5a00;--fail:#b02a22;--shadow:0 1px 2px rgba(20,20,25,.05),0 12px 32px rgba(20,20,25,.07);color-scheme:light}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#0e0f12;--surface:#17191e;--surface2:#21242b;--ink:#eeede9;--muted:#a0a6b0;--line:#2b2f37;--series:#3987e5;--band:rgba(170,176,186,.12);--pass:#62cf92;--unsure:#f0c063;--fail:#ff8d84;--shadow:0 1px 2px rgba(0,0,0,.3),0 14px 36px rgba(0,0,0,.35);color-scheme:dark}}
:root[data-theme=dark]{--bg:#0e0f12;--surface:#17191e;--surface2:#21242b;--ink:#eeede9;--muted:#a0a6b0;--line:#2b2f37;--series:#3987e5;--band:rgba(170,176,186,.12);--pass:#62cf92;--unsure:#f0c063;--fail:#ff8d84;--shadow:0 1px 2px rgba(0,0,0,.3),0 14px 36px rgba(0,0,0,.35);color-scheme:dark}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:1180px;margin:0 auto;padding:8px 24px 72px}h1,h2,h3,p{margin:0}.muted{color:var(--muted);font-size:.875rem}.hidden{display:none!important}
.top{position:sticky;top:0;z-index:5;display:flex;justify-content:space-between;align-items:center;padding:12px 24px;background:color-mix(in srgb,var(--bg) 82%,transparent);-webkit-backdrop-filter:saturate(1.6) blur(16px);backdrop-filter:saturate(1.6) blur(16px)}
.brand{display:flex;gap:8px;align-items:center;font-weight:650;letter-spacing:-.01em}.brand svg{width:22px;height:22px;fill:none;stroke:var(--series);stroke-width:2.4;stroke-linecap:round}.top-actions,.row,.menu{display:flex;gap:8px;flex-wrap:wrap}
button,select,input[type=search]{font:inherit;color:inherit}button{cursor:pointer}.ghost,select,input[type=search]{background:var(--surface);border:1px solid var(--line);border-radius:9px;padding:6px 12px;transition:border-color .15s,background .15s,transform .1s}.ghost:hover,select:hover{border-color:var(--muted)}.ghost:active{transform:scale(.97)}:focus-visible{outline:2px solid var(--series);outline-offset:2px}
.hero{display:flex;justify-content:space-between;align-items:center;gap:32px;padding:32px 0 24px}.eyebrow{color:var(--muted);font-size:.8rem;overflow-wrap:anywhere}h1{font-size:clamp(2rem,5.2vw,3.5rem);line-height:1.04;letter-spacing:-.035em;font-weight:720;margin:.25rem 0 .5rem}.sub{color:var(--muted);font-size:1.05rem}#ref-image{width:min(280px,32vw);aspect-ratio:16/9;object-fit:cover;border-radius:14px;box-shadow:var(--shadow)}
.tiles{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.tile{display:grid;grid-template-columns:auto 1fr;grid-template-rows:auto auto;column-gap:12px;align-items:center;text-align:left;background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:16px 18px;transition:transform .15s,box-shadow .15s,border-color .15s}.tile:hover{transform:translateY(-2px);box-shadow:var(--shadow)}.tile[aria-pressed=true]{border-color:var(--series)}.tile .icon{grid-row:span 2}.tile b{font-size:1.9rem;line-height:1.1;font-variant-numeric:tabular-nums;letter-spacing:-.02em}.tile span:last-child{color:var(--muted);font-size:.875rem}
.icon,.badge{display:inline-flex;align-items:center;justify-content:center;font-weight:700}.icon{width:34px;height:34px;border-radius:10px;font-size:1rem}.s-pass{background:#0ca30c;color:#fff}.s-unsure{background:#fab219;color:#0b0b0b}.s-fail{background:#d03b3b;color:#fff}
.bar{display:flex;gap:2px;height:8px;margin:14px 0}.bar i{display:block;border-radius:4px;flex:0 0 auto;width:0;transition:width .3s cubic-bezier(.2,.8,.2,1)}
.chips{list-style:none;display:flex;flex-wrap:wrap;gap:3px;padding:0;margin:0 0 24px}.chip{width:38px;height:38px;border:0;border-radius:8px;font-size:.78rem;font-weight:650;display:flex;flex-direction:column;align-items:center;justify-content:center;line-height:1.05;transition:transform .12s,background .2s}.chip:hover{transform:scale(1.12)}.chip small{font-size:.65rem}
.panel{background:var(--surface);border:1px solid var(--line);border-radius:16px;padding:20px;margin-bottom:16px}.panel-head{display:flex;justify-content:space-between;align-items:flex-start;gap:16px;flex-wrap:wrap;margin-bottom:14px}h2{font-size:1.05rem;letter-spacing:-.01em}
.seg{display:inline-flex;background:var(--surface2);border-radius:10px;padding:3px;gap:2px}.seg button{border:0;background:transparent;border-radius:8px;padding:5px 12px;color:var(--muted);transition:background .15s,color .15s}.seg button[aria-pressed=true]{background:var(--surface);color:var(--ink);box-shadow:0 1px 3px rgba(0,0,0,.14)}.seg.wide{display:flex;margin-bottom:16px}.seg.wide button{flex:1;padding:9px}
.sliders{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:14px 28px;margin-bottom:14px}.slider label{display:flex;justify-content:space-between;font-size:.875rem}.slider output{font-variant-numeric:tabular-nums;font-weight:600}input[type=range]{width:100%;accent-color:var(--series)}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}.stat b{display:block;font-size:1.6rem;letter-spacing:-.02em;font-variant-numeric:tabular-nums}.stat span{color:var(--muted);font-size:.875rem}
.charts{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}.chart h3{font-size:.875rem;margin-bottom:4px}.chart svg{width:100%;height:auto;display:block;touch-action:pan-y}.chart text{fill:var(--muted);font-size:11px;font-variant-numeric:tabular-nums}.charts.small{grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin-top:16px}.band{fill:var(--band)}.limit{stroke:var(--muted);stroke-dasharray:4 3}.line{fill:none;stroke:var(--series);stroke-width:2;stroke-linejoin:round;stroke-linecap:round}.mark{stroke:var(--surface);stroke-width:2}.ok{fill:var(--series)}.near{fill:#fab219}.out{fill:#d03b3b}.cross{stroke:var(--muted);stroke-width:1;opacity:0}.chart:hover .cross{opacity:.7}.current{stroke:var(--ink);stroke-width:2}.key-line{margin-top:10px}
.toolbar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin:28px 0 8px}#search{flex:1 1 160px;min-width:0}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(236px,1fr));gap:14px;margin-top:12px}.card{position:relative;padding:0;text-align:left;background:var(--surface);border:1px solid var(--line);border-radius:14px;overflow:hidden;transition:transform .16s,box-shadow .16s}.card:hover{transform:translateY(-3px);box-shadow:var(--shadow)}.thumb{position:relative;aspect-ratio:16/9;background:var(--surface2)}.thumb img{width:100%;height:100%;object-fit:cover;display:block}.scrub{position:absolute;left:0;bottom:0;height:3px;background:#fff;box-shadow:0 0 3px rgba(0,0,0,.6);width:0;opacity:0;transition:opacity .15s}.card:hover .scrub{opacity:1}.card .badge{position:absolute;top:8px;right:8px}.badge{gap:4px;border-radius:7px;padding:2px 8px;font-size:.72rem;letter-spacing:.03em}.card-body{padding:10px 12px 12px}.card-body strong{display:block;font-size:.9rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.decided{color:var(--muted);font-size:.78rem}
.wrap{overflow-x:auto;margin-top:12px;background:var(--surface);border:1px solid var(--line);border-radius:14px}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}th,td{padding:9px 12px;text-align:left;border-bottom:1px solid var(--line);font-size:.875rem}tr:last-child td{border-bottom:0}#tbody tr{cursor:pointer}#tbody tr:hover{background:var(--surface2)}.v-near{color:var(--unsure);font-weight:650}.v-out{color:var(--fail);font-weight:650}
dialog{border:0;padding:0;background:var(--bg);color:var(--ink)}dialog::backdrop{background:rgba(5,6,8,.62);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px)}#detail{width:min(1160px,96vw);max-height:94vh;border-radius:18px;box-shadow:0 30px 90px rgba(0,0,0,.45)}#detail[open]{animation:rise .2s cubic-bezier(.2,.8,.2,1)}@keyframes rise{from{opacity:0;transform:translateY(12px) scale(.985)}}
.d-head{position:sticky;top:0;z-index:2;display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 18px;background:var(--bg);border-bottom:1px solid var(--line)}.d-title{display:flex;align-items:center;gap:10px;min-width:0}.d-title h2{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.d-nav{display:flex;align-items:center;gap:6px;flex:none}.d-body{display:grid;grid-template-columns:minmax(0,1fr) 300px;gap:18px;padding:18px}
.compare{position:relative;border-radius:12px;overflow:hidden;background:#000;line-height:0}.compare>img{width:100%;display:block}.c-top{position:absolute;inset:0;clip-path:inset(0 50% 0 0)}.c-top img{width:100%;height:100%;object-fit:cover;display:block}.c-handle{position:absolute;top:0;bottom:0;left:50%;width:2px;margin-left:-1px;background:#fff;box-shadow:0 0 6px rgba(0,0,0,.5);pointer-events:none}.c-handle span{position:absolute;top:50%;left:50%;width:34px;height:34px;margin:-17px;border-radius:50%;background:#fff;color:#111;display:flex;align-items:center;justify-content:center;font-size:15px;box-shadow:0 2px 8px rgba(0,0,0,.4)}.c-tag{position:absolute;top:10px;line-height:1.3;font-size:.75rem;background:rgba(0,0,0,.6);color:#fff;border-radius:6px;padding:2px 8px;pointer-events:none}.left{left:10px}.right{right:10px}#c-range{position:absolute;inset:0;width:100%;height:100%;margin:0;opacity:0;cursor:ew-resize}
.strip{display:flex;gap:6px;overflow-x:auto;padding:10px 2px 2px}.fr{flex:0 0 96px;padding:0;background:none;border:2px solid transparent;border-radius:9px;overflow:hidden;position:relative;font-size:.7rem;color:var(--muted)}.fr[aria-pressed=true]{border-color:var(--series)}.fr img{width:100%;display:block;aspect-ratio:16/9;object-fit:cover}.fr i{position:absolute;top:3px;right:3px;width:17px;height:17px;border-radius:5px;font-style:normal;font-size:.65rem;font-weight:700;display:flex;align-items:center;justify-content:center}.fr span{display:block;padding:2px 0}
.d-side h3{font-size:.875rem;margin:16px 0 6px}.mini td{padding:6px 2px}.mini td:last-child{text-align:right}#d-reasons{margin:0;padding-left:1.05rem;font-size:.875rem;color:var(--muted)}#d-reasons li{margin-bottom:5px}kbd{font:600 .7rem ui-monospace,monospace;border:1px solid var(--line);background:var(--surface2);border-radius:4px;padding:0 4px;margin-left:3px}
#help{padding:22px;border-radius:16px;width:min(380px,92vw)}#help dl{display:grid;grid-template-columns:auto 1fr;gap:9px 16px;margin:16px 0}#help dd{margin:0}#tip{position:fixed;z-index:9999;pointer-events:none;background:var(--ink);color:var(--bg);padding:4px 9px;border-radius:7px;font-size:.78rem;max-width:280px}#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:8px 16px;border-radius:10px;z-index:9999}
body.single #chips,body.single #charts-panel,body.single .toolbar,body.single #result-count{display:none}
@media (max-width:760px){main{padding:0 16px 56px}.top{padding:10px 16px}.hero{flex-direction:column-reverse;align-items:flex-start;gap:14px;padding-top:12px}#ref-image{width:100%}.tile{padding:12px;column-gap:8px}.tile .icon{width:26px;height:26px;font-size:.8rem}.tile b{font-size:1.4rem}.d-body{grid-template-columns:minmax(0,1fr)}.d-head{padding:10px 12px}#detail{width:100vw;max-width:100vw;max-height:100vh;height:100vh;border-radius:0}.d-nav #d-pos{display:none}}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important}}
@media (forced-colors:active){.chip,.icon,.badge{border:1px solid CanvasText}}
"""#

let appScript = #"""
(function () {
  var D = JSON.parse(document.getElementById("data").textContent);
  var $ = function (id) { return document.getElementById(id); };
  var METRICS = ["Saturation", "Brightness", "Background", "Overall look"];
  var ICONS = { pass: "✓", unsure: "?", fail: "✕" }, WORDS = { pass: "Pass", unsure: "Unsure", fail: "Fail" };
  var SLIDERS = [
    ["saturationMin", "Saturation at least", 50, 100, 1, "%"], ["saturationMax", "Saturation at most", 100, 160, 1, "%"],
    ["brightnessMin", "Brightness at least", 50, 100, 1, "%"], ["brightnessMax", "Brightness at most", 100, 160, 1, "%"],
    ["backgroundMin", "Background at least", 0, 100, 1, "%"], ["overallLookMax", "Overall look at most", 0.1, 1, 0.01, ""]
  ];
  var limits = Object.assign({}, D.thresholds), filter = "all", query = "", sort = "order", view = "grid", current = -1, frameIndex = 0;
  var decisions = {};
  var storeKey = "drift-scorecard:" + D.id;
  function read(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }
  function write(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }
  try { decisions = JSON.parse(read(storeKey) || "{}") || {}; } catch (e) { decisions = {}; }
  function esc(text) { return String(text).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
  function range(metric) {
    if (metric === "Saturation") return [limits.saturationMin, limits.saturationMax];
    if (metric === "Brightness") return [limits.brightnessMin, limits.brightnessMax];
    if (metric === "Background") return [limits.backgroundMin, 100];
    return [0, limits.overallLookMax];
  }
  function checkState(metric, value) {
    var r = range(metric), margin = D.margins[metric] || 0;
    if (value >= r[0] && value <= r[1]) return "ok";
    return value >= r[0] - margin - 1e-9 && value <= r[1] + margin + 1e-9 ? "near" : "out";
  }
  function metricsOf(frame) { return METRICS.filter(function (m) { return frame.values[m] !== undefined; }); }
  function frameVerdict(frame) {
    var states = metricsOf(frame).map(function (m) { return checkState(m, frame.values[m]); });
    return states.indexOf("out") >= 0 ? "fail" : states.indexOf("near") >= 0 ? "unsure" : "pass";
  }
  function clipVerdict(clip) {
    if (clip.error || !clip.frames.length) return "unsure";
    var verdicts = clip.frames.map(frameVerdict);
    return verdicts.indexOf("fail") >= 0 ? "fail" : verdicts.indexOf("unsure") >= 0 ? "unsure" : "pass";
  }
  function worst(clip, metric) {
    var values = clip.frames.map(function (f) { return f.values[metric]; }).filter(function (v) { return v !== undefined; });
    if (!values.length) return null;
    if (metric === "Background") return Math.min.apply(null, values);
    if (metric === "Overall look") return Math.max.apply(null, values);
    return values.reduce(function (a, b) { return Math.abs(b - 100) > Math.abs(a - 100) ? b : a; });
  }
  function show(metric, value) { return value === null ? "n/a" : metric === "Overall look" ? value.toFixed(2) : value.toFixed(1) + "%"; }
  function severity(clip) {
    return METRICS.reduce(function (total, m) {
      var v = worst(clip, m); if (v === null) return total;
      var r = range(m), scale = m === "Overall look" ? 0.05 : 5;
      return total + Math.max(0, r[0] - v, v - r[1]) / scale;
    }, clipVerdict(clip) === "unsure" && clip.error ? 1 : 0);
  }
  function toast(text) { var t = $("toast"); t.textContent = text; t.hidden = false; clearTimeout(toast.timer); toast.timer = setTimeout(function () { t.hidden = true; }, 1800); }
  function saveFile(name, text, type) { var a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([text], { type: type })); a.download = name; a.click(); setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000); toast("Saved " + name); }
  function copyText(text, done) {
    function fallback() { var area = document.createElement("textarea"); area.value = text; document.body.appendChild(area); area.select(); try { document.execCommand("copy"); toast(done); } catch (e) { toast("Could not copy"); } area.remove(); }
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(function () { toast(done); }, fallback); else fallback();
  }

  /* Static structure */
  var cards = D.clips.map(function (clip, index) {
    var card = document.createElement("button");
    card.className = "card"; card.type = "button";
    var src = clip.frames[0] ? clip.frames[0].image : "";
    card.innerHTML = '<div class="thumb">' + (src ? '<img alt="">' : "") + '<span class="badge"></span><div class="scrub"></div></div><div class="card-body"><strong></strong><span class="muted detail"></span> <span class="decided"></span></div>';
    var img = card.querySelector("img");
    if (img) { img.src = src; img.decoding = "async"; img.alt = clip.file; }
    card.querySelector("strong").textContent = clip.file;
    card.addEventListener("click", function () { openClip(index); });
    card.addEventListener("pointermove", function (event) {
      if (!clip.frames.length || !img) return;
      var box = card.getBoundingClientRect(), x = Math.max(0, Math.min(.999, (event.clientX - box.left) / box.width));
      img.src = clip.frames[Math.floor(x * clip.frames.length)].image;
      card.querySelector(".scrub").style.width = (x * 100) + "%";
    });
    card.addEventListener("pointerleave", function () { if (img) img.src = src; });
    $("grid").appendChild(card);
    return card;
  });
  var chips = D.clips.map(function (clip, index) {
    var li = document.createElement("li"), button = document.createElement("button");
    button.className = "chip"; button.type = "button";
    button.addEventListener("click", function () { openClip(index); });
    button.addEventListener("pointerenter", function (event) { showTip(event, clip.file); });
    button.addEventListener("pointermove", moveTip);
    button.addEventListener("pointerleave", hideTip);
    li.appendChild(button); $("chips").appendChild(li);
    return button;
  });
  $("thead").innerHTML = "<tr><th>#</th><th>Clip</th>" + METRICS.map(function (m) { return "<th>" + esc(m) + "</th>"; }).join("") + "<th>Result</th><th>You</th></tr>";
  var rows = D.clips.map(function (clip, index) {
    var row = document.createElement("tr");
    row.tabIndex = 0;
    row.addEventListener("click", function () { openClip(index); });
    row.addEventListener("keydown", function (event) { if (event.key === "Enter") openClip(index); });
    $("tbody").appendChild(row);
    return row;
  });
  var tip = $("tip");
  function showTip(event, text) { tip.textContent = text; tip.hidden = false; moveTip(event); }
  function moveTip(event) { tip.style.left = Math.max(4, Math.min(innerWidth - tip.offsetWidth - 4, event.clientX + 12)) + "px"; tip.style.top = Math.max(4, event.clientY - tip.offsetHeight - 10) + "px"; }
  function hideTip() { tip.hidden = true; }

  SLIDERS.forEach(function (s) {
    var box = document.createElement("div"); box.className = "slider";
    box.innerHTML = '<label for="s-' + s[0] + '"><span>' + esc(s[1]) + '</span><output id="o-' + s[0] + '"></output></label><input id="s-' + s[0] + '" type="range" min="' + s[2] + '" max="' + s[3] + '" step="' + s[4] + '">';
    $("sliders").appendChild(box);
    $("s-" + s[0]).addEventListener("input", function () { limits[s[0]] = parseFloat(this.value); schedule(); });
  });
  function syncSliders() {
    SLIDERS.forEach(function (s) {
      var input = $("s-" + s[0]);
      input.min = Math.min(s[2], limits[s[0]]); input.max = Math.max(s[3], limits[s[0]]); input.value = limits[s[0]];
      $("o-" + s[0]).textContent = s[4] < 1 ? limits[s[0]].toFixed(2) : limits[s[0]] + s[5];
    });
    Array.prototype.forEach.call($("presets").children, function (button) {
      var preset = D.presets[button.textContent];
      button.setAttribute("aria-pressed", SLIDERS.every(function (s) { return preset[s[0]] === limits[s[0]]; }) ? "true" : "false");
    });
  }
  Object.keys(D.presets).sort().reverse().forEach(function (name) {
    var button = document.createElement("button"); button.type = "button"; button.textContent = name;
    button.addEventListener("click", function () { Object.assign(limits, D.presets[name]); render(); });
    $("presets").appendChild(button);
  });
  [["all", "All"], ["pass", "Passed"], ["unsure", "Unsure"], ["fail", "Failed"], ["undecided", "Undecided"]].forEach(function (f) {
    var button = document.createElement("button"); button.type = "button"; button.dataset.f = f[0]; button.textContent = f[1];
    button.addEventListener("click", function () { setFilter(f[0]); });
    $("filters").appendChild(button);
  });
  function setFilter(value) { filter = value; applyBrowse(); }

  /* Charts */
  function drawChart(host, title, metric, points, active, onPick) {
    var W = 300, H = 150, L = 38, R = 10, T = 10, B = 24, r = range(metric), isLook = metric === "Overall look", isBg = metric === "Background";
    var limitsShown = isLook ? [r[1]] : isBg ? [r[0]] : r;
    var all = points.map(function (p) { return p.value; }).concat(limitsShown);
    var lo = Math.min.apply(null, all), hi = Math.max.apply(null, all), span = Math.max(hi - lo, .01);
    lo -= span * .08; hi += span * .08;
    function x(i) { return points.length === 1 ? (L + W - R) / 2 : L + (W - L - R) * i / (points.length - 1); }
    function y(v) { return T + (H - T - B) * (hi - v) / (hi - lo); }
    function tick(v) { return isLook ? v.toFixed(2) : Math.round(v) + "%"; }
    var bandTop = y(isBg ? hi : r[1]), bandBottom = y(isLook ? lo : r[0]);
    var s = '<rect class="band" x="' + L + '" y="' + bandTop.toFixed(1) + '" width="' + (W - L - R) + '" height="' + Math.max(0, bandBottom - bandTop).toFixed(1) + '"></rect>';
    limitsShown.forEach(function (v) { s += '<line class="limit" x1="' + L + '" x2="' + (W - R) + '" y1="' + y(v).toFixed(1) + '" y2="' + y(v).toFixed(1) + '"></line><text x="' + (L - 5) + '" y="' + (y(v) + 4).toFixed(1) + '" text-anchor="end">' + tick(v) + "</text>"; });
    s += '<line class="cross" y1="' + T + '" y2="' + (H - B) + '"></line><polyline class="line" points="' + points.map(function (p, i) { return x(i).toFixed(1) + "," + y(p.value).toFixed(1); }).join(" ") + '"></polyline>';
    var outside = 0;
    points.forEach(function (p, i) {
      var state = checkState(metric, p.value), cx = x(i), cy = y(p.value), cur = i === active ? " current" : "";
      if (state !== "ok") outside++;
      s += state === "ok" ? '<circle class="mark ok' + cur + '" cx="' + cx.toFixed(1) + '" cy="' + cy.toFixed(1) + '" r="4"></circle>'
        : '<rect class="mark ' + state + cur + '" x="' + (cx - 4.5).toFixed(1) + '" y="' + (cy - 4.5).toFixed(1) + '" width="9" height="9" transform="rotate(45 ' + cx.toFixed(1) + " " + cy.toFixed(1) + ')"></rect>';
    });
    s += '<text x="' + L + '" y="' + (H - 7) + '">' + esc(points[0].label) + '</text><text x="' + (W - R) + '" y="' + (H - 7) + '" text-anchor="end">' + esc(points[points.length - 1].label) + "</text>";
    host.innerHTML = "<h3>" + esc(title) + '</h3><svg viewBox="0 0 300 150" role="img" aria-label="' + esc(title + ": " + outside + " of " + points.length + " points outside the limits") + '">' + s + "</svg>";
    var svg = host.querySelector("svg"), cross = host.querySelector(".cross");
    function near(event) { var box = svg.getBoundingClientRect(), px = (event.clientX - box.left) / box.width * W, best = 0; points.forEach(function (p, i) { if (Math.abs(x(i) - px) < Math.abs(x(best) - px)) best = i; }); return best; }
    svg.addEventListener("pointermove", function (event) {
      var i = near(event), state = checkState(metric, points[i].value);
      cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i));
      showTip(event, points[i].label + ": " + show(metric, points[i].value) + ", " + { ok: "within limits", near: "just outside", out: "outside the limit" }[state]);
      svg.style.cursor = onPick ? "pointer" : "";
    });
    svg.addEventListener("pointerleave", hideTip);
    if (onPick) svg.addEventListener("click", function (event) { hideTip(); onPick(points[near(event)].index); });
  }

  /* Rendering */
  var verdicts = [], chartHosts = METRICS.map(function () { var d = document.createElement("div"); d.className = "chart"; $("charts").appendChild(d); return d; });
  function counts() { var c = { pass: 0, unsure: 0, fail: 0 }; verdicts.forEach(function (v) { c[v]++; }); return c; }
  function render() {
    verdicts = D.clips.map(clipVerdict);
    var c = counts(), total = D.clips.length;
    $("n-pass").textContent = c.pass; $("n-unsure").textContent = c.unsure; $("n-fail").textContent = c.fail;
    $("headline").textContent = total === 1 ? WORDS[verdicts[0]] : c.pass === total ? "Every clip passed." : c.pass + " of " + total + " clips passed.";
    $("subline").textContent = total === 1 ? D.clips[0].file : c.unsure + " need a person to look. " + c.fail + " drifted past the limits.";
    var bar = $("bar").children; [c.pass, c.unsure, c.fail].forEach(function (n, i) { bar[i].style.width = "calc((100% - 4px) * " + (n / total) + ")"; });
    chips.forEach(function (chip, i) { var v = verdicts[i]; chip.className = "chip s-" + v; chip.setAttribute("aria-label", "Clip " + (i + 1) + ", " + D.clips[i].file + ": " + WORDS[v]); chip.innerHTML = (i + 1) + '<small aria-hidden="true">' + ICONS[v] + "</small>"; });
    cards.forEach(function (card, i) {
      var v = verdicts[i], clip = D.clips[i], badge = card.querySelector(".badge");
      badge.className = "badge s-" + v; badge.textContent = ICONS[v] + " " + WORDS[v];
      var bg = worst(clip, "Background"), look = worst(clip, "Overall look");
      card.querySelector(".detail").textContent = clip.error ? "Could not be read" : "Background " + show("Background", bg) + (look === null ? "" : " · Look " + look.toFixed(2));
      card.querySelector(".decided").textContent = decisions[clip.file] ? "· You: " + decisions[clip.file] : "";
    });
    rows.forEach(function (row, i) {
      var clip = D.clips[i], v = verdicts[i];
      row.innerHTML = "<td>" + (i + 1) + "</td><td>" + esc(clip.file) + "</td>" + METRICS.map(function (m) { var val = worst(clip, m); var st = val === null ? "ok" : checkState(m, val); return '<td class="v-' + st + '">' + show(m, val) + "</td>"; }).join("") + '<td><span class="badge s-' + v + '">' + ICONS[v] + " " + WORDS[v] + "</span></td><td>" + esc(decisions[clip.file] || "") + "</td>";
    });
    syncSliders(); renderCharts(); renderAccuracy(); applyBrowse();
    if ($("detail").open) renderDetail();
  }
  var pending = false;
  function schedule() { if (pending) return; pending = true; requestAnimationFrame(function () { pending = false; render(); }); }
  function renderCharts() {
    METRICS.forEach(function (m, h) {
      var points = [];
      D.clips.forEach(function (clip, i) { var v = worst(clip, m); if (v !== null) points.push({ label: "Clip " + (i + 1), value: v, index: i }); });
      chartHosts[h].classList.toggle("hidden", !points.length);
      if (points.length) drawChart(chartHosts[h], m, m, points, -1, openClip);
    });
  }
  function renderAccuracy() {
    var e = { kp: 0, ku: 0, kf: 0, rp: 0, ru: 0, rf: 0 };
    D.clips.forEach(function (clip, i) { var d = decisions[clip.file]; if (!d) return; e[d[0] + verdicts[i][0]]++; });
    var kept = e.kp + e.ku + e.kf, redone = e.rp + e.ru + e.rf, total = kept + redone;
    $("accuracy-panel").classList.toggle("hidden", total === 0);
    if (!total) return;
    $("accuracy-note").textContent = "Based on the " + total + " clips you have decided. Limits tuned to the same clips will look better than they are, so test them on new clips.";
    $("accuracy").innerHTML = [[e.kp + e.rf, "Clearly right"], [e.kf + e.rp, "Clearly wrong"], [e.ku + e.ru, "Left to a person"], [Math.max(kept, redone), "Same answer for every clip would get"]].map(function (s) { return '<div class="stat"><b>' + s[0] + " / " + total + "</b><span>" + esc(s[1]) + "</span></div>"; }).join("");
  }
  function visible(i) {
    var clip = D.clips[i];
    if (query && clip.file.toLowerCase().indexOf(query) < 0) return false;
    if (filter === "undecided") return !decisions[clip.file];
    return filter === "all" || verdicts[i] === filter;
  }
  function ordered() {
    var list = D.clips.map(function (_, i) { return i; });
    if (sort === "worst") list.sort(function (a, b) { return severity(D.clips[b]) - severity(D.clips[a]); });
    else if (sort !== "order") list.sort(function (a, b) { var x = worst(D.clips[a], sort), y = worst(D.clips[b], sort); if (x === null) return 1; if (y === null) return -1; return sort === "Overall look" ? y - x : Math.abs(y - 100) - Math.abs(x - 100); });
    return list;
  }
  function applyBrowse() {
    var list = ordered(), shown = 0;
    list.forEach(function (i) { var on = visible(i); if (on) shown++; cards[i].classList.toggle("hidden", !on); rows[i].classList.toggle("hidden", !on); $("grid").appendChild(cards[i]); $("tbody").appendChild(rows[i]); });
    $("result-count").textContent = shown === D.clips.length ? D.clips.length + " clips" : shown + " of " + D.clips.length + " clips";
    Array.prototype.forEach.call($("filters").children, function (b) { b.setAttribute("aria-pressed", b.dataset.f === filter ? "true" : "false"); });
    document.querySelectorAll(".tile").forEach(function (t) { t.setAttribute("aria-pressed", t.dataset.filter === filter ? "true" : "false"); });
    $("grid").classList.toggle("hidden", view !== "grid"); $("table-wrap").classList.toggle("hidden", view !== "table");
  }

  /* Detail */
  function openClip(index) { current = index; frameIndex = defaultFrame(index); renderDetail(); if (!$("detail").open) $("detail").showModal(); }
  function defaultFrame(index) { var clip = D.clips[index], f = clip.frames.findIndex(function (fr) { return frameVerdict(fr) === "fail"; }); if (f < 0) f = clip.frames.findIndex(function (fr) { return frameVerdict(fr) === "unsure"; }); return Math.max(0, f); }
  function step(delta) { var list = ordered().filter(visible); if (!list.length) return; var at = list.indexOf(current); var next = list[(at + delta + list.length) % list.length]; if (at < 0) next = list[0]; current = next; frameIndex = defaultFrame(next); renderDetail(); }
  function setFrame(i) { var clip = D.clips[current]; if (!clip.frames.length) return; frameIndex = (i + clip.frames.length) % clip.frames.length; renderDetail(); }
  function decide(value) { var file = D.clips[current].file; if (decisions[file] === value) delete decisions[file]; else decisions[file] = value; write(storeKey, JSON.stringify(decisions)); render(); }
  function reasons(clip) {
    if (clip.error) return [clip.error];
    var list = [];
    clip.frames.forEach(function (f) { metricsOf(f).forEach(function (m) { var st = checkState(m, f.values[m]); if (st === "ok") return; var r = range(m); var allowed = m === "Overall look" ? "at most " + r[1].toFixed(2) : m === "Background" ? "at least " + r[0] + "%" : r[0] + "% to " + r[1] + "%"; list.push(f.label + ": " + m.toLowerCase() + " is " + show(m, f.values[m]) + ", allowed " + allowed + (st === "near" ? " (only just outside)." : ".")); }); });
    return list.concat(clip.warnings || []);
  }
  function renderDetail() {
    var clip = D.clips[current], v = verdicts[current], frame = clip.frames[frameIndex];
    var list = ordered().filter(visible), at = list.indexOf(current);
    $("d-title").textContent = clip.file; $("d-badge").className = "badge s-" + v; $("d-badge").textContent = ICONS[v] + " " + WORDS[v];
    $("d-pos").textContent = at >= 0 ? (at + 1) + " of " + list.length : "";
    $("compare").classList.toggle("hidden", !frame); $("c-ref").src = D.referenceImage;
    if (frame) { $("c-frame").src = frame.image; $("c-frame").alt = frame.label + " frame of " + clip.file; $("c-label").textContent = frame.label + " · " + frame.seconds.toFixed(1) + "s"; }
    var strip = $("strip"); strip.innerHTML = "";
    clip.frames.forEach(function (f, i) {
      var fv = frameVerdict(f), b = document.createElement("button");
      b.className = "fr"; b.type = "button"; b.setAttribute("aria-pressed", i === frameIndex ? "true" : "false"); b.setAttribute("aria-label", f.label + ", " + WORDS[fv]);
      b.innerHTML = '<img alt=""><i class="s-' + fv + '" aria-hidden="true">' + ICONS[fv] + "</i><span>" + esc(f.label) + "</span>";
      b.querySelector("img").src = f.image; b.addEventListener("click", function () { setFrame(i); }); strip.appendChild(b);
    });
    var host = $("d-charts"); host.innerHTML = "";
    if (clip.frames.length > 1) METRICS.forEach(function (m) {
      if (clip.frames[0].values[m] === undefined) return;
      var d = document.createElement("div"); d.className = "chart"; host.appendChild(d);
      drawChart(d, m, m, clip.frames.map(function (f, i) { return { label: f.label, value: f.values[m], index: i }; }), frameIndex, setFrame);
    });
    $("d-values").innerHTML = frame ? metricsOf(frame).map(function (m) { var st = checkState(m, frame.values[m]); return "<tr><td>" + esc(m) + '</td><td class="v-' + st + '">' + show(m, frame.values[m]) + "</td></tr>"; }).join("") : "";
    var why = reasons(clip); $("d-reason-title").textContent = v === "pass" ? "Within every limit" : v === "unsure" ? "A person should look" : "Why it failed";
    $("d-reasons").innerHTML = why.map(function (t) { return "<li>" + esc(t) + "</li>"; }).join("");
    $("keep").setAttribute("aria-pressed", decisions[clip.file] === "keep" ? "true" : "false"); $("redo").setAttribute("aria-pressed", decisions[clip.file] === "redo" ? "true" : "false");
  }
  function setCompare(value) { $("c-top").style.clipPath = "inset(0 " + (100 - value) + "% 0 0)"; $("c-handle").style.left = value + "%"; }
  $("c-range").addEventListener("input", function () { setCompare(this.value); });

  /* Controls */
  $("ref-name").textContent = "Reference: " + D.referenceFile;
  if (D.referenceImage) $("ref-image").src = D.referenceImage; else $("ref-image").classList.add("hidden");
  if (D.clips.length === 1) document.body.classList.add("single");
  $("d-prev").addEventListener("click", function () { step(-1); }); $("d-next").addEventListener("click", function () { step(1); });
  $("d-close").addEventListener("click", function () { $("detail").close(); });
  $("detail").addEventListener("click", function (event) { if (event.target === this) this.close(); });
  $("keep").addEventListener("click", function () { decide("keep"); }); $("redo").addEventListener("click", function () { decide("redo"); });
  $("reset").addEventListener("click", function () { limits = Object.assign({}, D.thresholds); render(); toast("Limits reset"); });
  $("copy-limits").addEventListener("click", function () { copyText(["--saturation-min " + limits.saturationMin, "--saturation-max " + limits.saturationMax, "--brightness-min " + limits.brightnessMin, "--brightness-max " + limits.brightnessMax, "--background-min " + limits.backgroundMin, "--overall-look-max " + limits.overallLookMax].join(" "), "Limits copied"); });
  $("search").addEventListener("input", function () { query = this.value.trim().toLowerCase(); applyBrowse(); });
  $("sort").addEventListener("change", function () { sort = this.value; applyBrowse(); });
  document.querySelectorAll(".tile").forEach(function (t) { t.addEventListener("click", function () { setFilter(filter === t.dataset.filter ? "all" : t.dataset.filter); }); });
  Array.prototype.forEach.call($("views").children, function (b) { b.addEventListener("click", function () { view = b.dataset.view; Array.prototype.forEach.call($("views").children, function (o) { o.setAttribute("aria-pressed", o === b ? "true" : "false"); }); applyBrowse(); }); });
  $("export-csv").addEventListener("click", function () {
    function cell(t) { t = String(t); if (/^[=+\-@\t\r]/.test(t)) t = "'" + t; return /[",\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; }
    var lines = [["Clip"].concat(METRICS, ["Result", "Your decision"]).map(cell).join(",")];
    D.clips.forEach(function (clip, i) { lines.push([clip.file].concat(METRICS.map(function (m) { var v = worst(clip, m); return v === null ? "" : v; }), [verdicts[i], decisions[clip.file] || ""]).map(cell).join(",")); });
    saveFile("drift-scorecard.csv", lines.join("\n") + "\n", "text/csv");
  });
  $("export-decisions").addEventListener("click", function () { var names = Object.keys(decisions); if (!names.length) { toast("Open a clip and choose Keep or Redo first"); return; } saveFile("decisions.txt", names.map(function (n) { return decisions[n] + " " + n; }).join("\n") + "\n", "text/plain"); });
  var THEMES = ["auto", "light", "dark"], theme = read("drift-scorecard:theme") || "auto";
  function applyTheme() { if (theme === "auto") document.documentElement.removeAttribute("data-theme"); else document.documentElement.setAttribute("data-theme", theme); $("theme").textContent = theme[0].toUpperCase() + theme.slice(1); }
  $("theme").addEventListener("click", function () { theme = THEMES[(THEMES.indexOf(theme) + 1) % 3]; write("drift-scorecard:theme", theme); applyTheme(); });
  $("help-open").addEventListener("click", function () { $("help").showModal(); }); $("help-close").addEventListener("click", function () { $("help").close(); });
  document.addEventListener("keydown", function (event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    var tag = event.target.tagName, typing = tag === "SELECT" || (tag === "INPUT" && event.target.type !== "range") || tag === "TEXTAREA";
    if (typing) return;
    var inDetail = $("detail").open, onRange = tag === "INPUT";
    if (event.key === "/" && !inDetail) { event.preventDefault(); $("search").focus(); }
    else if (event.key === "?") { if (!$("help").open) $("help").showModal(); }
    else if (inDetail && (event.key === "j" || event.key === "J")) step(1);
    else if (inDetail && (event.key === "k" || event.key === "K")) step(-1);
    else if (inDetail && event.key === "1") decide("keep");
    else if (inDetail && event.key === "2") decide("redo");
    else if (inDetail && !onRange && event.key === "ArrowRight") { event.preventDefault(); setFrame(frameIndex + 1); }
    else if (inDetail && !onRange && event.key === "ArrowLeft") { event.preventDefault(); setFrame(frameIndex - 1); }
  });
  applyTheme(); setCompare(50); render();
  if (D.clips.length === 1) openClip(0);
  window.__drift = { verdicts: function () { return verdicts.slice(); } };
})();
"""#
