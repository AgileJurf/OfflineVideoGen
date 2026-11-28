import AVKit
import Charts
import SwiftUI
import VideoEngine

struct BenchmarkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sessions: [BenchmarkSummary] = []
    @State private var failure: String?
    private var generations: [BenchmarkSummary] { sessions.filter { $0.kind == "generation" } }
    var body: some View {
        List {
            Section("Frame Lab") {
                LabeledContent("Active model", value: "Neodragon")
                LabeledContent("Backend", value: "Core ML · CPU motion compatibility")
                LabeledContent("Precision", value: "Mixed FP16/FP32; T5 FP32")
                LabeledContent("Preset", value: model.inferenceProfileName).accessibilityIdentifier("benchmarkBaselinePreset")
                LabeledContent("Two-second schedule", value: "4 image + 18 motion evaluations")
                LabeledContent("Native output", value: "512 × 320 · 24 FPS")
                Text("Fast, Balanced and Cinema presets require matched on-device comparisons. GPU/Neural Engine utilization is unavailable without device profiling; requested compute units are not utilization measurements.").font(.caption).foregroundStyle(.secondary)
                NavigationLink("Run a reproducible baseline") { DeviceBenchmarkToolsView() }.accessibilityIdentifier("openBenchmarkTools")
                NavigationLink("Compare saved outputs") { VideoComparisonView() }.disabled(model.videos.count < 2)
            }
            ExportFilesSection()
            if !generations.isEmpty {
                Section("Recorded generation sessions") {
                    LabeledContent("Succeeded / recorded", value: "\(generations.filter { $0.status == "succeeded" }.count) / \(generations.count)")
                    Chart(generations.prefix(10)) { session in
                        BarMark(x: .value("Session", String(session.id.prefix(18))), y: .value("Seconds", session.elapsedSeconds))
                            .foregroundStyle(session.status == "succeeded" ? StudioTheme.accent : Color.secondary)
                    }.chartXAxis(.hidden).frame(height: 150).accessibilityLabel("Wall time for up to ten recorded sessions")
                    Text("Wall time includes pauses. Interrupted and resumed sessions are shown separately and are not full-generation speed comparisons.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Local sessions · latest 50") {
                if let failure { Text(failure).foregroundStyle(.orange) }
                if sessions.isEmpty { Text("No measurements yet. Run a generation or baseline on your device.").foregroundStyle(.secondary) }
                ForEach(sessions) { session in
                    NavigationLink { BenchmarkSessionView(session: session) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(session.kind.capitalized) · \(session.status)")
                            Text("Build \(session.appBuild) · \(session.sessionLabel) · \(session.elapsedSeconds, specifier: "%.1f") s").font(.caption)
                            Text(session.configuration).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.studioBackground().navigationTitle("Frame Lab").task { await reload() }.refreshable { await reload() }
    }
    @MainActor private func reload() async {
        guard !model.working else { failure = "Measurements are being recorded. Refresh when the run finishes."; return }
        let directory = model.benchmarkDirectory
        do {
            if FileManager.default.fileExists(atPath: directory.path) { sessions = try await Task.detached(priority: .utility) { try BenchmarkSummary.list(in: directory) }.value }
            failure = nil
        } catch { failure = "A local journal could not be read: " + error.localizedDescription }
    }
}

struct DeviceBenchmarkToolsView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var focused: Bool
    var body: some View {
        Form {
            Section("Reproducible baseline") {
                Text("Uses the working Neodragon weights and schedule, Default style and a two-second output. Keep charging, Low Power Mode, cache condition and starting thermal state consistent between runs.").font(.subheadline)
                Picker("Scene", selection: $model.benchmarkPromptIndex) {
                    ForEach(AppModel.benchmarkPrompts.indices, id: \.self) { Text(AppModel.benchmarkPrompts[$0]).tag($0) }
                }
                TextField("Seed", text: $model.benchmarkSeed).keyboardType(.numberPad).focused($focused).accessibilityIdentifier("benchmarkSeed")
                Button("Run 2-second baseline", systemImage: "play.circle") { focused = false; model.runBaselineBenchmark() }
                    .disabled(!model.installed || model.working || model.exportingFiles || UInt64(model.benchmarkSeed) == nil).accessibilityIdentifier("runBaselineBenchmark")
                Text("Prompt, seed, model load/prediction times, sampled process memory and thermal state are recorded locally. Export only when you choose.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Five-second memory trial") {
                Text("First run the two-second baseline above, then its two-second attention comparison with the same scene and seed. Compare the outputs before trying five seconds. Detail conditioning is off for these memory tests.").font(.subheadline)
                if model.attentionTrialInstalled {
                    Button("Run 2-second attention comparison", systemImage: "play.circle") { focused = false; model.runAttentionBenchmark(seconds: 2) }
                        .accessibilityIdentifier("runAttentionComparison")
                    Button("Run 5-second attention trial", systemImage: "play.circle") { focused = false; model.runAttentionBenchmark(seconds: 5) }
                        .accessibilityIdentifier("runFiveSecondTrial")
                    Text("This candidate keeps every attention token and all trained weights. Actual five-second completion and memory use still require the iPhone test.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Install the optional update in Models to run these comparisons.").foregroundStyle(.secondary)
                }
            }.disabled(!model.installed || model.working || model.exportingFiles || UInt64(model.benchmarkSeed) == nil)
            if model.working { Section { GenerationJobCard(log: model.jobLog) } }
            ExportFilesSection()
        }.studioBackground().navigationTitle("Baseline test").scrollDismissesKeyboard(.immediately)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { focused = false }.accessibilityIdentifier("dismissKeyboard") } }
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
                LabeledContent("Completed diffusion evaluations", value: "\(session.completedSteps)/\(session.expectedEvaluations)")
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
        }.studioBackground().navigationTitle("Session details")
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
                    VideoPlayer(player: leftPlayer).aspectRatio(CGFloat(left?.width ?? 16) / CGFloat(max(1, left?.height ?? 10)), contentMode: .fit)
                    VideoPlayer(player: rightPlayer).aspectRatio(CGFloat(right?.width ?? 16) / CGFloat(max(1, right?.height ?? 10)), contentMode: .fit)
                }
                HStack {
                    Button("Play together", systemImage: "play.fill") { Task { await replay() } }
                    Spacer()
                    Button("Pause", systemImage: "pause.fill") { leftPlayer?.pause(); rightPlayer?.pause() }
                }.buttonStyle(.bordered).disabled(model.working)
                if let left, let right {
                    if left.effectivePrompt != right.effectivePrompt || left.seed != right.seed || left.duration != right.duration {
                        Text("Model prompts, styles, seeds, or duration differ. This can be a style comparison, but it is not a matched inference-performance comparison.").foregroundStyle(.orange)
                    }
                    if left.isCrop || right.isCrop {
                        Text("A cropped copy reuses its original’s generation measurements. Crop export does not run a new diffusion job.").foregroundStyle(.orange)
                    }
                    if left.smoothing != nil || right.smoothing != nil {
                        Text("An interpolated copy reuses its original’s diffusion measurements. Smoothing time includes transfer and queueing; it is not a faster generation measurement.").foregroundStyle(.orange)
                    }
                    if (left.metrics.resumedFromStep ?? 0) > 0 || (right.metrics.resumedFromStep ?? 0) > 0 {
                        Text("At least one output was resumed. Its session duration is not a full generation time.").foregroundStyle(.orange)
                    }
                    HStack(alignment: .top, spacing: 16) { details(left, label: "Reference"); details(right, label: "Comparison") }
                }
                Text("Inspect motion, subject identity, background stability, prompt adherence and flicker. Lower frame differences alone do not indicate better quality; a frozen video can score well on that measure.").font(.footnote).foregroundStyle(.secondary)
                Text("Playback comparison leaves both original videos intact. Export each from its Library preview.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }.studioBackground().navigationTitle("Compare outputs")
            .task { leftID = model.videos.last?.id; rightID = model.videos.first?.id; loadPlayers() }
            .onChange(of: leftID) { loadPlayers() }
            .onChange(of: rightID) { loadPlayers() }
            .onChange(of: model.working) { if model.working { leftPlayer?.pause(); rightPlayer?.pause() } }
            .onDisappear { leftPlayer?.pause(); rightPlayer?.pause() }
    }
    private func selection(_ title: String, value: Binding<UUID?>) -> some View {
        Picker(title, selection: value) {
            Text("Choose video").tag(nil as UUID?)
            ForEach(model.videos) { video in
                Text("\(video.prompt.prefix(28)) · \(video.framesPerSecond) FPS · seed \(video.seed) · \(video.id.uuidString.prefix(6))").tag(Optional(video.id))
            }
        }
    }
    private func details(_ video: VideoRecord, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.headline)
            Text(video.prompt)
            Text("Style: " + video.styleName)
            Text("Reference detail prompt: " + ((video.upstreamDetailPrompt ?? false) ? "On" : "Off"))
            Text(video.isCrop ? "Center-cropped copy" : (video.smoothing == nil ? video.framingName + " output" : "RIFE interpolated copy"))
            if let smoothing = video.smoothing { Text("Smoothing + transfer: \(smoothing.elapsedSeconds, specifier: "%.2f") s") }
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
