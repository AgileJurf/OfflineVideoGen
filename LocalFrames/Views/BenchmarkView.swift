import AVKit
import SwiftUI
import VideoEngine

struct BenchmarkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessions: [BenchmarkSummary] = []
    @State private var failure: String?
    var body: some View {
        List {
            Section("Reference configuration") {
                LabeledContent("Model", value: "MOVD · " + String(MOVDModel.revision.prefix(8)))
                LabeledContent("Precision", value: GenerationProfile.precision)
                LabeledContent("Preset", value: "Baseline")
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preset: Baseline")
                    .accessibilityIdentifier("benchmarkBaselinePreset")
                LabeledContent("Sampler", value: "Rectified flow · 30-point schedule")
                LabeledContent("Diffusion evaluations", value: "21 · final leap at index 20")
                LabeledContent("Guidance", value: "7 · conditional/unconditional batch")
                LabeledContent("Output", value: "256 × 256 · 12 FPS")
                Text("The reference keeps the original weights and generation settings. Test one change at a time using the same prompt and seed.").font(.caption)
            }
            Section("Optimization presets") {
                ForEach(GenerationProfile.pendingPresets, id: \.self) { name in
                    LabeledContent(name, value: "Awaiting device comparisons").foregroundStyle(.secondary)
                }
                Text("Presets become selectable after matched on-device timing and quality tests. No experimental precision or sampler is selected automatically.").font(.caption)
            }
            Section("Reproducible runs") {
                Text("Use Setup’s Sailboat, Flag, and Rolling ball prompts. Start with seed 42 and repeat each case three times; then test seeds 123 and 2026. Keep output duration at 2 seconds.")
                Text("Record charging, Low Power Mode, starting thermal state, and whether this is the first run after launch. Cool the phone before each comparison. A resumed session measures only the remaining work.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Compare saved outputs") { VideoComparisonView() }
                    .disabled(model.videos.count < 2).accessibilityIdentifier("compareBenchmarkVideos")
            }
            Section("Local sessions · latest 50") {
                if let failure { Text(failure).foregroundStyle(.orange) }
                if sessions.isEmpty { Text("Run a baseline in Setup to record model timings and failures.").foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    NavigationLink {
                        BenchmarkSessionView(session: session)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(session.kind.capitalized) · \(session.status)")
                            Text("Build \(session.appBuild) · \(session.sessionLabel) · \(session.elapsedSeconds, specifier: "%.1f") s").font(.caption)
                            Text(session.id).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle("Benchmarks")
            .task { await reload() }
            .refreshable { await reload() }
    }
    @MainActor private func reload() async {
        guard !model.working else { failure = "Measurements are being recorded. Refresh after the run finishes."; return }
        let directory = model.benchmarkDirectory
        do { sessions = try await Task.detached(priority: .utility) { try BenchmarkSummary.list(in: directory) }.value; failure = nil }
        catch { failure = "A local journal could not be read: " + error.localizedDescription }
    }
}

private struct BenchmarkSessionView: View {
    let session: BenchmarkSummary
    var body: some View {
        List {
            Section("Run") {
                LabeledContent("Status", value: session.status)
                LabeledContent("Model", value: session.modelRevision)
                LabeledContent("Configuration", value: session.configuration)
                LabeledContent("Seed", value: session.seed)
                Text(session.prompt)
                LabeledContent("Style", value: session.style)
                if session.effectivePrompt != session.prompt {
                    DisclosureGroup("Effective model prompt") { Text(session.effectivePrompt).font(.caption).textSelection(.enabled) }
                }
                LabeledContent(session.sessionLabel + " time", value: String(format: "%.2f s", session.elapsedSeconds))
                LabeledContent("Model loading", value: String(format: "%.2f s", session.totalLoadSeconds))
                LabeledContent("Model predictions", value: String(format: "%.2f s", session.totalPredictionSeconds))
                LabeledContent("Peak sampled memory", value: ByteCountFormatter.string(fromByteCount: Int64(session.peakMemoryBytes), countStyle: .memory))
                LabeledContent("Thermal states", value: session.thermalStates.sorted().joined(separator: ", "))
                LabeledContent("Memory warnings", value: String(session.memoryWarnings))
                LabeledContent("Completed diffusion evaluations", value: "\(session.completedSteps)/21")
                LabeledContent("Restored evaluations", value: String(session.restoredSteps))
                LabeledContent("New diffusion evaluations", value: String(max(0, session.completedSteps - session.restoredSteps)))
                LabeledContent("Requested output", value: "\(session.width) × \(session.height) · \(session.fps) FPS")
                if session.restoredSteps > 0 { Text("This time is not the total generation time. Keep all linked journals when comparing a resumed job.").foregroundStyle(.orange) }
                Text("Memory is sampled, not a continuous peak. Model timing excludes some app work. Requested compute units do not establish GPU or Neural Engine utilization.").font(.caption).foregroundStyle(.secondary)
                if session.hasIncompleteLines { Text("Journal has an incomplete line or sequence gap; interpret these measurements with care.").foregroundStyle(.orange) }
                if let operation = session.lastOperation { LabeledContent("Unfinished operation", value: operation) }
                if let failure = session.failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section("Partitions · slowest total first") {
                ForEach(session.partitions) { part in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(part.name).font(.caption.monospaced())
                        Text("Load \(part.loadSeconds, specifier: "%.2f") s (\(part.loads)) · Predict \(part.predictionSeconds, specifier: "%.2f") s (\(part.predictions))").font(.caption)
                        if part.failures > 0 { Text("\(part.failures) failed operations").font(.caption).foregroundStyle(.red) }
                    }
                }
            }
        }.navigationTitle("Session details")
    }
}

struct VideoComparisonView: View {
    @EnvironmentObject private var model: AppModel
    @State private var leftID: UUID?
    @State private var rightID: UUID?
    @State private var leftPlayer: AVPlayer?
    @State private var rightPlayer: AVPlayer?
    private var left: VideoRecord? { model.videos.first { $0.id == leftID } }
    private var right: VideoRecord? { model.videos.first { $0.id == rightID } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                selection("Reference", value: $leftID)
                selection("Comparison", value: $rightID)
                HStack(spacing: 8) {
                    VideoPlayer(player: leftPlayer).aspectRatio(1, contentMode: .fit)
                    VideoPlayer(player: rightPlayer).aspectRatio(1, contentMode: .fit)
                }
                HStack {
                    Button("Play together", systemImage: "play.fill") { Task { await replay() } }
                    Spacer()
                    Button("Pause", systemImage: "pause.fill") { leftPlayer?.pause(); rightPlayer?.pause() }
                }.buttonStyle(.bordered)
                if let left, let right {
                    if left.effectivePrompt != right.effectivePrompt || left.seed != right.seed || left.duration != right.duration {
                        Text("Model prompts, styles, seeds, or duration differ. This can be a style comparison, but it is not a matched inference-performance comparison.").foregroundStyle(.orange)
                    }
                    if left.isCrop || right.isCrop {
                        Text("A cropped copy reuses its original’s generation measurements. Crop export does not run a new diffusion job.").foregroundStyle(.orange)
                    }
                    if (left.metrics.resumedFromStep ?? 0) > 0 || (right.metrics.resumedFromStep ?? 0) > 0 {
                        Text("At least one output was resumed. Its session duration is not a full generation time.").foregroundStyle(.orange)
                    }
                    HStack(alignment: .top, spacing: 16) { details(left, label: "Reference"); details(right, label: "Comparison") }
                }
                Text("Inspect motion, subject identity, background stability, prompt adherence and flicker. Lower frame differences alone do not indicate better quality; a frozen video can score well on that measure.").font(.footnote).foregroundStyle(.secondary)
                Text("Playback comparison leaves both original videos intact. Export each from its Library preview.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Compare outputs")
            .task { leftID = model.videos.last?.id; rightID = model.videos.first?.id; loadPlayers() }
            .onChange(of: leftID) { loadPlayers() }
            .onChange(of: rightID) { loadPlayers() }
            .onDisappear { leftPlayer?.pause(); rightPlayer?.pause() }
    }
    private func selection(_ title: String, value: Binding<UUID?>) -> some View {
        Picker(title, selection: value) {
            Text("Choose video").tag(nil as UUID?)
            ForEach(model.videos) { video in
                Text("\(video.prompt.prefix(28)) · seed \(video.seed) · \(video.id.uuidString.prefix(6))").tag(Optional(video.id))
            }
        }
    }
    private func details(_ video: VideoRecord, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.headline)
            Text(video.prompt)
            Text("Style: " + video.style.name)
            Text(video.isCrop ? "Center-cropped copy" : "Native square output")
            Text("Seed \(video.seed)")
            Text(video.metrics.profileID ?? "Earlier baseline")
            Text(video.metrics.precision ?? "Original model precision")
            Text("Session: \(video.metrics.elapsedSeconds, specifier: "%.2f") s")
            Text("Peak sampled: " + ByteCountFormatter.string(fromByteCount: Int64(video.metrics.peakSampledMemoryBytes), countStyle: .memory))
            Text("Thermal: " + video.metrics.thermalStates.joined(separator: ", "))
            Text("\(video.width) × \(video.height) · \(video.framesPerSecond) FPS")
            if let loads = video.metrics.modelLoadSeconds { Text("Load: \(loads, specifier: "%.2f") s") }
            if let steps = video.metrics.diffusionEvaluations { Text("Evaluations this session: \(steps)") }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func loadPlayers() {
        leftPlayer?.pause(); rightPlayer?.pause()
        leftPlayer = left.map { AVPlayer(url: model.library.videoURL($0.id)) }
        rightPlayer = right.map { AVPlayer(url: model.library.videoURL($0.id)) }
    }
    @MainActor private func replay() async {
        guard let leftPlayer, let rightPlayer else { return }
        leftPlayer.pause(); rightPlayer.pause()
        await leftPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        await rightPlayer.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        let start = CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()), CMTime(seconds: 0.2, preferredTimescale: 600))
        leftPlayer.setRate(1, time: .zero, atHostTime: start)
        rightPlayer.setRate(1, time: .zero, atHostTime: start)
    }
}
