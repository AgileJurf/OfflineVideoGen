import AVFoundation
import VideoEngine

/// Explicit postprocessing of an existing generated video. No inference is performed here.
enum VideoCropExporter {
    static func export(source: URL, destination: URL, framing: OutputFraming,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard framing.isCrop, source.standardizedFileURL != destination.standardizedFileURL,
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw GenerationError.encodingFailed("Choose a new destination for the cropped copy")
        }
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GenerationError.encodingFailed("The original has no video track")
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let fps = try await track.load(.nominalFrameRate)
        // The current library contains native square MOVD clips. Do not silently scale or
        // repeatedly crop a derivative, or accept an untested rotated/variable-rate source.
        guard size == CGSize(width: 256, height: 256), transform.isIdentity,
              abs(fps - 12) < 0.1, duration.seconds.isFinite, duration.seconds > 0 else {
            throw GenerationError.encodingFailed("Crop export needs the original 256 × 256, 12 FPS video")
        }
        try Task.checkCancellation()
        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: framing.width, height: framing.height)
        composition.frameDuration = CMTime(value: 1, timescale: 12)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(translationX: -CGFloat(256 - framing.width) / 2,
                                             y: -CGFloat(256 - framing.height) / 2), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw GenerationError.encodingFailed("Crop export is unavailable")
        }
        exporter.videoComposition = composition
        exporter.shouldOptimizeForNetworkUse = false
        let cancellation = ExportCancellation(exporter)
        let reporter = Task {
            while !Task.isCancelled {
                progress(Double(exporter.progress))
                do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
            }
        }
        defer { reporter.cancel() }
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await exporter.export(to: destination, as: .mp4)
                try Task.checkCancellation()
            } onCancel: { cancellation.cancel() }
            let result = AVURLAsset(url: destination)
            guard let resultTrack = try await result.loadTracks(withMediaType: .video).first else {
                throw GenerationError.encodingFailed("The cropped copy has no video track")
            }
            let outputSize = try await resultTrack.load(.naturalSize)
            let outputDuration = try await result.load(.duration).seconds
            guard outputSize == composition.renderSize, abs(outputDuration - duration.seconds) < 0.05 else {
                throw GenerationError.encodingFailed("Crop dimensions or duration were not preserved")
            }
            progress(1)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// AVFoundation supports cancelling an active asynchronous export. Confine the
/// cross-task reference to that operation; configuration remains in export().
private final class ExportCancellation: @unchecked Sendable {
    private let exporter: AVAssetExportSession
    init(_ exporter: AVAssetExportSession) { self.exporter = exporter }
    func cancel() { exporter.cancelExport() }
}
