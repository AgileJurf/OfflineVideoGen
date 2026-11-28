import AVFoundation
import Foundation
import Photos
import SwiftUI
import VideoEngine

/// UI state and orchestration. The working Core ML graph, weights and schedulers
/// are unchanged; no network client participates in generation or style processing.
@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = ""
    @Published var duration = 2 { didSet { savePreferences() } }
    @Published var useFixedSeed = false { didSet { savePreferences() } }
    @Published var generationSeed = "42" { didSet { savePreferences() } }
    @Published var videos: [VideoRecord] = []
    @Published var selectedVideo: VideoRecord?
    @Published private(set) var installed = false
    @Published private(set) var ready = false
    @Published private(set) var working = false { didSet { UIApplication.shared.isIdleTimerDisabled = working } }
    @Published private(set) var installing = false
    @Published private(set) var installingAttentionTrial = false
    @Published private(set) var attentionTrialInstalled = false
    @Published var useAttentionTrial = false {
        didSet {
            if useAttentionTrial, duration > NeodragonAttentionVariant.deviceTrialMaximumSeconds {
                duration = NeodragonAttentionVariant.deviceTrialMaximumSeconds
            }
            savePreferences()
        }
    }
    @Published var useUpstreamDetailPrompt = false {
        didSet { savePreferences() }
    }
    @Published private(set) var exportingFiles = false
    @Published private(set) var progress = GenerationProgress(0, "Ready") {
        didSet { jobLog.append(progress.message) }
    }
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var filesStatus: String?
    @Published private(set) var benchmarkFiles: [URL] = []
    @Published private(set) var pauseReason: GenerationControl.PauseReason?
    @Published private(set) var backgroundStatus = BackgroundGeneration.shared.availabilityMessage
    @Published private(set) var migrationReport: LegacyMigration.Report?
    @Published private(set) var modelStorageBytes: Int64?
    @Published private(set) var libraryStorageBytes: Int64?
    @Published private(set) var maximumSeconds = 9
    @Published var creationRequestID = UUID()
    @Published var benchmarkPromptIndex = 0
    @Published var benchmarkSeed = "42"
    @Published private(set) var jobStartedAt: Date?
    let library: VideoLibrary
    let installer: NeodragonInstaller
    let manifest = try? NeodragonManifest.bundled()
    let attentionManifest = try? NeodragonManifest.bundled(attentionTrial: true)
    let attentionInstaller: NeodragonInstaller
    let attentionDirectory: URL
    let modelDirectory: URL
    let temporaryDirectory: URL
    let benchmarkDirectory: URL
    let exports: LocalExports
    let styles: StyleStore
    let jobLog = JobActivityLog()
    private let migration: LegacyMigration
    private let preferencesURL: URL
    private var preferencesLoaded = false
    private var loaded = false
    private var operation: Task<Void, Never>?
    private var activeBenchmarkLog: BenchmarkLog?
    private var generationControl: GenerationControl?
    private var inForeground = true
    private var installationStage = ModelInstallationStage.preparing
    private let engine = NeodragonEngine()
    private var restoredPrompt: String?
    private var restoredScene: String?
    private var restoredStyle: StyleConditioning?
    private var restoredUsesUpstreamDetail = false
    private struct Preferences: Codable {
        var useFixedSeed: Bool?
        var seed: String?
        var duration: Int?
        var style: VisualStyle?
        var useAttentionTrial: Bool?
        var useUpstreamDetailPrompt: Bool?
    }
    static let benchmarkPrompts = [
        "A small sailboat glides across a calm lake at sunrise.",
        "A person walks slowly across a sunlit courtyard.",
        "A woman smiles and turns her head toward a window.",
        "A dog trots across a grassy field.",
        "Clouds drift above a mountain lake.",
        "A red car drives along a quiet country road.",
        "The camera tracks a cyclist moving along a street.",
        "People walk through a busy outdoor market.",
        "An animated astronaut waves while floating in space.",
        "A hand gently rolls a yellow ball across a table."
    ]
    var supportedDurations: ClosedRange<Int> { 2...(useAttentionTrial ? min(maximumSeconds, NeodragonAttentionVariant.deviceTrialMaximumSeconds) : maximumSeconds) }
    var inferenceProfileID: String { useAttentionTrial ? NeodragonAttentionVariant.profileID : NeodragonMotionComputePolicy.cpuCompatibility.profileID }
    var inferenceProfileName: String { useAttentionTrial ? "Lower-memory attention · device trial" : "Working baseline" }
    var isGenerating: Bool { generationControl != nil }
    var effectivePrompt: String {
        if restoredScene == prompt, restoredStyle == styles.selected, let restoredPrompt {
            // Preserve the exact older style template when changing only the
            // optional detail setting for a saved video's comparison.
            if useUpstreamDetailPrompt == restoredUsesUpstreamDetail { return restoredPrompt }
            if useUpstreamDetailPrompt { return NeodragonPromptConditioning.upstreamDetail(restoredPrompt) }
            let suffix = NeodragonPromptConditioning.upstreamDetailSuffix
            return restoredPrompt.hasSuffix(suffix) ? String(restoredPrompt.dropLast(suffix.count)) : restoredPrompt
        }
        let styled = styles.selected.applying(to: prompt)
        return useUpstreamDetailPrompt ? NeodragonPromptConditioning.upstreamDetail(styled) : styled
    }
    var progressMessage: String {
        switch pauseReason {
        case .cooling: return "Cooling down. Your job will continue when the device is cool."
        case .foregroundRequired: return "Paused in the background. Return to Local Frames to continue."
        case nil: return progress.message
        }
    }
    var estimatedTimeMessage: String {
        if pauseReason != nil { return "Estimate paused during cooling or background waits." }
        return progress.estimate?.displayText ?? "Not enough measurements to estimate the finish time yet."
    }

    init(root: URL? = nil) {
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalFrames", isDirectory: true)
        library = VideoLibrary(root: support.appendingPathComponent("Library", isDirectory: true))
        // Keep this exact path: a TestFlight upgrade must reuse the working weights.
        let modelRoot = support.appendingPathComponent("OptionalModels/Neodragon", isDirectory: true)
        modelDirectory = modelRoot.appendingPathComponent("Installed", isDirectory: true)
        installer = NeodragonInstaller(root: modelRoot)
        let attentionRoot = modelRoot.appendingPathComponent("Variants/Head8-v1", isDirectory: true)
        attentionDirectory = attentionRoot.appendingPathComponent("Installed", isDirectory: true)
        attentionInstaller = NeodragonInstaller(root: attentionRoot)
        temporaryDirectory = support.appendingPathComponent("Temporary", isDirectory: true)
        benchmarkDirectory = support.appendingPathComponent("Benchmarks", isDirectory: true)
        preferencesURL = support.appendingPathComponent("creation-preferences.json")
        let old = (try? Data(contentsOf: preferencesURL)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
        useFixedSeed = old?.useFixedSeed ?? false; generationSeed = old?.seed ?? "42"
        duration = min((old?.useAttentionTrial ?? false) ? NeodragonAttentionVariant.deviceTrialMaximumSeconds : 9, max(2, old?.duration ?? 2))
        useAttentionTrial = old?.useAttentionTrial ?? false
        useUpstreamDetailPrompt = old?.useUpstreamDetailPrompt ?? false
        styles = StyleStore(url: support.appendingPathComponent("visual-styles-v2.json"), legacyStyle: old?.style ?? .default)
        let documents = root?.appendingPathComponent("Exports", isDirectory: true)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        exports = LocalExports(root: documents, historyURL: support.appendingPathComponent("export-history.json"))
        migration = LegacyMigration(root: support)
        preferencesLoaded = true
    }
    private func savePreferences() {
        guard preferencesLoaded else { return }
        do {
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Preserve unknown legacy user preferences rather than replacing their file.
            var values = (try? Data(contentsOf: preferencesURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            values["useFixedSeed"] = useFixedSeed; values["seed"] = generationSeed; values["duration"] = duration
            values["useAttentionTrial"] = useAttentionTrial
            values["useUpstreamDetailPrompt"] = useUpstreamDetailPrompt
            try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]).write(to: preferencesURL, options: .atomic)
        } catch { notice = "These settings could not be saved: " + error.localizedDescription }
    }
    func load() async {
        guard !loaded else { return }; loaded = true
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            videos = try await library.list()
            migrationReport = try await migration.run()
            await refreshInstallation()
            refreshBenchmarkFiles()
            await refreshStorage()
            await publishExports()
            ready = true
        } catch { errorMessage = "Preparation could not finish: " + error.localizedDescription; loaded = false }
    }
    private func refreshInstallation() async {
        installed = await installer.isInstalled()
        attentionTrialInstalled = await attentionInstaller.isAttentionVariantInstalled()
        if !installed || !attentionTrialInstalled { useAttentionTrial = false }
        if installed, let info = try? NeodragonEngine.validateInstallation(at: modelDirectory) { maximumSeconds = info.maximumSeconds }
        else { maximumSeconds = manifest?.maximumSeconds ?? 2 }
        if duration > maximumSeconds { duration = maximumSeconds }
    }
    func reuseSettings(_ video: VideoRecord) {
        guard !working, video.canReuseSettings else { return }
        let usedTrial = video.metrics.profileID == NeodragonAttentionVariant.profileID
        guard !usedTrial || attentionTrialInstalled else {
            errorMessage = "Install the optional attention trial in Models to reuse this video’s inference settings."
            return
        }
        useAttentionTrial = usedTrial
        useUpstreamDetailPrompt = video.upstreamDetailPrompt ?? false
        prompt = video.prompt; duration = min(maximumSeconds, video.duration); useFixedSeed = true; generationSeed = String(video.seed)
        if let condition = video.styleConditioning {
            if condition.isCustom { try? styles.upsert(condition) }
            styles.select(condition)
        } else { styles.select(StyleCatalog.definition(video.style)) }
        restoredScene = prompt; restoredStyle = styles.selected; restoredPrompt = video.effectivePrompt
        restoredUsesUpstreamDetail = video.upstreamDetailPrompt ?? false
        selectedVideo = nil; creationRequestID = UUID()
        notice = "Original prompt, model input and seed restored. Editing the scene or style creates new conditioning."
    }
    func clearRestoredConditioning() { restoredPrompt = nil; restoredScene = nil; restoredStyle = nil }
    func runBaselineBenchmark() {
        guard installed, ready, !working, !exportingFiles else { return }
        useAttentionTrial = false
        useUpstreamDetailPrompt = false
        prompt = Self.benchmarkPrompts[benchmarkPromptIndex]; duration = 2
        useFixedSeed = true; generationSeed = benchmarkSeed; styles.select(StyleCatalog.definition(.default))
        clearRestoredConditioning(); generate()
    }
    func runAttentionBenchmark(seconds: Int) {
        guard installed, attentionTrialInstalled, ready, !working, !exportingFiles, [2, 5].contains(seconds) else { return }
        useAttentionTrial = true
        useUpstreamDetailPrompt = false
        prompt = Self.benchmarkPrompts[benchmarkPromptIndex]; duration = seconds
        useFixedSeed = true; generationSeed = benchmarkSeed; styles.select(StyleCatalog.definition(.default))
        clearRestoredConditioning(); generate()
    }
    func generate() {
        guard ready, installed, !working, !exportingFiles else { return }
        do {
            let seed: UInt64
            if useFixedSeed {
                guard let value = UInt64(generationSeed) else { throw GenerationError.incompatibleModel("Enter a whole-number seed from 0 to 18446744073709551615.") }
                seed = value
            } else { seed = UInt64.random(in: 0...UInt64.max) }
            let condition = styles.selected
            let detailConditioning = useUpstreamDetailPrompt
            try condition.validate()
            let style = VisualStyle(rawValue: condition.id) ?? .default
            let request = try NeodragonGenerationRequest(prompt: prompt, duration: duration, seed: seed, style: style, modelPrompt: effectivePrompt)
            let installation = try NeodragonEngine.validateInstallation(at: modelDirectory)
            let geometry = try NeodragonModel.geometry(seconds: duration)
            let policy = NeodragonMotionComputePolicy.cpuCompatibility
            let variantDirectory: URL? = useAttentionTrial ? attentionDirectory : nil
            if let variantDirectory {
                _ = try NeodragonAttentionVariant.validateInstallation(at: variantDirectory)
                guard duration <= NeodragonAttentionVariant.deviceTrialMaximumSeconds else {
                    throw GenerationError.incompatibleModel("The attention device trial currently supports up to five seconds.")
                }
            }
            jobLog.start(); jobStartedAt = Date()
            let log = try makeLog(kind: "generation", fields: [
                "prompt": request.prompt, "effectiveModelPrompt": request.effectivePrompt, "visualStyle": condition.id,
                "styleName": condition.name, "styleConditioningVersion": "2", "styleMethod": "local-prompt-conditioning",
                "detailConditioning": useUpstreamDetailPrompt ? "upstream-default-modifier-v1" : "original-or-restored-input",
                "seed": String(seed), "durationSeconds": String(duration), "width": "512", "height": "320", "fps": "24",
                "generationMode": GenerationMode.textToVideo.rawValue, "requestedFraming": "native-16:10",
                "profileID": inferenceProfileID, "precision": "Mixed FP16/FP32; T5 Float32", "motionComputePolicy": policy.rawValue,
                "configuration": "Neodragon · \(inferenceProfileName) · mixed precision · native 24 FPS",
                "expectedPartitions": installation.modelNames.joined(separator: ","),
                "expectedEvaluations": String(4 + (geometry.latentFrames - 1) * 3),
                "schedule": "SSD-1B LCM 4 steps, then 3 flow evaluations per subsequent latent unit",
                "cacheCondition": "uncontrolled OS cache; four tiny decoder models retained within the job"])
            styles.recordUse(); working = true; activeBenchmarkLog = log; notice = nil; errorMessage = nil; pauseReason = nil
            let control = GenerationControl { [weak self] reason in
                Task { @MainActor in
                    guard let self else { return }
                    self.pauseReason = reason; self.jobLog.append(reason == nil ? "Generation continuing" : self.progressMessage)
                    BackgroundGeneration.shared.report(self.progress, paused: reason == nil ? nil : self.progressMessage)
                }
            }
            generationControl = control; control.setForeground(inForeground)
            progress = .init(0, "Preparing generation")
            BackgroundGeneration.shared.statusChanged = { [weak self] in self?.backgroundStatus = $0 }
            BackgroundGeneration.shared.start(control: control, log: log, onExpiration: { [weak self] in
                self?.operation?.cancel(); self?.notice = "iOS ended the job. Completed videos remain in Library."
            }) { [self] in
                operation = Task {
                    let output = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    var succeeded = false
                    defer { try? FileManager.default.removeItem(at: output); finish(success: succeeded) }
                    do {
                        let free = try temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                        guard free > 1024 * 1024 * 1024 else { throw GenerationError.insufficientStorage }
                        let metrics = try await engine.generate(request, modelsAt: modelDirectory, output: output, benchmark: log, control: control, motionComputePolicy: policy, attentionVariantAt: variantDirectory) { progress in
                            Task { @MainActor in self.progress = progress; BackgroundGeneration.shared.report(progress, paused: self.pauseReason == nil ? nil : self.progressMessage) }
                        }
                        try Task.checkCancellation()
                        progress = .init(1, "Saving output")
                        let item = try await library.addNeodragon(temporaryURL: output, request: request, metrics: metrics, conditioning: condition,
                                                                upstreamDetailPrompt: detailConditioning)
                        videos = try await library.list(); selectedVideo = item
                        try log.finish(status: "succeeded", fields: ["videoID": item.id.uuidString])
                        succeeded = true
                    } catch is CancellationError {
                        try? log.finish(status: "cancelled"); notice = "Generation cancelled. The local journal is retained."
                    } catch {
                        var fields = BenchmarkLog.diagnosticErrorFields(error); fields["error"] = String(describing: error)
                        try? log.finish(status: "failed", fields: fields); errorMessage = error.localizedDescription
                    }
                }
            }
        } catch { jobLog.finish("Could not start: " + error.localizedDescription); errorMessage = error.localizedDescription }
    }
    func install() { startInstallation(attentionTrial: false) }
    func installAttentionTrial() { startInstallation(attentionTrial: true) }
    private func startInstallation(attentionTrial: Bool) {
        guard ready, !working, !exportingFiles, let manifest = attentionTrial ? attentionManifest : self.manifest,
              !attentionTrial || installed else { return }
        let target = attentionTrial ? attentionInstaller : installer
        do {
            var fields = ["packageVersion": manifest.modelVersion]
            if attentionTrial, let file = Bundle.main.url(forResource: "neodragon-attention-manifest", withExtension: "json") {
                fields["attentionManifestSHA256"] = try FileIntegrity.sha256(file)
            }
            let log = try makeLog(kind: "installation", fields: fields)
            working = true; installing = true; notice = nil; activeBenchmarkLog = log
            installingAttentionTrial = attentionTrial
            installationStage = .preparing
            progress = .init(0, "Preparing model installation")
            operation = Task {
                defer { finish() }
                do {
                    try await target.install(manifest, baseAt: attentionTrial ? modelDirectory : nil, benchmark: log, stage: { stage in
                        Task { @MainActor in self.installationStage = stage }
                    }) { progress in Task { @MainActor in self.progress = progress } }
                    await refreshInstallation()
                    try log.finish(status: (attentionTrial ? attentionTrialInstalled : installed) ? "succeeded" : "failed")
                } catch is CancellationError {
                    try? log.finish(status: "cancelled"); notice = "Installation paused. Verified downloads are kept for the next attempt."
                } catch {
                    var fields = BenchmarkLog.diagnosticErrorFields(error); fields["error"] = String(describing: error)
                    try? log.finish(status: "failed", fields: fields); errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func removeModel() async {
        guard !working, !exportingFiles else { return }
        do { try await installer.remove(); await refreshInstallation(); await refreshStorage() }
        catch { errorMessage = error.localizedDescription }
    }
    func removeAttentionTrial() async {
        guard !working, !exportingFiles else { return }
        do { try await attentionInstaller.remove(); useAttentionTrial = false; await refreshInstallation(); await refreshStorage() }
        catch { errorMessage = error.localizedDescription }
    }
    func cancel() {
        jobLog.append("Cancellation requested; waiting for the current model operation to return")
        if let operation { operation.cancel() }
        else if working { try? activeBenchmarkLog?.finish(status: "cancelled"); finish() }
    }
    func sceneChanged(_ phase: ScenePhase) {
        guard phase != .inactive else { return }
        inForeground = phase == .active; generationControl?.setForeground(inForeground)
        activeBenchmarkLog?.record("scene_changed", fields: ["state": inForeground ? "foreground" : "background"])
        if !inForeground, working, generationControl == nil { operation?.cancel() }
    }
    func handleMemoryWarning() {
        ThumbnailCache.shared.removeAll()
        let stage = installing ? installationStage.rawValue : progress.message
        activeBenchmarkLog?.record("memory_warning", fields: ["activity": installing ? "installation" : "generation", "visibleStage": stage])
        guard working else { return }
        if installing && !installationStage.shouldPauseForMemoryWarning { notice = "iOS reported memory pressure. Bounded download or verification is continuing."; return }
        jobLog.append("iOS reported memory pressure at: " + stage)
        cancel(); errorMessage = "Work stopped after iOS reported memory pressure. Last stage: \(stage). Completed videos and the local journal are preserved."
    }
    private func finish(success: Bool = false) {
        jobLog.finish(success ? "Video saved to Library" : (errorMessage == nil ? "Job stopped" : "Job ended with an error"))
        BackgroundGeneration.shared.finish(success: success)
        working = false; installing = false; installingAttentionTrial = false; operation = nil; activeBenchmarkLog = nil; generationControl = nil; pauseReason = nil
        refreshBenchmarkFiles()
        Task { await publishExports(); await refreshStorage() }
    }
    private func makeLog(kind: String, fields: [String: String] = [:]) throws -> BenchmarkLog {
        var metadata = fields
        metadata["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        metadata["appBuild"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        metadata["modelID"] = NeodragonModel.identifier; metadata["modelRevision"] = NeodragonModel.weightsRevision
        if let file = Bundle.main.url(forResource: "neodragon-manifest", withExtension: "json") { metadata["manifestSHA256"] = try FileIntegrity.sha256(file) }
        if useAttentionTrial || installingAttentionTrial, let file = Bundle.main.url(forResource: "neodragon-attention-manifest", withExtension: "json") {
            metadata["attentionManifestSHA256"] = try FileIntegrity.sha256(file)
        }
        if let file = Bundle.main.url(forResource: "build-revision", withExtension: "txt") { metadata["sourceRevision"] = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) }
        let buffer = jobLog.buffer
        let activity: (@Sendable (BenchmarkLog.Activity) -> Void)?
        if kind == "generation" { activity = { event in buffer.append(elapsed: event.elapsedSeconds, message: event.message) } }
        else { activity = nil }
        return try BenchmarkLog(url: benchmarkDirectory.appendingPathComponent("\(kind)-\(UUID().uuidString).jsonl"), kind: kind, metadata: metadata,
                                activity: activity)
    }
    private func refreshBenchmarkFiles() {
        benchmarkFiles = ((try? FileManager.default.contentsOfDirectory(at: benchmarkDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["jsonl", "json", "mp4"].contains($0.pathExtension) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func videoSources(_ video: VideoRecord) -> [LocalExports.Source] {
        [.init(url: library.videoURL(video.id), folder: .videos, filename: "LocalFrames-\(video.id).mp4"),
         .init(url: library.metadataURL(video.id), folder: .videos, filename: "LocalFrames-\(video.id).json")]
    }
    func publishExports() async {
        guard !working, !exportingFiles else { return }; exportingFiles = true
        defer { exportingFiles = false }
        do {
            let sources = videos.flatMap(videoSources) + benchmarkFiles.map { LocalExports.Source(url: $0, folder: .benchmarks, filename: $0.lastPathComponent) }
            _ = try await exports.publish(sources)
            filesStatus = "Files → Browse → On My iPhone → Local Frames"
        } catch { filesStatus = "Some export copies could not be saved: " + error.localizedDescription }
    }
    func exportBenchmarks() async -> [URL] {
        guard !working, !exportingFiles else { return [] }; exportingFiles = true
        defer { exportingFiles = false }
        do { return try await exports.publish(benchmarkFiles.map { .init(url: $0, folder: .benchmarks, filename: $0.lastPathComponent) }, explicit: true) }
        catch { errorMessage = error.localizedDescription; return [] }
    }
    func exportVideo(_ video: VideoRecord) async -> [URL] {
        guard !working, !exportingFiles else { return [] }; exportingFiles = true
        defer { exportingFiles = false }
        do { return try await exports.publish(videoSources(video), explicit: true) }
        catch { errorMessage = error.localizedDescription; return [] }
    }
    func saveToPhotos(_ video: VideoRecord) async {
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.library.videoURL(video.id)) }; notice = "Video saved to Photos." }
        catch { errorMessage = error.localizedDescription }
    }
    func delete(_ video: VideoRecord) async {
        guard !working else { return }
        do { try await library.delete(video); videos = try await library.list(); await refreshStorage() }
        catch { errorMessage = error.localizedDescription }
    }
    func refreshStorage() async {
        guard !working else { return }
        let modelRoot = modelDirectory.deletingLastPathComponent(), videoRoot = library.root
        let totals = await Task.detached(priority: .utility) { (Self.bytes(in: modelRoot), Self.bytes(in: videoRoot)) }.value
        modelStorageBytes = totals.0; libraryStorageBytes = totals.1
    }
    nonisolated static func bytes(in directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]) else { return 0 }
        var result: Int64 = 0
        for case let url as URL in files {
            if let value = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]), value.isRegularFile == true, value.isSymbolicLink != true { result += Int64(value.fileSize ?? 0) }
        }
        return result
    }
}
