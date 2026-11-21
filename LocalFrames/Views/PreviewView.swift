import AVKit
import SwiftUI
import UniformTypeIdentifiers

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
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VideoPlayer(player: player).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22))
                    HStack {
                        Button("Replay", systemImage: "arrow.counterclockwise") { player?.seek(to: .zero); player?.play() }
                        Spacer()
                        Text("\(video.duration)s · \(video.width) × \(video.height)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(video.prompt).font(.headline)
                    Text(video.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Save to Photos", systemImage: "photo.badge.arrow.down") { Task { await model.saveToPhotos(video) } }
                        Spacer()
                        Button("Export to Files", systemImage: "square.and.arrow.up") { exporting = true }
                    }.buttonStyle(.bordered).font(.subheadline)
                    Button("Regenerate", systemImage: "sparkles") {
                        model.prompt = video.prompt; model.duration = video.duration
                        dismiss(); model.generate()
                    }.disabled(model.working || !model.installed)
                    Button("Delete video", systemImage: "trash", role: .destructive) { deleting = true }
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }.padding(22)
            }.navigationTitle("Your video").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { player = AVPlayer(url: model.library.videoURL(video.id)) }
                .onDisappear { player?.pause() }
                .fileExporter(isPresented: $exporting, document: VideoFile(url: model.library.videoURL(video.id)), contentType: .mpeg4Movie,
                              defaultFilename: "LocalFrames-\(video.id.uuidString.prefix(8))") { result in
                    if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
                }
                .confirmationDialog("Delete this video permanently?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete video", role: .destructive) { Task { await model.delete(video); dismiss() } }
                }
        }
    }
}
