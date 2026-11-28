import AVKit
import SwiftUI
import VideoEngine

struct PreviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let video: VideoRecord
    @State private var player: AVPlayer?
    @State private var details = false
    @State private var share: SharedFiles?
    @State private var deleting = false
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea(edges: .horizontal)
                .simultaneousGesture(TapGesture().onEnded { revealControls() })
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.studioButton().accessibilityLabel("Close video")
                    Spacer()
                    Text("\(video.duration)s · \(video.framesPerSecond) FPS").font(.caption.monospacedDigit()).padding(12).studioGlass(radius: 22)
                }.padding(.horizontal, 16).padding(.top, 12)
                Spacer()
                StudioGlassGroup {
                    HStack(spacing: 14) {
                        Button { player?.seek(to: .zero); player?.play(); revealControls() } label: { Image(systemName: "arrow.counterclockwise").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Replay video")
                        Button { details = true; player?.pause(); revealControls() } label: { Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Generation details")
                        Spacer()
                        Button { Task { player?.pause(); let urls = await model.exportVideo(video); if !urls.isEmpty { share = .init(urls: urls) } } } label: {
                            Label("Export", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                        }.disabled(model.exportingFiles).accessibilityIdentifier("exportVideo")
                        Menu {
                            Button("Save to Photos", systemImage: "photo.badge.arrow.down") { Task { await model.saveToPhotos(video) } }
                            if video.canReuseSettings { Button("Reuse settings", systemImage: "arrow.clockwise") { model.reuseSettings(video); dismiss() }.disabled(model.working) }
                            Button("Delete video", systemImage: "trash", role: .destructive) { deleting = true }.disabled(model.working)
                        } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Video actions")
                    }.padding(.horizontal, 16).padding(.vertical, 6).studioGlass(radius: 26)
                }.padding(.horizontal, 16).padding(.bottom, 14)
            }.opacity(controls || voiceOver ? 1 : 0).allowsHitTesting(controls || voiceOver)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controls)
        }.preferredColorScheme(.dark)
            .task(id: video.id) { player?.pause(); player = AVPlayer(url: model.library.videoURL(video.id)); revealControls() }
            .onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); hideTask?.cancel() }
            .onChange(of: scenePhase) { if scenePhase != .active { player?.pause(); controls = true } }
            .onChange(of: model.working) { if model.working { player?.pause() } }
            .sheet(isPresented: $details) { VideoDetailsView(video: video) }
            .sheet(item: $share) { ActivityShareSheet(urls: $0.urls) }
            .confirmationDialog("Delete this video from Library? Exported copies remain in Files and Photos.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { Task { await model.delete(video); dismiss() } }
            }
    }
    private func revealControls() {
        controls = true; hideTask?.cancel()
        guard !voiceOver else { return }
        hideTask = Task {
            do { try await Task.sleep(for: .seconds(5)); if player?.rate != 0 && !details && share == nil { controls = false } } catch { }
        }
    }
}
struct VideoDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let video: VideoRecord
    var body: some View {
        NavigationStack {
            List {
                Section("Scene") { Text(video.prompt).textSelection(.enabled) }
                Section("Generation") {
                    LabeledContent("Engine", value: video.isNeodragon ? "Neodragon" : "Earlier generation engine")
                    LabeledContent("Model version", value: video.metrics.modelRevision)
                    LabeledContent("Native / saved resolution", value: "\(video.width) × \(video.height)")
                    LabeledContent("Saved frame rate", value: "\(video.framesPerSecond) FPS")
                    LabeledContent("Duration", value: "\(video.duration) seconds")
                    LabeledContent("Seed", value: String(video.seed))
                    LabeledContent("Style", value: video.styleName)
                    LabeledContent("Session time", value: String(format: "%.1f seconds", video.metrics.elapsedSeconds))
                    LabeledContent("Peak sampled memory", value: ByteCountFormatter.string(fromByteCount: Int64(video.metrics.peakSampledMemoryBytes), countStyle: .memory))
                    Text(video.createdAt.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                }
                Section("Provenance") {
                    if video.smoothing != nil { Text("Previously interpolated copy. Its original remains a separate library item. The former online helper has been retired.") }
                    else if video.isCrop { Text("Center-cropped copy. Its dimensions describe the export, not native model generation.") }
                    else { Text("Original generated video. No interpolation or upscale is recorded.") }
                    if (video.metrics.resumedFromStep ?? 0) > 0 { Text("Resumed session: this timing covers only the remaining work.").foregroundStyle(.orange) }
                    Text("Prompt-based style conditioning. No trained style adapter is recorded.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Effective model prompt") { Text(video.effectivePrompt).font(.callout).textSelection(.enabled) }
            }.studioBackground().navigationTitle("Generation details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
