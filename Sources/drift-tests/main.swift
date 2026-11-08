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
    let normal = sampleTimes(duration: 5)
    expect(near(normal[0].seconds, 0.1) && near(normal[1].seconds, 2.5) && near(normal[2].seconds, 4.9), "samples sit at start, middle and end")
    let tiny = sampleTimes(duration: 0.1)
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

    for bad in [["a.png"], ["a", "b", "c"], ["a", "b", "--nope"], ["a", "b", "--saturation-min"], ["a", "b", "--saturation-min", "lots"],
                ["a", "b", "--brightness-max", "nan"], ["a", "b", "--brightness-min", "-1"],
                ["a", "b", "--saturation-min", "120"], ["a", "b", "--brightness-min", "111"], ["a", "b", "--background-min", "101"]] {
        expect(throwsError { _ = try parseArguments(bad) }, "rejects arguments: \(bad.joined(separator: " "))")
    }
}

func testReports() throws {
    let reference = solid(200, 100, 100)
    let bad = try score(referenceFile: "<script>.png", videoFile: "v&v.mp4", reference: reference,
                        frames: [frameAt(solid(20, 200, 20))], thresholds: Thresholds())
    let html = htmlReport(bad, referenceJPEG: encodeJPEG(reference), frameJPEGs: [encodeJPEG(reference)])
    expect(!html.contains("<script>") && html.contains("&lt;script&gt;.png"), "file names are escaped in the HTML report")
    expect(html.contains("v&amp;v.mp4"), "ampersands are escaped in the HTML report")
    expect(html.contains(">FAIL<"), "HTML shows the verdict")
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
        try runScorecard(referencePath: reference, videoPath: "\(folder)/\(name)", thresholds: Thresholds()).card
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
    expect(try runScorecard(referencePath: reference, videoPath: folder + "/color-drift.mp4", thresholds: loose).card.passed,
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

do {
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
