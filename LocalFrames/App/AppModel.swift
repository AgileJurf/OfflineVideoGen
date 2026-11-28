import Foundation
import Photos
import SwiftUI
import VideoEngine
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @Published var prompt = ""
    @Published var duration = 2
    @Published var generationModel: VideoModelChoice = .movd {
        didSet {
            if generationModel == .neodragon { smoothAfterGeneration = false }
            if generationModel == .movd && duration > 5 { duration = 5 }
            saveCreationPreferences()
        }
    }
    @Published var neodragonInstalled = false
    @Published var installingNeodragon = false
    let neodragonInstaller: NeodragonInstaller
    let neodragonDirectory: URL
    let neodragonManifest = try? NeodragonManifest.bundled()
    var selectedModelInstalled: Bool { generationModel == .movd ? installed : neodragonInstalled }
    var supportedDurations: ClosedRange<Int> { generationModel == .movd ? 2...5 : 2...(neodragonManifest?.maximumSeconds ?? 2) }
    @Published var smoothAfterGeneration = false { didSet { saveCreationPreferences() } }
    @Published private(set) var pendingSmoothingVideo: VideoRecord?
    @Published var workflowReview: VideoRecord?
    @Published private(set) var generationWillSmooth = false
    @Published var visualStyle: VisualStyle = .default { didSet { saveCreationPreferences() } }
    @Published var outputFraming: OutputFraming = .square { didSet { saveCreationPreferences() } }
    @Published var useFixedSeed = false { didSet { saveCreationPreferences() } }
    @Published var generationSeed = "42" { didSet { saveCreationPreferences() } }
    @Published var recordCreationDiagnostics = false { didSet { saveCreationPreferences() } }
    @Published var creationRequestID = UUID()
    @Published var exportingCrop = false
    @Published private(set) var smoothingActive = false
    @Published private(set) var smoothingPreview: PreparedSmoothing?
    @Published private(set) var smoothingResult: VideoRecord?
    @Published private(set) var smoothingMessage: String?
    private let smoothingClient: RIFEClient
    let helperAccount: HFAccountModel
    @Published var videos: [VideoRecord] = []
    @Published var selectedVideo: VideoRecord?
    @Published var installed = false
    @Published var working = false {
        didSet { UIApplication.shared.isIdleTimerDisabled = working }
    }
    @Published var installing = false
    @Published var installationStage: ModelInstallationStage = .preparing
    @Published var progress = GenerationProgress(0, "Ready")
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var benchmarkFiles: [URL] = []
    @Published var benchmarkPromptIndex = 0
    @Published var benchmarkSeed = "42"
    @Published var pauseReason: GenerationControl.PauseReason?
    @Published var backgroundStatus = BackgroundGeneration.shared.availabilityMessage
    @Published var savedBaselineDescription: String?
    static let benchmarkPrompts = [
        "A small sailboat glides across a calm lake at sunrise.",
        "A red flag waves gently in the wind against a blue sky.",
        "A yellow ball rolls slowly across a wooden table."
    ]
    let library: VideoLibrary
    let installer: ModelInstaller
    let support: OnlineSupport
    @Published var hasModelRollback = false
    let modelDirectory: URL
    let temporaryDirectory: URL
    let benchmarkDirectory: URL
    let resumeDirectory: URL
    private let preferencesURL: URL
    private var pendingSmoothingURL: URL { preferencesURL.deletingLastPathComponent().appendingPathComponent("pending-smoothing.json") }
    private var preferencesLoaded = false
    private struct CreationPreferences: Codable {
        let style: VisualStyle
        let framing: OutputFraming
        let useFixedSeed: Bool
        let seed: String
        var recordDiagnostics: Bool? = nil
        var smoothAfterGeneration: Bool? = nil
        var model: VideoModelChoice? = nil
    }
    private let engine = MOVDEngine()
    private let neodragonEngine = NeodragonEngine()
    private var operation: Task<Void, Never>?
    private var activeBenchmarkLog: BenchmarkLog?
    private var pausedForMemory = false
    private var generationControl: GenerationControl?
    private var loaded = false
    private var inForeground = true
    private var pendingBaseline: BaselineJob?
    private struct BaselineJob: Codable {
        let id: UUID
        let request: GenerationRequest
        var previousJournal: String?
    }

    var progressMessage: String {
        switch pauseReason {
        case .cooling: return "Paused to cool down. Generation will continue automatically when the phone is cool."
        case .foregroundRequired: return "Paused while the app is in the background. Open Local Frames to continue."
        case nil: return progress.message
        }
    }

    var estimatedTimeMessage: String {
        if pauseReason != nil { return "Time estimate paused; cooling and background waits have no predictable duration." }
        if progress.fraction >= 0.99 { return "Finishing and saving your video…" }
        return progress.estimate?.displayText ?? "Estimating finish time from this device’s model timings…"
    }
    var isGenerating: Bool { generationControl != nil }
    var smoothingSelectionIssue: String? {
        if generationModel == .neodragon { return "Neodragon generates 24 FPS locally and does not use online smoothing." }
        if !support.enabled { return "Enable online support in Setup to add the free smoothing stage." }
        if duration != 2 || outputFraming != .square { return "24 FPS smoothing currently supports 2-second square videos. Choose those settings, or use 12 FPS offline." }
        return nil
    }

    init(root: URL? = nil, smoothingClient: RIFEClient? = nil, helperAccount: HFAccountModel? = nil) {
        let account = helperAccount ?? HFAccountModel()
        self.helperAccount = account
        self.smoothingClient = smoothingClient ?? RIFEClient(credentials: account.client)
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalFrames", isDirectory: true)
        library = VideoLibrary(root: support.appendingPathComponent("Library", isDirectory: true))
        let modelRoot = support.appendingPathComponent("Models", isDirectory: true)
        modelDirectory = modelRoot.appendingPathComponent("Installed", isDirectory: true)
        installer = ModelInstaller(root: modelRoot)
        let optionalRoot = support.appendingPathComponent("OptionalModels/Neodragon", isDirectory: true)
        neodragonDirectory = optionalRoot.appendingPathComponent("Installed", isDirectory: true)
        neodragonInstaller = NeodragonInstaller(root: optionalRoot)
        self.support = OnlineSupport(directory: support.appendingPathComponent("OnlineSupport", isDirectory: true))
        temporaryDirectory = support.appendingPathComponent("Temporary", isDirectory: true)
        benchmarkDirectory = support.appendingPathComponent("Benchmarks", isDirectory: true)
        resumeDirectory = support.appendingPathComponent("ResumableBaseline", isDirectory: true)
        preferencesURL = support.appendingPathComponent("creation-preferences.json")
        if let data = try? Data(contentsOf: preferencesURL),
           let preferences = try? JSONDecoder().decode(CreationPreferences.self, from: data) {
            visualStyle = preferences.style; outputFraming = preferences.framing
            useFixedSeed = preferences.useFixedSeed; generationSeed = preferences.seed
            recordCreationDiagnostics = preferences.recordDiagnostics ?? false
            smoothAfterGeneration = preferences.smoothAfterGeneration ?? false
            generationModel = preferences.model ?? .movd
            if generationModel == .neodragon { smoothAfterGeneration = false }
        }
        preferencesLoaded = true
        self.support.onDisable = { [weak self] in self?.closeSmoothingReview(); self?.helperAccount.cancel() }
    }

    private func saveCreationPreferences() {
        guard preferencesLoaded else { return }
        let preferences = CreationPreferences(style: visualStyle, framing: outputFraming,
                                              useFixedSeed: useFixedSeed, seed: generationSeed,
                                              recordDiagnostics: recordCreationDiagnostics,
                                              smoothAfterGeneration: smoothAfterGeneration, model: generationModel)
        do {
            try FileManager.default.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: preferencesURL, options: .atomic)
        } catch { notice = "Your selection is available for this session, but could not be remembered." }
    }

    func reuseSettings(_ video: VideoRecord) {
        guard !working, video.canReuseSettings else { return }
        generationModel = video.isNeodragon ? .neodragon : .movd
        prompt = video.prompt; duration = video.duration; visualStyle = video.style
        smoothAfterGeneration = video.smoothing != nil
        outputFraming = video.isCrop ? video.framing : (video.requestedFraming ?? .square)
        useFixedSeed = true; generationSeed = String(video.seed)
        selectedVideo = nil
        workflowReview = nil
        creationRequestID = UUID()
        notice = "Saved prompt, style, framing and seed restored. Review them before generating."
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            // Each generation owns its file. An interrupted previous session leaves only this directory to clean.
            if FileManager.default.fileExists(atPath: temporaryDirectory.path) { try FileManager.default.removeItem(at: temporaryDirectory) }
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            videos = try await library.list()
            if let data = try? Data(contentsOf: pendingSmoothingURL),
               let id = try? JSONDecoder().decode(UUID.self, from: data) {
                if !videos.contains(where: { $0.parentVideoID == id && $0.smoothing != nil }) {
                    pendingSmoothingVideo = videos.first { $0.id == id && SmoothingMedia.supports($0) }
                }
            }
            await helperAccount.restore()
            installed = await installer.isInstalled()
            neodragonInstalled = await neodragonInstaller.isInstalled()
            hasModelRollback = await installer.hasRollback()
            refreshBenchmarkFiles()
            refreshSavedBaseline()
        } catch { errorMessage = error.localizedDescription }
    }

    func generate() {
        if generationModel == .neodragon { beginNeodragonGeneration(); return }
        if smoothAfterGeneration, let issue = smoothingSelectionIssue { errorMessage = issue; return }
        if pendingSmoothingVideo != nil { errorMessage = "Finish the pending 24 FPS job or choose Keep 12 FPS before starting another job."; return }
        beginGeneration(benchmarking: false)
    }

    /// Called only after the genuine local generation has been saved. No upload or consent is persisted.
    func offerSmoothingForGeneratedVideo(_ video: VideoRecord) throws {
        guard SmoothingMedia.supports(video) else { throw SmoothingError.unsupported }
        try JSONEncoder().encode(video.id).write(to: pendingSmoothingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pendingSmoothingVideo = video
        if !working && inForeground && support.enabled { workflowReview = video }
    }

    func keepOriginalWithoutSmoothing() {
        guard !working else { return }
        try? FileManager.default.removeItem(at: pendingSmoothingURL)
        pendingSmoothingVideo = nil; workflowReview = nil
        notice = "Your 12 FPS original is saved in Library. You can request smoothing later."
    }

    func runBaselineBenchmark() {
        guard installed, !working else { return }
        generationModel = .movd
        prompt = Self.benchmarkPrompts[benchmarkPromptIndex]
        duration = 2
        beginGeneration(benchmarking: true)
    }

    func resumeBaseline() {
        guard let pendingBaseline, !working, installed else { return }
        generationModel = .movd
        prompt = pendingBaseline.request.prompt
        duration = pendingBaseline.request.duration
        benchmarkSeed = String(pendingBaseline.request.seed)
        beginGeneration(benchmarking: true, resuming: pendingBaseline)
    }

    private func checkpointURL(for job: BaselineJob) -> URL { resumeDirectory.appendingPathComponent(job.id.uuidString + ".checkpoint") }

    private func saveJob(_ job: BaselineJob) throws {
        try FileManager.default.createDirectory(at: resumeDirectory, withIntermediateDirectories: true)
        var directory = resumeDirectory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try JSONEncoder().encode(job).write(to: resumeDirectory.appendingPathComponent("pending.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        pendingBaseline = job
    }

    private func refreshSavedBaseline() {
        let url = resumeDirectory.appendingPathComponent("pending.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            pendingBaseline = nil; savedBaselineDescription = nil; return
        }
        do {
            let job = try JSONDecoder().decode(BaselineJob.self, from: Data(contentsOf: url))
            pendingBaseline = job
            let checkpoint = checkpointURL(for: job)
            if FileManager.default.fileExists(atPath: checkpoint.path) {
                let saved = try GenerationCheckpoint.summary(at: checkpoint)
                guard saved.request == job.request else { throw GenerationError.invalidCheckpoint }
                savedBaselineDescription = "Saved baseline: \(saved.completedSteps) of 21 motion steps completed. An unfinished step or video decoding may repeat after relaunch."
            } else { savedBaselineDescription = "Saved baseline request. Prompt encoding will restart because no motion-step checkpoint was saved yet." }
        } catch {
            savedBaselineDescription = "Saved baseline cannot be read. Discard it to start a new baseline."
        }
    }

    func discardSavedBaseline() {
        guard !working else { return }
        do { try clearSavedBaseline() } catch { errorMessage = error.localizedDescription }
    }

    private func clearSavedBaseline() throws {
        if FileManager.default.fileExists(atPath: resumeDirectory.path) { try FileManager.default.removeItem(at: resumeDirectory) }
        pendingBaseline = nil; savedBaselineDescription = nil
    }

    private func beginGeneration(benchmarking: Bool, resuming: BaselineJob? = nil) {
        support.cancel()
        guard installed, !working else { return }
        guard !benchmarking || pendingBaseline == nil || resuming != nil else { return }
        do {
            let seed: UInt64
            if benchmarking || useFixedSeed {
                guard let value = UInt64(benchmarking ? benchmarkSeed : generationSeed) else {
                    errorMessage = "Enter a whole-number seed from 0 to 18446744073709551615."
                    return
                }
                seed = value
            } else { seed = UInt64.random(in: 0...UInt64.max) }
            let request = try resuming?.request ?? GenerationRequest(prompt: prompt, duration: duration, seed: seed,
                                                                      style: benchmarking ? .default : visualStyle)
            let framing: OutputFraming = benchmarking ? .square : outputFraming
            let wantsSmoothing = !benchmarking && smoothAfterGeneration
            var job: BaselineJob? = benchmarking ? (resuming ?? BaselineJob(id: UUID(), request: request)) : nil
            let log = (benchmarking || recordCreationDiagnostics) ? try makeBenchmarkLog(kind: "generation", fields: [
                "prompt": request.prompt, "seed": String(request.seed), "durationSeconds": String(request.duration),
                "effectiveModelPrompt": request.effectivePrompt, "visualStyle": request.style.rawValue,
                "generationMode": GenerationMode.textToVideo.rawValue, "requestedFraming": framing.rawValue,
                "width": String(request.width), "height": String(request.height), "fps": String(request.framesPerSecond),
                "configuration": "baseline-fp32-stdit-vae-t5-int8-spatial-cpu",
                "decoderExecutionPolicy": MOVDModel.decoderExecutionPolicy,
                "profileID": GenerationProfile.baselineID, "precision": GenerationProfile.precision,
                "schedule": "30 points; leap index 20; 21 predictions; TDTM first 10; CFG 7; latent frames 20",
                "cacheCondition": "uncontrolled OS cache; record first/repeat run separately; process is not restarted automatically",
                "baselineJobID": job?.id.uuidString ?? "", "resumedFromJournal": resuming?.previousJournal ?? "",
                "checkpointPolicy": benchmarking ? "Exact Float32 state after each completed diffusion step; checkpoint I/O and pauses included in session wall time" : "Create job; no saved-baseline checkpoint; pauses included in session wall time"
            ]) : nil
            if var updated = job {
                updated.previousJournal = log?.url.lastPathComponent
                try saveJob(updated)
                job = updated
            }
            working = true
            generationWillSmooth = wantsSmoothing
            installing = false
            activeBenchmarkLog = log
            pausedForMemory = false
            pauseReason = nil
            notice = nil
            let control = GenerationControl { [weak self] reason in
                Task { @MainActor in
                    guard let self else { return }
                    self.pauseReason = reason
                    BackgroundGeneration.shared.report(self.progress, paused: reason == nil ? nil : self.progressMessage)
                }
            }
            control.setForeground(inForeground)
            generationControl = control
            progress = .init(0, "Preparing generation")
            let checkpoint = job.map { checkpointURL(for: $0) }
            BackgroundGeneration.shared.statusChanged = { [weak self] status in self?.backgroundStatus = status }
            BackgroundGeneration.shared.start(control: control, log: log, onExpiration: { [weak self] in
                self?.operation?.cancel()
                self?.notice = benchmarking ? "Background execution ended. Resume the saved baseline in Setup." : "Background execution ended. Open Local Frames to try generation again."
            }) { [self] in
              self.operation = Task { [self] in
                let output = self.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                var succeeded = false
                defer { try? FileManager.default.removeItem(at: output); self.finish(success: succeeded) }
                do {
                    let free = try self.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                    guard free > 1024 * 1024 * 1024 else { throw GenerationError.insufficientStorage }
                    let metrics = try await self.engine.generate(request, modelsAt: self.modelDirectory, output: output,
                                                            benchmark: log, control: control, checkpointURL: checkpoint,
                                                            timingHistoryURL: self.benchmarkDirectory.appendingPathComponent("timing-cache.data")) { progress in
                        Task { @MainActor in
                            self.progress = progress
                            BackgroundGeneration.shared.report(progress, paused: self.pauseReason == nil ? nil : self.progressMessage)
                        }
                    }
                    log?.record("engine_completed", fields: ["elapsedSeconds": String(metrics.elapsedSeconds)])
                    try Task.checkCancellation()
                    let item = try await self.library.add(temporaryURL: output, request: request, metrics: metrics, requestedFraming: framing)
                    self.videos = try await self.library.list()
                    if let log {
                        let videoURL = self.library.videoURL(item.id)
                        let asset = AVURLAsset(url: videoURL)
                        let videoDuration = try await asset.load(.duration).seconds
                        let tracks = try await asset.loadTracks(withMediaType: .video)
                        guard let track = tracks.first else { throw GenerationError.encodingFailed("No video track") }
                        let fps = try await track.load(.nominalFrameRate)
                        let size = try await track.load(.naturalSize)
                        guard abs(videoDuration - Double(request.duration)) < 0.05, abs(fps - Float(request.framesPerSecond)) < 0.1,
                              Int(size.width) == request.width, Int(size.height) == request.height else {
                            throw GenerationError.encodingFailed("Output dimensions, frame rate or duration differ from the generation request")
                        }
                        let artifact = log.url.deletingPathExtension().appendingPathExtension("mp4")
                        try FileManager.default.copyItem(at: videoURL, to: artifact)
                        try JSONEncoder().encode(item).write(to: log.url.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
                        try log.finish(status: "succeeded", fields: ["videoFile": artifact.lastPathComponent,
                            "videoSHA256": try ModelInstaller.sha256(artifact), "measuredDurationSeconds": String(videoDuration),
                            "measuredFPS": String(fps), "measuredWidth": String(Int(size.width)), "measuredHeight": String(Int(size.height)),
                            "visualQuality": "not assessed; inspect exported video"])
                    }
                    if benchmarking { try self.clearSavedBaseline() }
                    succeeded = true
                    var preview = item
                    if framing.isCrop {
                        do { preview = try await self.makeCrop(item, framing: framing) }
                        catch { self.notice = "The square video was saved. The crop did not finish; you can retry it from the video preview." }
                    }
                    if wantsSmoothing {
                        do { try self.offerSmoothingForGeneratedVideo(item) }
                        catch { self.notice = "Your original was saved. Open it in Library to request a 24 FPS copy."; self.selectedVideo = item }
                    } else { self.selectedVideo = preview }
                } catch is CancellationError {
                    try? log?.finish(status: "cancelled", fields: ["checkpointRetained": String(checkpoint != nil)])
                    self.notice = benchmarking ? "Baseline paused. Use Resume saved baseline to continue from the last saved motion step." : "Generation cancelled."
                } catch {
                    var fields = BenchmarkLog.diagnosticErrorFields(error)
                    fields["error"] = String(describing: error)
                    try? log?.finish(status: "failed", fields: fields)
                    self.errorMessage = error.localizedDescription
                }
              }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func makeCrop(_ video: VideoRecord, framing: OutputFraming) async throws -> VideoRecord {
        let output = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let started = ProcessInfo.processInfo.systemUptime
        progress = .init(0, "Saving \(framing.name) crop · square original preserved")
        try await VideoCropExporter.export(source: library.videoURL(video.id), destination: output, framing: framing) { value in
            Task { @MainActor in self.progress = .init(value, "Saving \(framing.name) crop · square original preserved") }
        }
        try Task.checkCancellation()
        let item = try await library.addCrop(temporaryURL: output, original: video, framing: framing,
                                            elapsedSeconds: ProcessInfo.processInfo.systemUptime - started)
        videos = try await library.list()
        return item
    }

    func exportCrop(_ video: VideoRecord, framing: OutputFraming) {
        guard !working, !video.isCrop, framing.isCrop else { return }
        working = true; exportingCrop = true; notice = nil
        operation = Task {
            defer { finish() }
            do { selectedVideo = try await makeCrop(video, framing: framing) }
            catch is CancellationError { notice = "Crop export cancelled. The original video is unchanged." }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func prepareSmoothing(_ video: VideoRecord) {
        guard support.enabled, !working else { return }
        closeSmoothingReview()
        smoothingResult = nil; smoothingMessage = nil
        working = true; smoothingActive = true
        progress = .init(0, "Preparing a local preview · nothing uploaded")
        operation = Task {
            defer { finish() }
            do {
                let prepared = try await SmoothingMedia.prepare(video, source: library.videoURL(video.id), temporaryRoot: temporaryDirectory)
                guard !Task.isCancelled, support.enabled else {
                    try? FileManager.default.removeItem(at: prepared.directory)
                    throw CancellationError()
                }
                smoothingPreview = prepared
            } catch is CancellationError { smoothingMessage = "Preview cancelled. Nothing was uploaded." }
            catch { smoothingMessage = (error as? SmoothingError)?.localizedDescription ?? "The local preview could not be prepared. Nothing was uploaded." }
        }
    }

    func startSmoothing(previewID: UUID, consent: Bool) {
        guard !working, support.enabled, consent, let prepared = smoothingPreview, prepared.id == previewID else { return }
        // Consume the reviewed snapshot immediately. Neither success nor failure can reuse its consent.
        smoothingPreview = nil; smoothingResult = nil; smoothingMessage = nil
        support.cancel(); working = true; smoothingActive = true
        progress = .init(0, "Starting 24 FPS smoothing")
        operation = Task {
            defer { try? FileManager.default.removeItem(at: prepared.directory); finish() }
            do {
                // The callback shares the operation's bounded lifetime; finish() releases the task.
                let result = try await smoothingClient.smooth(prepared, consentID: previewID, enabled: support.enabled) { text in
                    Task { @MainActor in
                        guard self.smoothingActive else { return }
                        self.progress = .init(0, text)
                    }
                }
                try Task.checkCancellation()
                guard support.enabled else { throw CancellationError() }
                let saved = try await library.addSmoothed(result, original: prepared.original)
                videos = try await library.list(); smoothingResult = saved
                if pendingSmoothingVideo?.id == prepared.original.id {
                    try? FileManager.default.removeItem(at: pendingSmoothingURL)
                    pendingSmoothingVideo = nil
                }
                smoothingMessage = "24 FPS copy saved. Your original 12 FPS video is unchanged."
            } catch is CancellationError {
                smoothingMessage = "Smoothing cancelled. Your original is safe. The helper may already have received or processed the clip; cancellation does not delete its remote copy."
            } catch {
                if Task.isCancelled {
                    smoothingMessage = "Smoothing stopped. Your original is safe. The helper may already have received the clip. Nothing will retry automatically."
                } else { smoothingMessage = (error as? HFAccountError)?.localizedDescription ?? (error as? SmoothingError)?.localizedDescription ?? SmoothingError.unavailable.localizedDescription }
            }
            if support.enabled && inForeground && !Task.isCancelled { helperAccount.refreshQuota(enabled: true) }
        }
    }

    func closeSmoothingReview() {
        if smoothingActive { operation?.cancel() }
        if let preview = smoothingPreview { try? FileManager.default.removeItem(at: preview.directory) }
        smoothingPreview = nil
    }

    func install() {
        guard !working else { return }
        support.cancel()
        do {
            let manifest = try support.installationManifest ?? ModelManifest.bundled()
            let log = try makeBenchmarkLog(kind: "installation", fields: ["expectedDownloadBytes": String(manifest.archives.reduce(Int64(0)) { $0 + $1.bytes })])
            working = true
            installing = true
            installationStage = .preparing
            activeBenchmarkLog = log
            pausedForMemory = false
            notice = nil
            progress = .init(0, "Preparing model download")
            operation = Task {
                defer { finish() }
                do {
                    try await installer.install(manifest, benchmark: log, stage: { stage in
                        Task { @MainActor in self.installationStage = stage }
                    }) { progress in
                        Task { @MainActor in self.progress = progress }
                    }
                    installed = await installer.isInstalled()
                    hasModelRollback = await installer.hasRollback()
                    try log.finish(status: installed ? "succeeded" : "failed")
                } catch is CancellationError {
                    try? log.finish(status: "cancelled")
                    notice = pausedForMemory
                        ? "Model preparation paused after iOS reported memory pressure. Completed downloads are kept. Tap Install to retry preparation."
                        : "Installation paused. Tap Install to resume available downloads."
                } catch {
                    var fields = BenchmarkLog.diagnosticErrorFields(error, phase: "compile")
                    fields["error"] = String(describing: error)
                    try? log.finish(status: "failed", fields: fields)
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeModel() async {
        guard !working else { return }
        do { try await installer.remove(); installed = false; hasModelRollback = false }
        catch { errorMessage = error.localizedDescription }
    }

    func restoreModelRollback() async {
        guard !working else { return }
        support.cancel(); working = true
        defer { working = false }
        do {
            try await installer.restoreRollback()
            installed = await installer.isInstalled(); hasModelRollback = await installer.hasRollback()
            notice = "The previous verified model was restored. Your videos are unchanged."
        } catch { errorMessage = error.localizedDescription }
    }

    func cancel() {
        if let operation { operation.cancel() }
        else if working {
            try? activeBenchmarkLog?.finish(status: "cancelled", fields: ["reason": "Cancelled before background task launch"])
            finish()
        }
    }

    func sceneChanged(_ phase: ScenePhase) {
        guard phase != .inactive else { return }
        inForeground = phase == .active
        if !inForeground { support.cancel(); helperAccount.cancelQuotaRefresh() }
        generationControl?.setForeground(inForeground)
        activeBenchmarkLog?.record("scene_changed", fields: ["state": inForeground ? "foreground" : "background"])
        if !inForeground, working, generationControl == nil {
            operation?.cancel()
            notice = "Work paused while the app was in the background. Completed videos are kept."
        }
    }

    private func finish(success: Bool = false) {
        let reviewAfterGeneration = generationWillSmooth && success
        BackgroundGeneration.shared.finish(success: success)
        working = false; installing = false; installingNeodragon = false; exportingCrop = false; smoothingActive = false; operation = nil; activeBenchmarkLog = nil; generationControl = nil; pauseReason = nil
        generationWillSmooth = false
        refreshBenchmarkFiles(); refreshSavedBaseline()
        if reviewAfterGeneration && inForeground && support.enabled { workflowReview = pendingSmoothingVideo }
    }

    func handleMemoryWarning() {
        activeBenchmarkLog?.record("memory_warning", fields: ["activity": installing ? "installation" : "generation", "installationStage": installationStage.rawValue])
        guard working else { return }
        if installing {
            if installationStage.shouldPauseForMemoryWarning {
                pausedForMemory = true
                cancel()
                notice = "Model preparation is pausing after iOS reported memory pressure. Completed downloads will be kept."
            } else {
                // Network download and checksum verification use bounded buffers.
                // A system warning alone is not a reason to discard or restart these stages.
                notice = "iOS reported low memory. Installation is continuing."
            }
        } else {
            cancel()
            errorMessage = "Work stopped after iOS reported memory pressure."
                + (activeBenchmarkLog == nil ? "" : " The diagnostic log is retained.")
        }
    }

    private func makeBenchmarkLog(kind: String, fields: [String: String] = [:]) throws -> BenchmarkLog {
        var metadata = fields
        metadata["appVersion"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        metadata["appBuild"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        metadata["memoryLimitRequest"] = "increased-memory-limit entitlement requested; OS-dependent; inspect availableProcessMemoryBytes"
        if let revision = Bundle.main.url(forResource: "build-revision", withExtension: "txt") {
            metadata["sourceRevision"] = try String(contentsOf: revision, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if metadata["manifestSHA256"] == nil, let manifest = Bundle.main.url(forResource: "model-manifest", withExtension: "json") {
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
            activeBenchmarkLog = log
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
            if pendingSmoothingVideo?.id == video.id {
                try? FileManager.default.removeItem(at: pendingSmoothingURL)
                pendingSmoothingVideo = nil; workflowReview = nil
            }
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

extension AppModel {
    func installNeodragon() {
        guard !working, let manifest = neodragonManifest else { return }
        do {
            let log = try makeBenchmarkLog(kind: "installation", fields: ["modelID": manifest.modelID,
                "modelRevision": manifest.weightsRevision, "modelVersion": manifest.modelVersion,
                "expectedPartitions": manifest.archives.flatMap(\.models).joined(separator: ","),
                "manifestSHA256": try optionalManifestHash()])
            support.cancel(); working = true; installing = true; installingNeodragon = true
            installationStage = .preparing; activeBenchmarkLog = log; pausedForMemory = false
            notice = nil; progress = .init(0, "Preparing optional Neodragon installation")
            operation = Task {
                defer { finish() }
                do {
                    try await neodragonInstaller.install(manifest, benchmark: log, stage: { stage in
                        Task { @MainActor in self.installationStage = stage }
                    }) { progress in Task { @MainActor in self.progress = progress } }
                    neodragonInstalled = await neodragonInstaller.isInstalled()
                    try log.finish(status: neodragonInstalled ? "succeeded" : "failed")
                    if neodragonInstalled {
                        generationModel = .neodragon; duration = 2
                        notice = "Neodragon is installed separately. Start with a 2-second test; device performance and longer-video quality are experimental."
                    }
                } catch is CancellationError {
                    try? log.finish(status: "cancelled")
                    notice = "Neodragon installation paused. Completed downloads are kept; local model preparation may repeat when resumed."
                } catch {
                    try? log.finish(status: "failed", fields: BenchmarkLog.diagnosticErrorFields(error, phase: "compile"))
                    errorMessage = error.localizedDescription
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeNeodragon() async {
        guard !working else { return }
        do {
            try await neodragonInstaller.remove()
            neodragonInstalled = false
            if generationModel == .neodragon { generationModel = .movd }
        } catch { errorMessage = error.localizedDescription }
    }

    private func optionalManifestHash() throws -> String {
        guard let url = Bundle.main.url(forResource: "neodragon-manifest", withExtension: "json") else {
            throw GenerationError.modelMissing("Neodragon download manifest")
        }
        return try ModelInstaller.sha256(url)
    }

    private func beginNeodragonGeneration() {
        guard neodragonInstalled, !working else { return }
        guard pendingSmoothingVideo == nil else {
            errorMessage = "Finish the pending smoothing job or keep its original before starting another generation."
            return
        }
        do {
            let seed: UInt64
            if useFixedSeed {
                guard let value = UInt64(generationSeed) else {
                    errorMessage = "Enter a whole-number seed from 0 to 18446744073709551615."; return
                }
                seed = value
            } else { seed = UInt64.random(in: 0...UInt64.max) }
            let request = try NeodragonGenerationRequest(prompt: prompt, duration: duration, seed: seed, style: visualStyle)
            let installation = try NeodragonEngine.validateInstallation(at: neodragonDirectory)
            let geometry = try NeodragonModel.geometry(seconds: duration)
            let motionComputePolicy = NeodragonMotionComputePolicy.cpuCompatibility
            // The optional port always keeps local evidence while device validation
            // is in progress. Diagnostics remain subject to separate upload consent.
            let log = try makeBenchmarkLog(kind: "generation", fields: ["modelID": NeodragonModel.identifier,
                "modelRevision": NeodragonModel.weightsRevision, "manifestSHA256": try optionalManifestHash(),
                "prompt": request.prompt, "effectiveModelPrompt": request.effectivePrompt, "visualStyle": request.style.rawValue,
                "seed": String(seed), "durationSeconds": String(request.duration), "width": "512", "height": "320", "fps": "24",
                "generationMode": GenerationMode.textToVideo.rawValue, "requestedFraming": "native-16:10",
                "profileID": motionComputePolicy.profileID, "precision": "Mixed FP16/FP32; T5 Float32",
                "motionComputePolicy": motionComputePolicy.rawValue,
                "configuration": "Neodragon CPU motion compatibility · mixed precision · native 24 FPS",
                "expectedPartitions": installation.modelNames.joined(separator: ","),
                "expectedEvaluations": String(4 + (geometry.latentFrames - 1) * 3),
                "schedule": "SSD-1B LCM 4 steps, then 3 flow evaluations per subsequent latent unit",
                "checkpointPolicy": "Cooling retains in-memory state; interruption ends this experimental job",
                "cacheCondition": "uncontrolled OS cache; four tiny decoder models retained within the job"])
            support.cancel(); working = true; activeBenchmarkLog = log
            installing = false; generationWillSmooth = false; pausedForMemory = false; pauseReason = nil; notice = nil
            let control = GenerationControl { [weak self] reason in
                Task { @MainActor in
                    guard let self else { return }
                    self.pauseReason = reason
                    BackgroundGeneration.shared.report(self.progress, paused: reason == nil ? nil : self.progressMessage)
                }
            }
            generationControl = control; control.setForeground(inForeground)
            progress = .init(0, "Preparing Neodragon generation")
            BackgroundGeneration.shared.statusChanged = { [weak self] status in self?.backgroundStatus = status }
            BackgroundGeneration.shared.start(control: control, log: log, onExpiration: { [weak self] in
                self?.operation?.cancel()
                self?.notice = "Background execution ended. Neodragon has no saved-job recovery yet; open the app to start another test."
            }) { [self] in
                self.operation = Task { [self] in
                    var succeeded = false
                    let output = self.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                    defer { try? FileManager.default.removeItem(at: output); self.finish(success: succeeded) }
                    do {
                        let metrics = try await self.neodragonEngine.generate(request, modelsAt: self.neodragonDirectory, output: output,
                                                                       benchmark: log, control: control,
                                                                       motionComputePolicy: motionComputePolicy) { progress in
                            Task { @MainActor in
                                self.progress = progress
                                BackgroundGeneration.shared.report(progress, paused: self.pauseReason == nil ? nil : self.progressMessage)
                            }
                        }
                        try Task.checkCancellation()
                        let item = try await self.library.addNeodragon(temporaryURL: output, request: request, metrics: metrics)
                        self.videos = try await self.library.list(); self.selectedVideo = item
                        try log.finish(status: "succeeded", fields: ["videoID": item.id.uuidString])
                        succeeded = true
                    } catch is CancellationError {
                        try? log.finish(status: "cancelled")
                        self.notice = "Neodragon generation cancelled. The local diagnostic journal is retained."
                    } catch {
                        var fields = BenchmarkLog.diagnosticErrorFields(error)
                        fields["error"] = String(describing: error)
                        try? log.finish(status: "failed", fields: fields)
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
