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

public struct BatchResult {
    public let outcomes: [ClipOutcome]
    public let clips: [ReportClip]
    public let reference: PixelImage?
}

/// Frames above this count are stored at half size, so a very large report still opens quickly.
let fullSizeFrameBudget = 400

/// Checks clips on several processor cores at once. Results keep the input order.
public func runBatch(referencePath: String, videos: [String], thresholds: Thresholds, frameCount: Int,
                     progress: ((_ done: Int, _ total: Int, _ file: String) -> Void)? = nil) -> BatchResult {
    let lock = NSLock()
    var outcomes = [ClipOutcome?](repeating: nil, count: videos.count)
    var clips = [ReportClip?](repeating: nil, count: videos.count)
    var reference: PixelImage?
    var next = 0, done = 0
    let shrink = videos.count * frameCount > fullSizeFrameBudget
    let workers = max(1, min(videos.count, ProcessInfo.processInfo.activeProcessorCount - 1))
    DispatchQueue.concurrentPerform(iterations: workers) { _ in
        while true {
            lock.lock()
            let index = next
            next += 1
            lock.unlock()
            guard index < videos.count else { return }
            autoreleasepool {
                let name = URL(fileURLWithPath: videos[index]).lastPathComponent
                let outcome: ClipOutcome, clip: ReportClip
                var picture: PixelImage?
                do {
                    let run = try runScorecard(referencePath: referencePath, videoPath: videos[index], thresholds: thresholds, frameCount: frameCount)
                    let images = run.frames.map { encodeJPEG(shrink ? halfSize($0) : $0) }
                    outcome = ClipOutcome(file: name, card: run.card, error: nil)
                    clip = makeReportClip(file: name, card: run.card, error: nil, images: images)
                    picture = run.reference
                } catch {
                    outcome = ClipOutcome(file: name, card: nil, error: error.localizedDescription)
                    clip = makeReportClip(file: name, card: nil, error: error.localizedDescription, images: [])
                }
                lock.lock()
                outcomes[index] = outcome
                clips[index] = clip
                if reference == nil { reference = picture }
                done += 1
                let finished = done
                lock.unlock()
                progress?(finished, videos.count, name)
            }
        }
    }
    return BatchResult(outcomes: outcomes.compactMap { $0 }, clips: clips.compactMap { $0 }, reference: reference)
}

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

public func saveBatch(_ result: BatchResult, referencePath: String, thresholds: Thresholds, to directory: String) throws {
    let folder = URL(fileURLWithPath: directory, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result.outcomes).write(to: folder.appendingPathComponent("report.json"))
    // A summary-only reference so the page still shows it when every clip was unreadable.
    let picture = result.reference ?? (try? loadPicture(referencePath)).map { normalize($0, width: 480, height: max(8, 480 * $0.height / $0.width)) }
    let html = interactiveHTML(clips: result.clips, referenceFile: URL(fileURLWithPath: referencePath).lastPathComponent, referenceJPEG: picture.map(encodeJPEG), thresholds: thresholds)
    try html.write(to: folder.appendingPathComponent("report.html"), atomically: true, encoding: .utf8)
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
