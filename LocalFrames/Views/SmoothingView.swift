import AVKit
import SwiftUI

struct SmoothingLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    var body: some View {
        List {
            Section {
                Text("Choose an original 2-second, 256 × 256, 12 FPS video. You will preview that exact clip and approve its upload before it leaves your iPhone.")
                    .font(.footnote)
                if model.videos.filter(SmoothingMedia.supports).isEmpty {
                    Text("No compatible clips yet. Generate a 2-second square video offline first.").accessibilityIdentifier("noSmoothingClips")
                }
                ForEach(model.videos.filter(SmoothingMedia.supports)) { video in
                    NavigationLink { SmoothingReviewView(video: video, support: support) } label: {
                        HStack {
                            if let image = UIImage(contentsOfFile: model.library.thumbnailURL(video.id).path) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            VStack(alignment: .leading) {
                                Text(video.prompt).lineLimit(2)
                                Text(video.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                Text("2s · 256 × 256 · 12 FPS").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.disabled(!support.enabled || model.working)
                }
            }
        }.navigationTitle("Choose a clip")
    }
}

struct SmoothingReviewView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    let video: VideoRecord
    @State private var consent = false
    @State private var player: AVPlayer?
    init(video: VideoRecord, support: OnlineSupport) { self.video = video; self.support = support }
    var body: some View {
        Form {
            Section("Optional 24 FPS copy · beta") {
                if let player { VideoPlayer(player: player).aspectRatio(1, contentMode: .fit) }
                Text(video.prompt).font(.headline)
                Text(video.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Text("Adds AI-interpolated frames after offline generation. It does not speed up MOVD, extend the clip, or fix all visual artifacts. The original stays in your library.").font(.caption)
            }
            if let prepared = model.smoothingPreview, prepared.original.id == video.id {
                Section("Review this upload") {
                    LabeledContent("Clip", value: "2s · 256 × 256 · 12 FPS")
                    LabeledContent("Upload size", value: ByteCountFormatter.string(fromByteCount: Int64(prepared.bytes), countStyle: .file))
                    Text("Destination: Hugging Face’s community Space 1inkusFace/RIFE. This sends the full video shown above directly to that third party, plus network metadata such as your IP address. Your prompt, seed, library metadata and other files are not attached.").font(.caption)
                    Text("The Space’s operator and hosting provider process the clip. Its retention period is not guaranteed, and Local Frames cannot confirm deletion. Cancelling may not stop remote processing. Only upload a clip you are comfortable sharing with this service.").font(.caption)
                    Text("Uses anonymous free access, or your connected free Hugging Face account after checking its status and included quota. Signed-in requests link this clip to that account at the provider. No credits, paid accounts, paid fallback or automatic retries. Quotas and queues may prevent completion. Keep this screen open on Wi-Fi.").font(.caption)
                    Link("View the helper", destination: RIFEClient.spaceURL)
                    Link("Hugging Face privacy policy", destination: URL(string: "https://huggingface.co/privacy")!)
                    Toggle("I agree to upload this clip", isOn: $consent).accessibilityIdentifier("smoothingConsent")
                    Button("Upload this clip & create 24 FPS copy") {
                        let approved = consent; consent = false; player?.pause()
                        model.startSmoothing(previewID: prepared.id, consent: approved)
                    }.disabled(!consent || !support.enabled || model.working).accessibilityIdentifier("uploadSmoothingClip")
                }
            }
            if model.smoothingActive {
                Section {
                    ProgressView(model.progress.message)
                    Text("Queue and network time vary; no reliable finish estimate is available.").font(.caption)
                    Button("Cancel smoothing", role: .cancel) { model.cancel(); consent = false }
                }
            }
            if let message = model.smoothingMessage { Section { Text(message).accessibilityIdentifier("smoothingMessage") } }
            if let result = model.smoothingResult, result.parentVideoID == video.id {
                Section("Saved separately") {
                    Text("2 seconds · 48 frames · 24 FPS · 256 × 256")
                    Text("The helper creates intermediate frames. If it returns 47 frames, the last frame is held for one extra 1/24 second to preserve the original 2-second duration.").font(.caption)
                    Button("Open saved 24 FPS copy") { model.selectedVideo = result }
                    NavigationLink("Compare saved outputs") { VideoComparisonView() }
                }
            } else if !model.working && model.smoothingPreview == nil && support.enabled {
                Section { Button("Review clip again") { consent = false; model.prepareSmoothing(video) } }
            }
            if !support.enabled { Text("Online support is off. No clip will be uploaded.") }
        }.navigationTitle("24 FPS smoothing").navigationBarTitleDisplayMode(.inline)
            .task { consent = false; model.prepareSmoothing(video) }
            .onChange(of: model.smoothingPreview?.id) { _, _ in
                consent = false; player?.pause()
                player = model.smoothingPreview.map { AVPlayer(url: $0.clipURL) }
            }
            .onChange(of: support.enabled) { _, enabled in if !enabled { consent = false; player?.pause() } }
            .onDisappear { consent = false; player?.pause(); model.closeSmoothingReview() }
    }
}

struct SmoothingPreviewLink: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var support: OnlineSupport
    let video: VideoRecord
    var body: some View {
        if support.enabled && SmoothingMedia.supports(video) {
            NavigationLink("Create 24 FPS copy · online") { SmoothingReviewView(video: video, support: support) }
                .disabled(model.working)
        } else if !support.enabled && SmoothingMedia.supports(video) {
            Text("Optional 24 FPS smoothing is available in Setup → Online support. Each clip requires your approval before upload.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
