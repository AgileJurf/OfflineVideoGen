import Foundation
import Photos
import SwiftUI
import VideoEngine

@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = ""
    @Published var duration = 2
    @Published var videos: [VideoRecord] = []
    @Published var selectedVideo: VideoRecord?
    @Published var installed = false
    @Published var working = false
    @Published var installing = false
    @Published var progress = GenerationProgress(0, "Ready")
    @Published var errorMessage: String?
    @Published var notice: String?
    let library: VideoLibrary
    let installer: ModelInstaller
    let modelDirectory: URL
    let temporaryDirectory: URL
    private let engine = MOVDEngine()
    private var operation: Task<Void, Never>?

    init(root: URL? = nil) {
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalFrames", isDirectory: true)
        library = VideoLibrary(root: support.appendingPathComponent("Library", isDirectory: true))
        let modelRoot = support.appendingPathComponent("Models", isDirectory: true)
        modelDirectory = modelRoot.appendingPathComponent("Installed", isDirectory: true)
        installer = ModelInstaller(root: modelRoot)
        temporaryDirectory = support.appendingPathComponent("Temporary", isDirectory: true)
    }

    func load() async {
        do {
            // Each generation owns its file. An interrupted previous session leaves only this directory to clean.
            if FileManager.default.fileExists(atPath: temporaryDirectory.path) { try FileManager.default.removeItem(at: temporaryDirectory) }
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            videos = try await library.list()
            installed = await installer.isInstalled()
        } catch { errorMessage = error.localizedDescription }
    }

    func generate() {
        guard installed, !working else { return }
        do {
            let request = try GenerationRequest(prompt: prompt, duration: duration)
            working = true
            installing = false
            progress = .init(0, "Preparing generation")
            operation = Task {
                let output = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                defer { try? FileManager.default.removeItem(at: output); finish() }
                do {
                    let free = try temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard free > 1024 * 1024 * 1024 else { throw GenerationError.insufficientStorage }
                    let metrics = try await engine.generate(request, modelsAt: modelDirectory, output: output) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    try Task.checkCancellation()
                    let item = try await library.add(temporaryURL: output, request: request, metrics: metrics)
                    videos = try await library.list()
                    selectedVideo = item
                } catch is CancellationError {
                    notice = "Generation cancelled."
                } catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func install() {
        guard !working else { return }
        do {
            let manifest = try ModelManifest.bundled()
            working = true
            installing = true
            progress = .init(0, "Preparing model download")
            operation = Task {
                defer { finish() }
                do {
                    try await installer.install(manifest) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    installed = await installer.isInstalled()
                } catch is CancellationError { notice = "Installation paused. Tap Install to resume available downloads." }
                catch { errorMessage = error.localizedDescription }
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

    private func finish() { working = false; installing = false; operation = nil }

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
