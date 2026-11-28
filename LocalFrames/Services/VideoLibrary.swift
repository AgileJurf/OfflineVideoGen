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
    var generationMode: GenerationMode? = nil
    var effectiveModelPrompt: String? = nil
    var visualStyle: VisualStyle? = nil
    var styleConditioningVersion: Int? = nil
    var outputFraming: OutputFraming? = nil
    var requestedFraming: OutputFraming? = nil
    var sourceImageReference: String? = nil
    var parentVideoID: UUID? = nil
    var extensionHistory: [UUID]? = nil
    var mediaKind: String? = nil
    var postprocessingSeconds: Double? = nil
    var smoothing: SmoothingProvenance? = nil
    var modelID: String? = nil
    var styleConditioning: StyleConditioning? = nil

    var style: VisualStyle { visualStyle ?? .default }
    var effectivePrompt: String { effectiveModelPrompt ?? prompt }
    var isCrop: Bool { mediaKind == "center-crop-v1" }
    var framing: OutputFraming { outputFraming ?? .square }
    var isNeodragon: Bool { modelID == NeodragonModel.identifier || metrics.modelRevision == NeodragonModel.weightsRevision }
    var framingName: String { isNeodragon && !isCrop ? "Native 16:10" : framing.name }
    var styleName: String { styleConditioning?.name ?? style.name }
    var canReuseSettings: Bool {
        (generationMode ?? .textToVideo) == .textToVideo && isNeodragon && smoothing == nil
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

actor VideoLibrary {
    let root: URL
    init(root: URL) { self.root = root }
    nonisolated func videoURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".mp4") }
    nonisolated func metadataURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
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

    func addNeodragon(temporaryURL: URL, request: NeodragonGenerationRequest, metrics: GenerationMetrics, conditioning: StyleConditioning? = nil) async throws -> VideoRecord {
        guard metrics.modelRevision == NeodragonModel.weightsRevision else { throw GenerationError.invalidTensor }
        let item = VideoRecord(id: UUID(), prompt: request.prompt, duration: request.duration,
            width: NeodragonModel.width, height: NeodragonModel.height, framesPerSecond: NeodragonModel.framesPerSecond,
            seed: request.seed, createdAt: Date(), metrics: metrics, generationMode: .textToVideo,
            effectiveModelPrompt: request.effectivePrompt, visualStyle: request.style, styleConditioningVersion: conditioning?.version ?? 1,
            mediaKind: "generated", modelID: NeodragonModel.identifier, styleConditioning: conditioning)
        return try await persist(item, temporaryURL: temporaryURL)
    }

    private func persist(_ item: VideoRecord, temporaryURL: URL) async throws -> VideoRecord {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
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
