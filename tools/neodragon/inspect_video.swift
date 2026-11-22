import AVFoundation
import AppKit
import CryptoKit
import Foundation

/// Inspect the actual local export. Frame differences describe decoded pixels;
/// they are not a perceptual quality, motion consistency or prompt-adherence score.
@main struct InspectVideo {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "VideoInspection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: inspect-video input.mp4 new-output-directory"])
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else {
            throw NSError(domain: "VideoInspection", code: 2, userInfo: [NSLocalizedDescriptionKey: "Use a new evidence directory"])
        }
        let asset = AVURLAsset(url: input)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw inspectionError("No video track") }
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        guard fps.isFinite, fps > 0, duration.isFinite, duration > 0 else { throw inspectionError("Invalid video timing") }
        let compressedReader = try AVAssetReader(asset: asset)
        let compressed = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        compressedReader.add(compressed)
        guard compressedReader.startReading() else { throw inspectionError("Cannot read compressed samples") }
        var compressedBuffers = 0, compressedSamples = 0, emptyCompressedBuffers = 0, maximumSamplesPerBuffer = 0
        while let sample = compressed.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            compressedBuffers += 1
            compressedSamples += count
            if count == 0 { emptyCompressedBuffers += 1 }
            maximumSamplesPerBuffer = max(maximumSamplesPerBuffer, count)
        }
        guard compressedReader.status == .completed else { throw inspectionError("Incomplete compressed samples") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? inspectionError("Cannot read video") }
        var hashes: [String] = [], differences: [Double] = [], previous: [UInt8]?
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw inspectionError("No decoded pixels") }
            let pixels = try readPixels(buffer)
            hashes.append(SHA256.hash(data: Data(pixels)).map { String(format: "%02x", $0) }.joined())
            if let previous {
                guard previous.count == pixels.count else { throw inspectionError("Frame dimensions changed") }
                var sum: Int64 = 0
                for index in pixels.indices where index % 4 != 3 { sum += Int64(abs(Int(pixels[index]) - Int(previous[index]))) }
                differences.append(Double(sum) / Double(pixels.count / 4 * 3))
            }
            previous = pixels
        }
        guard reader.status == .completed, !hashes.isEmpty else { throw reader.error ?? inspectionError("Incomplete video") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var thumbnails: [String] = []
        let sampleCount = min(6, hashes.count)
        for offset in 0..<sampleCount {
            let frame = offset * (hashes.count - 1) / max(1, sampleCount - 1)
            let image = try await generator.image(at: CMTime(seconds: Double(frame) / Double(fps), preferredTimescale: 24_000)).image
            let name = String(format: "frame-%03d.png", frame)
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw inspectionError("Cannot encode inspection image")
            }
            try data.write(to: directory.appendingPathComponent(name))
            thumbnails.append(name)
        }
        let report: [String: Any] = ["scope": "Local export integrity and pixel variation; not a device benchmark or perceptual quality score",
            "file": input.lastPathComponent, "durationSeconds": duration, "framesPerSecond": fps,
            "width": size.width, "height": size.height, "decodedFrames": hashes.count,
            "compressedSampleBuffers": compressedBuffers, "compressedSamples": compressedSamples,
            "emptyCompressedBuffers": emptyCompressedBuffers, "maximumCompressedSamplesPerBuffer": maximumSamplesPerBuffer,
            "uniqueDecodedFrames": Set(hashes).count, "decodedFrameSHA256": hashes,
            "adjacentRGBMeanAbsoluteDifference0To255": differences, "inspectionImages": thumbnails]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("inspection.json"))
        print("Decoded \(hashes.count) frames; \(Set(hashes).count) unique; \(size.width) × \(size.height); \(fps) FPS; \(duration) seconds")
    }

    private static func inspectionError(_ message: String) -> NSError {
        NSError(domain: "VideoInspection", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func readPixels(_ buffer: CVPixelBuffer) throws -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw inspectionError("Missing pixel storage") }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var result: [UInt8] = []
        result.reserveCapacity(width * height * 4)
        for row in 0..<height {
            result.append(contentsOf: UnsafeBufferPointer(start: base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self), count: width * 4))
        }
        return result
    }
}
