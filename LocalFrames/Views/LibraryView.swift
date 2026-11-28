import ImageIO
import SwiftUI
import UIKit

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 100 }
    func removeAll() { cache.removeAllObjects() }
    func image(at url: URL) async -> UIImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        let image: UIImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }
}
struct VideoThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable() }
            else { Rectangle().fill(StudioTheme.surface).overlay { Image(systemName: "film").foregroundStyle(.secondary) } }
        }.task(id: url) { image = await ThumbnailCache.shared.image(at: url) }.accessibilityHidden(true)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("studio.libraryGrid") private var grid = true
    @AppStorage("studio.libraryNewest") private var newest = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var deletion: VideoRecord?
    @State private var share: SharedFiles?
    private var filtered: [VideoRecord] {
        model.videos.filter { query.isEmpty || ($0.prompt + " " + $0.styleName).localizedCaseInsensitiveContains(query) }
            .sorted { newest ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }
    var body: some View {
        Group {
            if model.videos.isEmpty {
                ContentUnavailableView("Your first frame awaits", systemImage: "film.stack", description: Text("Generated videos are saved on your iPhone and copied to your Local Frames folder in Files."))
                    .accessibilityIdentifier("emptyLibrary")
            } else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            else {
                ScrollView {
                    LazyVGrid(columns: grid ? [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 170), spacing: 16)] : [GridItem(.flexible())], spacing: 18) {
                        ForEach(filtered) { video in videoCard(video) }
                    }.padding(20)
                }
            }
        }.studioBackground().navigationTitle("Library").searchable(text: $query, prompt: "Search scenes and styles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Grid layout", isOn: $grid).accessibilityIdentifier("libraryGridToggle")
                        Toggle("Newest first", isOn: $newest)
                        if model.videos.count > 1 { NavigationLink("Compare outputs") { VideoComparisonView() } }
                    } label: { Image(systemName: grid ? "square.grid.2x2" : "list.bullet") }.accessibilityLabel("Library layout and sorting")
                }
            }
            .sheet(item: $share) { ActivityShareSheet(urls: $0.urls) }
            .confirmationDialog("Delete this library video? Copies previously exported to Files or Photos remain there.", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Delete video", role: .destructive) { if let deletion { Task { await model.delete(deletion) } }; deletion = nil }
            }
    }
    private func videoCard(_ video: VideoRecord) -> some View {
        Button { model.selectedVideo = video } label: {
            VStack(alignment: .leading, spacing: 10) {
                VideoThumbnail(url: model.library.thumbnailURL(video.id)).scaledToFit()
                    .aspectRatio(CGFloat(video.width) / CGFloat(video.height), contentMode: .fit)
                    .frame(maxWidth: .infinity).background(.black).clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(video.duration)s · \(video.framesPerSecond) FPS").font(.caption2.weight(.medium)).padding(8).studioGlass(radius: 14).padding(8)
                    }
                Text(video.prompt).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text(video.styleName).font(.caption).foregroundStyle(.secondary)
                Text(video.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
        }.buttonStyle(.plain).disabled(model.isGenerating)
            .accessibilityLabel("\(video.prompt), \(video.duration) seconds, \(video.styleName)")
            .contextMenu {
                Button("Play", systemImage: "play.fill") { model.selectedVideo = video }
                if video.canReuseSettings { Button("Regenerate / reuse settings", systemImage: "arrow.clockwise") { model.reuseSettings(video) }.disabled(model.working) }
                Button("Save to Photos", systemImage: "photo.badge.arrow.down") { Task { await model.saveToPhotos(video) } }
                Button("Export video and details", systemImage: "square.and.arrow.up") { Task { let urls = await model.exportVideo(video); if !urls.isEmpty { share = .init(urls: urls) } } }
                Button("Delete", systemImage: "trash", role: .destructive) { deletion = video }.disabled(model.working)
            }
    }
}
struct SharedFiles: Identifiable { let id = UUID(); let urls: [URL] }
