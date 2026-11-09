import DriftCore
import Foundation

do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp {
        print(usage)
        exit(0)
    }
    guard FileManager.default.fileExists(atPath: options.referencePath) else { throw ScorecardError.fileNotFound(options.referencePath) }
    let (videos, batch) = try expandInputs(options.videoPaths)
    let decisions = try options.decisionsPath.map { try parseDecisions(String(contentsOfFile: $0, encoding: .utf8)) }

    if !batch && decisions == nil {
        let run = try runScorecard(referencePath: options.referencePath, videoPath: videos[0], thresholds: options.thresholds, frameCount: options.frameCount)
        print(textReport(run.card))
        try saveReports(run, to: options.outputDirectory)
        print("\nFull report: \(options.outputDirectory)/report.html")
        exit(run.card.passed ? 0 : 1)
    }

    let outcomes = runBatch(referencePath: options.referencePath, videos: videos, thresholds: options.thresholds, frameCount: options.frameCount, outputDirectory: options.outputDirectory)
    print(batchText(outcomes))
    try saveBatch(outcomes, referenceFile: URL(fileURLWithPath: options.referencePath).lastPathComponent, thresholds: options.thresholds, to: options.outputDirectory)
    if let decisions { print("\n" + evaluationText(try evaluate(outcomes, decisions: decisions))) }
    print("\nFull report: \(options.outputDirectory)/report.html")
    exit(outcomes.allSatisfy { $0.verdict == .pass } ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("Could not run the scorecard. \(error.localizedDescription)\n".utf8))
    exit(2)
}
