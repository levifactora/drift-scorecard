import DriftCore
import Foundation

let folder = CommandLine.arguments.dropFirst().first ?? "samples"
do {
    try makeSamples(in: folder)
    print("Made reference.png, steady.mp4, color-drift.mp4 and background-drift.mp4 in \(folder)/")
} catch {
    FileHandle.standardError.write(Data("Could not make the samples. \(error.localizedDescription)\n".utf8))
    exit(2)
}
