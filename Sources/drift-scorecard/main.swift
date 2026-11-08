import DriftCore
import Foundation

do {
    let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp {
        print(usage)
        exit(0)
    }
    let run = try runScorecard(referencePath: options.referencePath, videoPath: options.videoPath, thresholds: options.thresholds)
    print(textReport(run.card))
    try saveReports(run, to: options.outputDirectory)
    print("\nFull report: \(options.outputDirectory)/report.html")
    exit(run.card.passed ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("Could not run the scorecard. \(error.localizedDescription)\n".utf8))
    exit(2)
}
