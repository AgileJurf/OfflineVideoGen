import AVFoundation
import Foundation
import UIKit
import VideoEngine

struct VideoRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let prompt: String
    let duration: Int
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let seed: UInt64
    let createdAt: Date
    let metrics: GenerationMetrics

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

actor VideoLibrary {
    let root: URL
    init(root: URL) { self.root = root }
    nonisolated func videoURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".mp4") }
    nonisolated func thumbnailURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".jpg") }

    func list() throws -> [VideoRecord] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), let item = try? JSONDecoder().decode(VideoRecord.self, from: data),
                  FileManager.default.fileExists(atPath: videoURL(item.id).path) else { return nil }
            return item
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func add(temporaryURL: URL, request: GenerationRequest, metrics: GenerationMetrics) async throws -> VideoRecord {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let item = VideoRecord(id: UUID(), prompt: request.prompt, duration: request.duration, width: request.width,
                               height: request.height, framesPerSecond: request.framesPerSecond, seed: request.seed,
                               createdAt: Date(), metrics: metrics)
        let destination = videoURL(item.id)
        try fm.moveItem(at: temporaryURL, to: destination)
        do {
            try JSONEncoder().encode(item).write(to: root.appendingPathComponent(item.id.uuidString + ".json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: destination))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 384, height: 384)
        if let image = try? await generator.image(at: .zero).image, let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) {
            try? data.write(to: thumbnailURL(item.id), options: .atomic)
        }
        return item
    }

    func delete(_ item: VideoRecord) throws {
        let fm = FileManager.default
        // Remove the video first; interruption cannot leave a playable orphan in the visible library.
        for url in [videoURL(item.id), root.appendingPathComponent(item.id.uuidString + ".json"), thumbnailURL(item.id)] {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }
}
