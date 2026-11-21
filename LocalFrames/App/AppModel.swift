import Foundation
import Photos
import SwiftUI
import VideoEngine
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = ""
    @Published var duration = 2
    @Published var videos: [VideoRecord] = []
    @Published var selectedVideo: VideoRecord?
    @Published var installed = false
    @Published var working = false {
        didSet { UIApplication.shared.isIdleTimerDisabled = working }
    }
    @Published var installing = false
    @Published var progress = GenerationProgress(0, "Ready")
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var benchmarkFiles: [URL] = []
    @Published var benchmarkPromptIndex = 0
    @Published var benchmarkSeed = "42"
    static let benchmarkPrompts = [
        "A small sailboat glides across a calm lake at sunrise.",
        "A red flag waves gently in the wind against a blue sky.",
        "A yellow ball rolls slowly across a wooden table."
    ]
    let library: VideoLibrary
    let installer: ModelInstaller
    let modelDirectory: URL
    let temporaryDirectory: URL
    let benchmarkDirectory: URL
    private let engine = MOVDEngine()
    private var operation: Task<Void, Never>?

    init(root: URL? = nil) {
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalFrames", isDirectory: true)
        library = VideoLibrary(root: support.appendingPathComponent("Library", isDirectory: true))
        let modelRoot = support.appendingPathComponent("Models", isDirectory: true)
        modelDirectory = modelRoot.appendingPathComponent("Installed", isDirectory: true)
        installer = ModelInstaller(root: modelRoot)
        temporaryDirectory = support.appendingPathComponent("Temporary", isDirectory: true)
        benchmarkDirectory = support.appendingPathComponent("Benchmarks", isDirectory: true)
    }

    func load() async {
        do {
            // Each generation owns its file. An interrupted previous session leaves only this directory to clean.
            if FileManager.default.fileExists(atPath: temporaryDirectory.path) { try FileManager.default.removeItem(at: temporaryDirectory) }
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            videos = try await library.list()
            installed = await installer.isInstalled()
            refreshBenchmarkFiles()
        } catch { errorMessage = error.localizedDescription }
    }

    func generate() { beginGeneration(benchmarking: false) }

    func runBaselineBenchmark() {
        guard installed, !working else { return }
        prompt = Self.benchmarkPrompts[benchmarkPromptIndex]
        duration = 2
        beginGeneration(benchmarking: true)
    }

    private func beginGeneration(benchmarking: Bool) {
        guard installed, !working else { return }
        do {
            let seed: UInt64
            if benchmarking {
                guard let value = UInt64(benchmarkSeed) else {
                    errorMessage = "Enter a whole-number seed from 0 to 18446744073709551615."
                    return
                }
                seed = value
            } else { seed = UInt64.random(in: 0...UInt64.max) }
            let request = try GenerationRequest(prompt: prompt, duration: duration, seed: seed)
            let log = benchmarking ? try makeBenchmarkLog(kind: "generation", fields: [
                "prompt": request.prompt, "seed": String(request.seed), "durationSeconds": String(request.duration),
                "width": String(request.width), "height": String(request.height), "fps": String(request.framesPerSecond),
                "configuration": "baseline-fp32-stdit-vae-t5-int8", "schedule": "30 points; leap index 20; 21 predictions; TDTM first 10; CFG 7; latent frames 20",
                "cacheCondition": "uncontrolled OS cache; record first/repeat run separately; process is not restarted automatically"
            ]) : nil
            working = true
            installing = false
            progress = .init(0, "Preparing generation")
            operation = Task {
                let output = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                defer { try? FileManager.default.removeItem(at: output); finish() }
                do {
                    let free = try temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard free > 1024 * 1024 * 1024 else { throw GenerationError.insufficientStorage }
                    let metrics = try await engine.generate(request, modelsAt: modelDirectory, output: output, benchmark: log) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    log?.record("engine_completed", fields: ["elapsedSeconds": String(metrics.elapsedSeconds)])
                    try Task.checkCancellation()
                    let item = try await library.add(temporaryURL: output, request: request, metrics: metrics)
                    videos = try await library.list()
                    if let log {
                        let videoURL = library.videoURL(item.id)
                        let asset = AVURLAsset(url: videoURL)
                        let videoDuration = try await asset.load(.duration).seconds
                        let tracks = try await asset.loadTracks(withMediaType: .video)
                        guard let track = tracks.first else { throw GenerationError.encodingFailed("No video track") }
                        let fps = try await track.load(.nominalFrameRate)
                        let size = try await track.load(.naturalSize)
                        guard abs(videoDuration - 2) < 0.05, abs(fps - 12) < 0.1,
                              Int(size.width) == 256, Int(size.height) == 256 else {
                            throw GenerationError.encodingFailed("Benchmark output dimensions or duration differ from the requested baseline")
                        }
                        let artifact = log.url.deletingPathExtension().appendingPathExtension("mp4")
                        try FileManager.default.copyItem(at: videoURL, to: artifact)
                        try JSONEncoder().encode(item).write(to: log.url.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
                        try log.finish(status: "succeeded", fields: ["videoFile": artifact.lastPathComponent,
                            "videoSHA256": try ModelInstaller.sha256(artifact), "measuredDurationSeconds": String(videoDuration),
                            "measuredFPS": String(fps), "measuredWidth": String(Int(size.width)), "measuredHeight": String(Int(size.height)),
                            "visualQuality": "not assessed; inspect exported video"])
                    }
                    selectedVideo = item
                } catch is CancellationError {
                    try? log?.finish(status: "cancelled")
                    notice = "Generation cancelled."
                } catch {
                    try? log?.finish(status: "failed", fields: ["error": String(describing: error)])
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func install() {
        guard !working else { return }
        do {
            let manifest = try ModelManifest.bundled()
            let log = try makeBenchmarkLog(kind: "installation", fields: ["expectedDownloadBytes": String(manifest.archives.reduce(Int64(0)) { $0 + $1.bytes })])
            working = true
            installing = true
            progress = .init(0, "Preparing model download")
            operation = Task {
                defer { finish() }
                do {
                    try await installer.install(manifest, benchmark: log) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    installed = await installer.isInstalled()
                    try log.finish(status: installed ? "succeeded" : "failed")
                } catch is CancellationError {
                    try? log.finish(status: "cancelled")
                    notice = "Installation paused. Tap Install to resume available downloads."
                } catch {
                    try? log.finish(status: "failed", fields: ["error": String(describing: error)])
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeModel() async {
        guard !working else { return }
        do { try await installer.remove(); installed = false }
        catch { errorMessage = error.localizedDescription }
    }

    func cancel() { operation?.cancel() }

    func interrupt() {
        if working { operation?.cancel(); notice = "Work paused because the app was interrupted. Keep Local Frames open while generating." }
    }

    private func finish() { working = false; installing = false; operation = nil; refreshBenchmarkFiles() }

    private func makeBenchmarkLog(kind: String, fields: [String: String] = [:]) throws -> BenchmarkLog {
        var metadata = fields
        metadata["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        metadata["appBuild"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        if let revision = Bundle.main.url(forResource: "build-revision", withExtension: "txt") {
            metadata["sourceRevision"] = try String(contentsOf: revision, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let manifest = Bundle.main.url(forResource: "model-manifest", withExtension: "json") {
            metadata["manifestSHA256"] = try ModelInstaller.sha256(manifest)
        }
        return try BenchmarkLog(url: benchmarkDirectory.appendingPathComponent("\(kind)-\(UUID().uuidString).jsonl"), kind: kind, metadata: metadata)
    }

    private func refreshBenchmarkFiles() {
        benchmarkFiles = ((try? FileManager.default.contentsOfDirectory(at: benchmarkDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jsonl", "json", "mp4"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func inspectComputePlans() {
        guard installed, !working, !videos.isEmpty else { return }
        do {
            let log = try makeBenchmarkLog(kind: "compute-plans", fields: ["evidenceType": "planner estimates, not runtime placement or utilization"])
            working = true
            installing = false
            progress = .init(0, "Preparing compute-plan inspection")
            operation = Task {
                defer { finish() }
                do {
                    try await ComputePlanAudit().run(modelsAt: modelDirectory, log: log) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    try log.finish(status: "completed_with_possible_unsupported_plans")
                    notice = "Compute-plan estimates are ready to export. They do not establish measured acceleration."
                } catch {
                    try? log.finish(status: error is CancellationError ? "cancelled" : "failed", fields: ["error": String(describing: error)])
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ video: VideoRecord) async {
        do {
            try await library.delete(video)
            videos = try await library.list()
            if selectedVideo?.id == video.id { selectedVideo = nil }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveToPhotos(_ video: VideoRecord) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            errorMessage = "Allow Local Frames to add videos in Settings → Privacy & Security → Photos."
            return
        }
        let url = library.videoURL(video.id)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            notice = "Saved to Photos."
        } catch { errorMessage = error.localizedDescription }
    }
}
