import AVKit
import SwiftUI
import UniformTypeIdentifiers
import VideoEngine

struct VideoFile: FileDocument {
    static var readableContentTypes: [UTType] { [.mpeg4Movie] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnsupportedScheme) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: .immediate)
    }
}

struct PreviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let video: VideoRecord
    @State private var player: AVPlayer?
    @State private var exporting = false
    @State private var deleting = false
    @State private var showExtensionInfo = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VideoPlayer(player: player).aspectRatio(CGFloat(video.width) / CGFloat(video.height), contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22))
                    HStack {
                        Button("Replay", systemImage: "arrow.counterclockwise") { player?.seek(to: .zero); player?.play() }
                        Spacer()
                        Text("\(video.duration)s · \(video.width) × \(video.height) · \(video.framesPerSecond) FPS").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(video.prompt).font(.headline)
                    LabeledContent("Style", value: video.style.name)
                    if video.isNeodragon { LabeledContent("Model", value: "Neodragon · native 24 FPS"); LabeledContent("Framing", value: video.framingName) }
                    LabeledContent("Seed", value: String(video.seed)).font(.caption)
                    if let smoothing = video.smoothing {
                        Label("24 FPS interpolated copy", systemImage: "sparkles.tv").font(.caption).foregroundStyle(.mint)
                        Text("Created with \(smoothing.provider). The original remains a separate library item. This is postprocessing, not a new diffusion generation.").font(.caption)
                        LabeledContent("Online processing + transfer", value: String(format: "%.1f seconds", smoothing.elapsedSeconds)).font(.caption)
                        Text("\(smoothing.returnedFrames) returned frames · \(smoothing.terminalHoldFrames) terminal hold frame(s). Reusing settings selects the 24 FPS workflow: a new local original followed by a fresh upload review.").font(.caption).foregroundStyle(.secondary)
                    }
                    SmoothingPreviewLink(support: model.support, video: video)
                    if video.isCrop {
                        Label("\(video.framing.name) · center-cropped copy", systemImage: "crop").font(.caption).foregroundStyle(.mint)
                        Text("The square original was saved separately. This copy contains no additional AI-generated frames.").font(.caption).foregroundStyle(.secondary)
                    }
                    if video.style != .default {
                        DisclosureGroup("Effective model prompt") { Text(video.effectivePrompt).font(.caption).textSelection(.enabled) }
                    }
                    Text(video.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save to Photos", systemImage: "photo.badge.arrow.down") { Task { await model.saveToPhotos(video) } }
                        Spacer()
                        Button("Export to Files", systemImage: "square.and.arrow.up") { exporting = true }
                    }.buttonStyle(.bordered).font(.subheadline)
                    Button("Reuse settings / change style", systemImage: "sparkles") { model.reuseSettings(video); dismiss() }
                        .disabled(model.working || !video.canReuseSettings)
                    Text("Restores the original prompt, style, duration and seed in Create. Choose another style there to compare results.").font(.caption).foregroundStyle(.secondary)
                    NavigationLink("Compare saved outputs") { VideoComparisonView() }.disabled(model.videos.count < 2)
                    Button("Extend Video · unavailable", systemImage: "lock") { showExtensionInfo = true }
                    if !video.isCrop && video.smoothing == nil && video.width == 256 && video.height == 256 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SAVE A CROPPED COPY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text("Center crop only. The square original remains unchanged.").font(.caption)
                            HStack {
                                Button("Portrait 9:16") { model.exportCrop(video, framing: .portrait) }
                                Button("Landscape 16:9") { model.exportCrop(video, framing: .landscape) }
                            }.buttonStyle(.bordered).disabled(model.working)
                            if model.exportingCrop {
                                ProgressView(value: model.progress.fraction)
                                Button("Cancel crop export", role: .cancel) { model.cancel() }
                            }
                        }
                    }
                    Button("Delete video", systemImage: "trash", role: .destructive) { deleting = true }.disabled(model.working)
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }.padding(22)
            }.navigationTitle("Your video").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: video.id) { player?.pause(); player = AVPlayer(url: model.library.videoURL(video.id)) }
                .onDisappear { player?.pause() }
                .fileExporter(isPresented: $exporting, document: VideoFile(url: model.library.videoURL(video.id)), contentType: .mpeg4Movie,
                              defaultFilename: "LocalFrames-\(video.id.uuidString.prefix(8))") { result in
                    if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
                }
                .confirmationDialog("Delete this video permanently?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete video", role: .destructive) { Task { await model.delete(video); dismiss() } }
                }
                .alert("Video continuation needs another model path", isPresented: $showExtensionInfo) {
                    Button("OK", role: .cancel) { }
                } message: { Text(GenerationMode.extendVideo.unavailableReason ?? "") }
        }
    }
}
