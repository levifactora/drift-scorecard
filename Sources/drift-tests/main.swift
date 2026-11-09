// The test suite. Run with: swift run drift-tests
// It is a plain program because XCTest needs a full Xcode install.
import DriftCore
import Foundation

var passedCount = 0
var failedCount = 0

func expect(_ condition: Bool, _ name: String) {
    if condition {
        passedCount += 1
    } else {
        failedCount += 1
        print("FAILED: \(name)")
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001) -> Bool { abs(a - b) <= tolerance }

func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, width: Int = 40, height: Int = 40) -> PixelImage {
    var bytes: [UInt8] = []
    for _ in 0..<(width * height) { bytes += [r, g, b, 255] }
    return PixelImage(width: width, height: height, rgba: bytes)
}

func painted(_ base: PixelImage, x: Range<Int>, y: Range<Int>, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> PixelImage {
    var bytes = base.rgba
    for row in y {
        for column in x {
            let i = (row * base.width + column) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
    }
    return PixelImage(width: base.width, height: base.height, rgba: bytes)
}

func throwsError(_ expected: ScorecardError? = nil, _ body: () throws -> Void) -> Bool {
    do {
        try body()
        return false
    } catch {
        guard let expected else { return true }
        return (error as? ScorecardError) == expected
    }
}

func frameAt(_ image: PixelImage, _ label: String = "Start") -> SampledFrame {
    SampledFrame(label: label, seconds: 0.1, image: image)
}

func card(_ reference: PixelImage, _ frames: [SampledFrame], _ thresholds: Thresholds = Thresholds()) throws -> Scorecard {
    try score(referenceFile: "r.png", videoFile: "v.mp4", reference: reference, frames: frames, thresholds: thresholds)
}

func testMetrics() {
    expect(near(colorStats(solid(255, 0, 0)).saturation, 1), "pure red is fully saturated")
    expect(near(colorStats(solid(128, 128, 128)).saturation, 0), "grey has no saturation")
    expect(near(colorStats(solid(0, 0, 0)).saturation, 0), "black has no saturation and does not divide by zero")
    expect(near(colorStats(solid(30, 60, 90)).brightness, 60), "brightness is the channel average")

    let base = solid(200, 40, 40)
    expect(near(backgroundSimilarity(base, base), 1), "identical pictures are 100% similar")
    expect(near(backgroundSimilarity(base, solid(40, 200, 40)), 0), "unrelated colors are 0% similar")
    expect(near(backgroundSimilarity(base, painted(base, x: 0..<40, y: 14..<40, 40, 200, 40)), 1),
           "changes below the background band are ignored")
    expect(near(backgroundSimilarity(base, painted(base, x: 0..<10, y: 0..<7, 40, 200, 40)), 0.875),
           "changing one of eight grid cells costs one eighth")
}

func testScoring() throws {
    let reference = solid(200, 100, 100)
    let same = try card(reference, [frameAt(reference)])
    expect(same.passed, "a frame identical to the reference passes")
    expect(same.frames[0].checks.map(\.value) == [100, 100, 100], "identical frame scores 100 on every metric")

    let dark = try card(reference, [frameAt(solid(100, 50, 50))])
    let brightness = dark.frames[0].checks[1]
    expect(!brightness.passed && near(brightness.value, 50), "half brightness fails at 50%")
    expect(dark.frames[0].checks[0].passed, "same-hue darkening leaves saturation at 100%")

    var exact = Thresholds()
    exact.brightnessMin = 50
    exact.backgroundMin = 0
    expect(try card(reference, [frameAt(solid(100, 50, 50))], exact).passed, "a value exactly on the limit passes")

    let mixed = try card(reference, [frameAt(reference, "Start"), frameAt(solid(20, 200, 20), "End")])
    expect(!mixed.passed, "one bad frame fails the whole video")
    expect(mixed.frames[0].passed && !mixed.frames[1].passed, "pass and fail are recorded per frame")
    expect(failureReasons(mixed).allSatisfy { $0.hasPrefix("End frame") }, "reasons name only the failing frame")

    expect(try !card(reference, []).passed, "a video with no frames can never pass")
    expect(throwsError { _ = try card(solid(128, 128, 128), [frameAt(reference)]) }, "a grey reference is refused")
    expect(throwsError { _ = try card(solid(0, 0, 0), [frameAt(reference)]) }, "a black reference is refused")
}

func testSampling() {
    let normal = sampleTimes(duration: 5, count: 3)
    expect(near(normal[0].seconds, 0.1) && near(normal[1].seconds, 2.5) && near(normal[2].seconds, 4.9), "samples sit at start, middle and end")
    let tiny = sampleTimes(duration: 0.1, count: 3)
    expect(tiny[0].seconds > 0 && tiny[0].seconds < tiny[1].seconds && tiny[1].seconds < tiny[2].seconds && tiny[2].seconds < 0.1,
           "very short videos still sample in order and inside the video")
}

func testArguments() throws {
    let options = try parseArguments(["a.png", "b.mp4", "--saturation-min", "105", "--background-min", "77.5", "--out", "here"])
    expect(options.referencePath == "a.png" && options.videoPath == "b.mp4", "file order is reference then video")
    expect(options.thresholds.saturationMin == 105 && options.thresholds.backgroundMin == 77.5, "thresholds are read")
    expect(options.thresholds.brightnessMax == 110, "unset thresholds keep defaults")
    expect(options.outputDirectory == "here", "output folder is read")
    expect(try parseArguments(["--help"]).showHelp, "help works without files")

    for bad in [["a.png"], ["a", "b", "--nope"], ["a", "b", "--saturation-min"], ["a", "b", "--saturation-min", "lots"],
                ["a", "b", "--brightness-max", "nan"], ["a", "b", "--brightness-min", "-1"],
                ["a", "b", "--saturation-min", "120"], ["a", "b", "--brightness-min", "111"], ["a", "b", "--background-min", "101"]] {
        expect(throwsError { _ = try parseArguments(bad) }, "rejects arguments: \(bad.joined(separator: " "))")
    }
}

func testReports() throws {
    let reference = solid(200, 100, 100)
    let bad = try score(referenceFile: "<script>.png", videoFile: "v&v.mp4", reference: reference,
                        frames: [frameAt(solid(20, 200, 20))], thresholds: Thresholds())
    let clip = makeReportClip(file: "</script><img src=x onerror=1>.mp4", card: bad, error: nil, images: [encodeJPEG(reference)])
    let html = interactiveHTML(clips: [clip], referenceFile: "<script>.png", referenceJPEG: encodeJPEG(reference), thresholds: Thresholds())
    expect(!html.contains("</script><img") && !html.contains("<script>.png") && html.contains("\\u003cscript>.png"), "file names cannot break out of the report's data")
    expect(html.contains("\"margins\"") && html.contains(";base64,"), "the report carries its limits and pictures")
    expect(clip.verdict == .fail && clip.frames[0].values["Saturation"] != nil, "report clips carry results")
    expect(textReport(bad).contains("OVERALL: FAIL"), "text report shows the verdict")
    expect(textReport(bad).contains("Why it failed:"), "text report explains failure")
    let decoded = try JSONDecoder().decode(Scorecard.self, from: jsonReport(bad))
    expect(decoded == bad, "JSON report round-trips")
    expect(encodeJPEG(reference).starts(with: [0xFF, 0xD8]), "thumbnails are real JPEG data")
}

func testEndToEnd() throws {
    let folder = NSTemporaryDirectory() + "drift-tests-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try makeSamples(in: folder)
    let reference = folder + "/reference.png"
    func run(_ name: String) throws -> Scorecard {
        try runScorecard(referencePath: reference, videoPath: "\(folder)/\(name)", thresholds: Thresholds(), frameCount: 3).card
    }
    func metricPassed(_ frame: FrameResult, _ metric: String) -> Bool { frame.checks.first { $0.metric == metric }!.passed }

    let steady = try run("steady.mp4")
    expect(steady.passed, "steady sample passes")
    expect(steady.frames.map(\.label) == ["Start", "Middle", "End"], "three frames are scored")
    expect(steady.warnings.isEmpty, "matching shapes give no warning")

    let color = try run("color-drift.mp4")
    expect(!color.passed, "color drift fails")
    expect(color.frames[0].passed, "color drift is not present at the start")
    expect(!metricPassed(color.frames[2], "Saturation") && !metricPassed(color.frames[2], "Brightness"), "color drift is caught at the end")

    let background = try run("background-drift.mp4")
    expect(!background.passed, "background drift fails")
    expect(background.frames[0].passed, "background drift is not present at the start")
    expect(!metricPassed(background.frames[2], "Background"), "background drift is caught at the end")

    var loose = Thresholds()
    loose.saturationMin = 0; loose.saturationMax = 10000; loose.brightnessMin = 0; loose.brightnessMax = 10000; loose.backgroundMin = 0
    expect(try runScorecard(referencePath: reference, videoPath: folder + "/color-drift.mp4", thresholds: loose, frameCount: 3).card.passed,
           "user-set thresholds change the verdict")

    let missing = folder + "/missing.mp4"
    expect(throwsError(.fileNotFound(missing)) { _ = try runScorecard(referencePath: reference, videoPath: missing, thresholds: Thresholds()) },
           "a missing video is a clear error")
    let junk = folder + "/junk.mp4"
    try Data("not a video".utf8).write(to: URL(fileURLWithPath: junk))
    expect(throwsError(.unreadableVideo(junk)) { _ = try runScorecard(referencePath: reference, videoPath: junk, thresholds: Thresholds()) },
           "a corrupt video is a clear error")
    expect(throwsError(.unreadableImage(junk)) { _ = try runScorecard(referencePath: junk, videoPath: folder + "/steady.mp4", thresholds: Thresholds()) },
           "a corrupt reference is a clear error")

    let output = folder + "/report/nested"
    try saveReports(try runScorecard(referencePath: reference, videoPath: folder + "/steady.mp4", thresholds: Thresholds()), to: output)
    expect(FileManager.default.fileExists(atPath: output + "/report.html") && FileManager.default.fileExists(atPath: output + "/report.json"),
           "reports are saved, creating folders as needed")
}

func testNewFeatures() throws {
    let reference = solid(200, 100, 100)
    func card(look: Double) throws -> Scorecard {
        try score(referenceFile: "r.png", videoFile: "v.mp4", reference: reference,
                  frames: [SampledFrame(label: "Start", seconds: 0, image: reference, overallLook: look)], thresholds: Thresholds())
    }
    expect(try card(look: 0.2).verdict == .pass, "a close overall look passes")
    let nearCard = try card(look: 0.47)
    expect(nearCard.verdict == .unsure && !nearCard.passed, "just outside a limit is unsure, and is still not a pass")
    expect(try card(look: 0.48).verdict == .unsure, "the edge of the unsure margin is unsure")
    expect(try card(look: 0.49).verdict == .fail, "beyond the margin is a failure")
    expect(textReport(nearCard).contains("OVERALL: UNSURE") && textReport(nearCard).contains("Close to a limit:"), "text report explains unsure")
    let mixed = try score(referenceFile: "r.png", videoFile: "v.mp4", reference: reference, frames: [
        SampledFrame(label: "A", seconds: 0, image: reference, overallLook: 0.47), SampledFrame(label: "B", seconds: 1, image: reference, overallLook: 0.9),
    ], thresholds: Thresholds())
    expect(mixed.verdict == .fail, "one clear failure outweighs unsure frames")
    let unsureClip = makeReportClip(file: "v.mp4", card: nearCard, error: nil, images: [encodeJPEG(reference)])
    expect(unsureClip.verdict == .unsure && interactiveHTML(clips: [unsureClip], referenceFile: "r.png", referenceJPEG: nil, thresholds: Thresholds()).contains("A person should look"), "the report shows unsure in words")

    let five = sampleTimes(duration: 10)
    expect(five.map(\.label) == ["Start", "25%", "Middle", "75%", "End"] && near(five[1].seconds, 2.5), "five evenly spaced frames by default")
    expect(sampleTimes(duration: 10, count: 9).count == 9, "the number of frames can be changed")
    let parsed = try parseArguments(["a.png", "b", "c.mp4", "--frames", "7", "--decisions", "d.txt", "--overall-look-max", "0.3"])
    expect(parsed.videoPaths == ["b", "c.mp4"] && parsed.frameCount == 7 && parsed.decisionsPath == "d.txt" && parsed.thresholds.overallLookMax == 0.3, "reads several inputs and new options")
    let cartoon = try parseArguments(["--background-min", "55", "--preset", "cartoon", "a.png", "b"])
    expect(cartoon.thresholds.backgroundMin == 55 && cartoon.thresholds.overallLookMax == 0.40, "a preset applies, and your own limits win in any order")
    for bad in [["a", "b", "--frames", "2"], ["a", "b", "--frames", "26"], ["a", "b", "--frames", "x"], ["a", "b", "--preset", "nope"]] {
        expect(throwsError { _ = try parseArguments(bad) }, "rejects arguments: \(bad.joined(separator: " "))")
    }

    let folder = NSTemporaryDirectory() + "drift-batch-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: folder) }
    try makeSamples(in: folder)
    let picture = folder + "/reference.png"
    let clips = folder + "/clips"
    try FileManager.default.createDirectory(atPath: clips, withIntermediateDirectories: true)
    for name in ["clip10.mp4", "clip2.mp4"] { try FileManager.default.copyItem(atPath: folder + "/steady.mp4", toPath: clips + "/" + name) }
    try Data("bad".utf8).write(to: URL(fileURLWithPath: clips + "/clip3.mp4"))
    try Data("x".utf8).write(to: URL(fileURLWithPath: clips + "/notes.txt"))
    let found = try expandInputs([clips])
    expect(found.batch && found.videos.map { ($0 as NSString).lastPathComponent } == ["clip2.mp4", "clip3.mp4", "clip10.mp4"], "folders list videos in natural order")
    let one = try expandInputs([folder + "/steady.mp4"])
    expect(!one.batch && one.videos.count == 1, "one video keeps the single report")
    expect(throwsError(.fileNotFound(folder + "/nope")) { _ = try expandInputs([folder + "/nope"]) }, "a missing input is a clear error")
    let empty = folder + "/empty"
    try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
    expect(throwsError { _ = try expandInputs([empty]) }, "a folder with no videos is a clear error")

    let batchResult = runBatch(referencePath: picture, videos: found.videos, thresholds: Thresholds(), frameCount: 3)
    let outcomes = batchResult.outcomes
    expect(outcomes.map(\.verdict) == [.pass, .unsure, .pass] && outcomes[1].error != nil, "one unreadable clip does not stop the run and never passes")
    expect(outcomes.map(\.file) == ["clip2.mp4", "clip3.mp4", "clip10.mp4"] && batchResult.clips.map(\.file) == outcomes.map(\.file), "results keep clip order when checked in parallel")
    let batchOutput = folder + "/out"
    try saveBatch(batchResult, referencePath: picture, thresholds: Thresholds(), to: batchOutput)
    let index = try String(contentsOfFile: batchOutput + "/report.html", encoding: .utf8)
    expect(index.contains("clip10.mp4") && index.contains("\"error\":\""), "the report includes every clip and any error")
    expect(try JSONDecoder().decode([ClipOutcome].self, from: Data(contentsOf: URL(fileURLWithPath: batchOutput + "/report.json"))) == outcomes, "summary JSON round-trips")
    expect(batchText(outcomes).contains("Passed 2, unsure 1, failed 0, of 3 clips."), "text summary counts clips")
    let shrunk = halfSize(solid(10, 20, 30, width: 40, height: 20))
    expect(shrunk.width == 20 && shrunk.height == 10 && shrunk.rgba[0] == 10, "large reports can use smaller frames")

    let decisions = try parseDecisions("keep a one.mp4\n\nredo b.mp4\nKEEP b.mp4\n")
    expect(decisions == ["a one.mp4": .keep, "b.mp4": .keep], "reads decisions and later changes")
    expect(throwsError { _ = try parseDecisions("maybe x.mp4") }, "a bad decision line is an error")
    let scored = try evaluate(outcomes, decisions: ["clip2.mp4": .keep, "clip3.mp4": .redo, "clip10.mp4": .redo, "other.mp4": .keep])
    expect(scored.keptPass == 1 && scored.redoUnsure == 1 && scored.redoPass == 1 && scored.total == 3, "scores clips against decisions and ignores unknown names")
    expect(evaluationText(scored).contains("would get 2 of 3 right"), "accuracy is compared with a blunt rule")
    expect(throwsError { _ = try evaluate(outcomes, decisions: ["z.mp4": .keep]) }, "no matching decisions is an error")
}

do {
    try testNewFeatures()
    testMetrics()
    try testScoring()
    testSampling()
    try testArguments()
    try testReports()
    try testEndToEnd()
} catch {
    failedCount += 1
    print("FAILED: unexpected error: \(error)")
}

print("\(passedCount) passed, \(failedCount) failed")
exit(failedCount == 0 ? 0 : 1)
