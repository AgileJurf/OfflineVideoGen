import AVFoundation
import CryptoKit
import Foundation

enum SmoothingError: Error, LocalizedError {
    case consentRequired, disabled, unsupported, changedClip, unavailable, quota, invalidResponse, tooLarge
    var errorDescription: String? {
        switch self {
        case .consentRequired: return "Review this clip and consent again before uploading. No automatic retries are made."
        case .disabled: return "Enable online support before choosing 24 FPS smoothing."
        case .unsupported: return "This beta supports original 2-second, 256 × 256, 12 FPS clips only."
        case .changedClip: return "The selected clip changed. Choose it again and review the new preview."
        case .quota: return "The free helper’s quota is unavailable. Your original is safe. Try again later; there is no paid fallback."
        case .unavailable: return "The free helper could not finish. Check Wi-Fi or try again later. Your original is safe; nothing will retry automatically."
        case .invalidResponse: return "The helper returned an incompatible result. No copy was saved; your original is unchanged."
        case .tooLarge: return "This clip or helper response exceeds the beta’s size limit. Your original is unchanged."
        }
    }
}

/// One immutable, locally verified preview. Never persist consent or reuse it for a second request.
struct PreparedSmoothing: Identifiable {
    let id: UUID
    let original: VideoRecord
    let directory: URL
    let clipURL: URL
    let sha256: String
    let bytes: Int
}

struct SmoothingProvenance: Codable, Hashable {
    let provider: String
    let method: String
    let sourceSHA256: String
    let sourceFrames: Int
    let returnedFrames: Int
    let terminalHoldFrames: Int
    let elapsedSeconds: Double
}

struct SmoothingResult {
    let url: URL
    let provenance: SmoothingProvenance
}

enum SmoothingMedia {
    static let maximumBytes = 8 * 1024 * 1024
    static func supports(_ video: VideoRecord) -> Bool {
        video.duration == 2 && video.width == 256 && video.height == 256 && video.framesPerSecond == 12
            && !video.isCrop && video.smoothing == nil && (video.mediaKind == nil || video.mediaKind == "generated")
    }

    static func fingerprint(_ url: URL) throws -> (hash: String, bytes: Int) {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let count = size.fileSize, count > 0, count <= maximumBytes else { throw SmoothingError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256(), bytes = 0
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes += chunk.count
            guard bytes <= maximumBytes else { throw SmoothingError.tooLarge }
            hash.update(data: chunk)
        }
        guard bytes == count else { throw SmoothingError.changedClip }
        return (hash.finalize().map { String(format: "%02x", $0) }.joined(), count)
    }

    static func prepare(_ original: VideoRecord, source: URL, temporaryRoot: URL) async throws -> PreparedSmoothing {
        guard supports(original) else { throw SmoothingError.unsupported }
        let id = UUID(), directory = temporaryRoot.appendingPathComponent("Smoothing-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            // Freeze precisely the file shown in the consent preview, without its library filename or sidecar.
            let clip = directory.appendingPathComponent("clip.mp4")
            _ = try fingerprint(source)
            try FileManager.default.copyItem(at: source, to: clip)
            _ = try await inspect(clip, fps: 12, acceptedCounts: [24])
            let verified = try fingerprint(clip)
            return PreparedSmoothing(id: id, original: original, directory: directory, clipURL: clip, sha256: verified.hash, bytes: verified.bytes)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    /// Decode actual frames and check timestamps, not just container FPS metadata.
    static func inspect(_ url: URL, fps: Int, acceptedCounts: Set<Int>) async throws -> Int {
        _ = try fingerprint(url)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1, audio.isEmpty, let track = tracks.first else { throw SmoothingError.invalidResponse }
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let rate = try await track.load(.nominalFrameRate), duration = try await asset.load(.duration).seconds
        guard size == CGSize(width: 256, height: 256), transform.isIdentity, abs(rate - Float(fps)) < 0.01,
              duration.isFinite, duration > 1.9, duration < 2.01 else { throw SmoothingError.invalidResponse }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw SmoothingError.invalidResponse }
        reader.add(output)
        guard reader.startReading() else { throw SmoothingError.invalidResponse }
        defer { reader.cancelReading() }
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard count < 48, let buffer = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferGetWidth(buffer) == 256, CVPixelBufferGetHeight(buffer) == 256,
                  abs(CMSampleBufferGetPresentationTimeStamp(sample).seconds - Double(count) / Double(fps)) < 0.002 else { throw SmoothingError.invalidResponse }
            count += 1
        }
        guard reader.status == .completed, acceptedCounts.contains(count), abs(duration - Double(count) / Double(fps)) < 0.002 else { throw SmoothingError.invalidResponse }
        return count
    }

    /// RIFE returns 2N-1 frames. Hold its final frame for one extra 1/24 second to retain the full source duration.
    /// This is endpoint padding, not a claim of another AI-generated motion frame. Memory stays bounded to a few buffers.
    static func normalize(_ raw: URL, destination: URL) async throws -> (returned: Int, held: Int) {
        let count = try await inspect(raw, fps: 24, acceptedCounts: [47, 48])
        guard raw != destination, !FileManager.default.fileExists(atPath: destination.path) else { throw SmoothingError.invalidResponse }
        let asset = AVURLAsset(url: raw)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SmoothingError.invalidResponse }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false; reader.add(output)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 256, AVVideoHeightKey: 256,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoExpectedSourceFrameRateKey: 24]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        do {
            try Task.checkCancellation()
            guard reader.startReading(), writer.startWriting() else { throw SmoothingError.invalidResponse }
            writer.startSession(atSourceTime: .zero)
            var index = 0, last: CVPixelBuffer?
            func append(_ buffer: CVPixelBuffer) async throws {
                let deadline = ProcessInfo.processInfo.systemUptime + 10
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else { throw SmoothingError.invalidResponse }
                    try await Task.sleep(for: .milliseconds(2))
                }
                try Task.checkCancellation()
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else { throw SmoothingError.invalidResponse }
                index += 1
            }
            while let sample = output.copyNextSampleBuffer() {
                guard index < count, let buffer = CMSampleBufferGetImageBuffer(sample) else { throw SmoothingError.invalidResponse }
                try await append(buffer); last = buffer
            }
            guard reader.status == .completed, index == count, let last else { throw SmoothingError.invalidResponse }
            if count == 47 { try await append(last) }
            writer.endSession(atSourceTime: CMTime(value: 48, timescale: 24)); input.markAsFinished()
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw SmoothingError.invalidResponse }
            _ = try await inspect(destination, fps: 24, acceptedCounts: [48])
            return (count, 48 - count)
        } catch {
            reader.cancelReading(); writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
