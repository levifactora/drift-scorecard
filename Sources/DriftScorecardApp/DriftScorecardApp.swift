import AppKit
import DriftCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct DriftScorecardApp: App {
    var body: some Scene {
        WindowGroup("Drift Scorecard") { ContentView().frame(width: 560) }
            .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class Runner: ObservableObject {
    @Published var picture: URL?
    @Published var videos: [URL] = []
    @Published var preset = "standard"
    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var message: String?
    @Published var lastReport: URL?

    var ready: Bool { picture != nil && !videos.isEmpty && !running }

    func addPicture(_ url: URL) {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else {
            message = "That file is not a picture."
            return
        }
        picture = url
        message = nil
    }

    func addVideos(_ urls: [URL]) {
        videos = urls
        message = nil
    }

    func start(output custom: URL? = nil, quitWhenDone: Bool = false) {
        guard let picture, !videos.isEmpty, !running else { return }
        running = true
        done = 0
        total = 0
        message = nil
        lastReport = nil
        let inputs = videos.map(\.path)
        let thresholds = presetThresholds(preset) ?? Thresholds()
        let stamp = Self.stamp.string(from: Date())
        let output = custom ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Drift Scorecard Reports/\(stamp)")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let videos = try expandInputs(inputs).videos
                let result = runBatch(referencePath: picture.path, videos: videos, thresholds: thresholds, frameCount: defaultFrameCount) { done, total, _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.done = max(self.done, done)
                        self.total = total
                    }
                }
                try saveBatch(result, referencePath: picture.path, thresholds: thresholds, to: output.path)
                let report = output.appendingPathComponent("report.html")
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.running = false
                    self.lastReport = report
                    if quitWhenDone { NSApp.terminate(nil) } else { NSWorkspace.shared.open(report) }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.running = false
                    self.message = error.localizedDescription
                    if quitWhenDone { exit(1) }
                }
            }
        }
    }

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()
}

struct DropCard: View {
    let number: String
    let title: String
    let detail: String
    let done: Bool
    let onChoose: () -> Void
    let onDrop: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(done ? Color.accentColor : Color.secondary.opacity(0.15)).frame(width: 34, height: 34)
                    if done { Image(systemName: "checkmark").foregroundColor(.white).font(.system(size: 14, weight: .bold)) }
                    else { Text(number).font(.system(size: 14, weight: .semibold)).foregroundColor(.secondary) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text("Choose").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(targeted ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: done ? [] : [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in providers {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { urls.append(url) } }
                    group.leave()
                }
            }
            group.notify(queue: .main) { if !urls.isEmpty { onDrop(urls) } }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: targeted)
    }
}

struct ContentView: View {
    @StateObject private var runner = Runner()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Drift Scorecard").font(.system(size: 28, weight: .bold))
                Text("See where AI video slips away from your reference picture.").foregroundColor(.secondary)
            }
            .padding(.bottom, 6)

            DropCard(number: "1", title: "Reference picture", detail: runner.picture?.lastPathComponent ?? "Drop a picture here, or click to choose", done: runner.picture != nil, onChoose: choosePicture) { urls in
                if let first = urls.first { runner.addPicture(first) }
            }
            DropCard(number: "2", title: "Video or folder", detail: videosText, done: !runner.videos.isEmpty, onChoose: chooseVideos) { runner.addVideos($0) }

            HStack {
                Text("Limits").foregroundColor(.secondary)
                Picker("Limits", selection: $runner.preset) {
                    Text("Standard").tag("standard")
                    Text("Cartoon").tag("cartoon")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
                Spacer()
            }

            if runner.running {
                VStack(alignment: .leading, spacing: 6) {
                    if runner.total > 0 { ProgressView(value: Double(runner.done), total: Double(runner.total)) } else { ProgressView().progressViewStyle(.linear) }
                    Text(runner.total > 0 ? "Checked \(runner.done) of \(runner.total) clips" : "Getting started…").font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            if let message = runner.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundColor(.red)
            }

            HStack {
                if let report = runner.lastReport {
                    Button("Open last report") { NSWorkspace.shared.open(report) }
                }
                Spacer()
                Button { runner.start() } label: {
                    Text(runner.running ? "Checking…" : "Check clips").frame(minWidth: 110)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!runner.ready)
            }
        }
        .padding(28)
        .onAppear(perform: autorun)
    }

    private var videosText: String {
        if runner.videos.isEmpty { return "Drop videos or a folder here, or click to choose" }
        return runner.videos.count == 1 ? runner.videos[0].lastPathComponent : "\(runner.videos.count) items"
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose your reference picture"
        if panel.runModal() == .OK, let url = panel.url { runner.addPicture(url) }
    }

    private func chooseVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .folder]
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose videos or a folder of videos"
        if panel.runModal() == .OK { runner.addVideos(panel.urls) }
    }

    /// Lets a test run the real app without clicking.
    private func autorun() {
        let environment = ProcessInfo.processInfo.environment
        guard let picture = environment["DRIFT_TEST_REFERENCE"], let videos = environment["DRIFT_TEST_VIDEOS"], let output = environment["DRIFT_TEST_OUT"] else { return }
        runner.picture = URL(fileURLWithPath: picture)
        runner.videos = [URL(fileURLWithPath: videos)]
        runner.start(output: URL(fileURLWithPath: output), quitWhenDone: true)
    }
}
