// Synthetic-fixture acceptance only. Does not upload files or modify its inputs.
// Optional endpoint normalization accepts only a 2N-1-frame 2x result and adds
// one held terminal frame. The 23 model-generated in-between frames stay intact.
import AVFoundation
import CryptoKit
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case let .invalid(message): return message } }
}

struct Frame {
    let buffer: CVPixelBuffer
    let time: Double
    let centroidX: Double
    let orangePixels: Int
    let hash: String
}

struct Clip {
    let duration: Double
    let fps: Float
    let width: Int
    let height: Int
    let frames: [Frame]
    let sha256: String
}

func readClip(_ url: URL) async throws -> Clip {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
        throw ProbeError.invalid("No video track")
    }
    let size = try await track.load(.naturalSize)
    guard size.width == 256, size.height == 256 else {
        throw ProbeError.invalid("This probe accepts only the fabricated 256 x 256 fixture")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    output.alwaysCopiesSampleData = true
    reader.add(output)
    guard reader.startReading() else { throw reader.error ?? ProbeError.invalid("Reader failed") }
    var frames: [Frame] = []
    while let sample = output.copyNextSampleBuffer() {
        guard frames.count < 60, let buffer = CMSampleBufferGetImageBuffer(sample) else {
            throw ProbeError.invalid("Expected a short synthetic fixture")
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            throw ProbeError.invalid("Missing pixel data")
        }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var xSum = 0.0
        var count = 0
        var hasher = SHA256()
        for y in 0..<256 {
            // Ignore padding so decoded-frame hashes compare visible pixels only.
            hasher.update(data: Data(bytes: base.advanced(by: y * stride), count: 256 * 4))
            for x in 0..<256 {
                let p = y * stride + x * 4
                let b = Double(bytes[p]), g = Double(bytes[p + 1]), r = Double(bytes[p + 2])
                if r > 140, g > 90, r > g * 1.15, g > b * 1.5 {
                    xSum += Double(x)
                    count += 1
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        guard count > 500 else { throw ProbeError.invalid("Synthetic orange subject was not detected") }
        frames.append(Frame(buffer: buffer, time: CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                            centroidX: xSum / Double(count), orangePixels: count,
                            hash: hasher.finalize().map { String(format: "%02x", $0) }.joined()))
    }
    guard reader.status == .completed else { throw reader.error ?? ProbeError.invalid("Decode failed") }
    let fileHash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    return Clip(duration: try await asset.load(.duration).seconds,
                fps: try await track.load(.nominalFrameRate), width: Int(size.width), height: Int(size.height),
                frames: frames, sha256: fileHash)
}

func stats(_ values: [Double]) -> [String: Double] {
    ["mean": values.reduce(0, +) / Double(values.count), "max": values.max() ?? 0]
}

func describe(_ clip: Clip) -> [String: Any] {
    ["durationSeconds": clip.duration, "nominalFPS": clip.fps, "width": clip.width,
     "height": clip.height, "decodedFrames": clip.frames.count, "sha256": clip.sha256,
     "uniqueDecodedFrames": Set(clip.frames.map(\.hash)).count,
     "presentationTimesSeconds": clip.frames.map(\.time),
     "subjectCentroidX": clip.frames.map(\.centroidX)]
}

func analyze(source: Clip, result: Clip) throws -> [String: Any] {
    guard source.frames.count == 24, abs(source.fps - 12) < 0.001,
          abs(source.duration - 2) < 0.001,
          zip(source.frames.indices, source.frames).allSatisfy({ abs($0.1.centroidX - Double(28 + $0.0 * 8)) < 0.75 }) else {
        throw ProbeError.invalid("Input is not the expected moving-shapes fixture")
    }
    guard [47, 48].contains(result.frames.count), abs(result.fps - 24) < 0.001 else {
        throw ProbeError.invalid("Expected 47 or 48 frames at 24 FPS")
    }
    let midpointErrors = (0..<23).map { index in
        abs(result.frames[2 * index + 1].centroidX -
            (source.frames[index].centroidX + source.frames[index + 1].centroidX) / 2)
    }
    let originalErrors = (0..<24).map { abs(result.frames[2 * $0].centroidX - source.frames[$0].centroidX) }
    let distinctMidpoints = (0..<23).filter { index in
        let middle = result.frames[2 * index + 1]
        let before = result.frames[2 * index]
        let after = result.frames[2 * index + 2]
        return middle.hash != before.hash && middle.hash != after.hash &&
            middle.centroidX > before.centroidX + 1 && middle.centroidX < after.centroidX - 1
    }.count
    let timestampErrors = result.frames.indices.map { abs(result.frames[$0].time - Double($0) / 24) }
    return [
        "expectedOutputFrames": 48, "expectedDurationSeconds": 2,
        "frameCountMatches": result.frames.count == 48,
        "durationMatchesWithinOneMillisecond": abs(result.duration - source.duration) <= 0.001,
        "maxTimestampErrorSeconds": timestampErrors.max() ?? 0,
        "testedIntermediateFrames": 23, "distinctIntermediateMotionFrames": distinctMidpoints,
        "midpointCentroidErrorPixels": stats(midpointErrors),
        "preservedFrameCentroidErrorPixels": stats(originalErrors),
        "syntheticMotionPass": distinctMidpoints == 23 && (midpointErrors.max() ?? .infinity) < 0.75,
        "limitations": "One fabricated translation case; not a natural-scene, occlusion, iPhone, or MOVD speed benchmark."
    ]
}

func normalizeEndpoint(_ clip: Clip, to url: URL) async throws {
    guard clip.frames.count == 47, abs(clip.fps - 24) < 0.001,
          abs(clip.duration - 47.0 / 24) <= 0.001,
          clip.frames.indices.allSatisfy({ abs(clip.frames[$0].time - Double($0) / 24) < 0.001 }),
          !FileManager.default.fileExists(atPath: url.path) else {
        throw ProbeError.invalid("Endpoint normalization requires a 2N-1 result and a new destination")
    }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 256, AVVideoHeightKey: 256,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000, AVVideoExpectedSourceFrameRateKey: 24]
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? ProbeError.invalid("Writer failed") }
    writer.startSession(atSourceTime: .zero)
    for index in 0..<48 {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { throw writer.error ?? ProbeError.invalid("Writer stopped") }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        guard adaptor.append(clip.frames[min(index, 46)].buffer,
                             withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else {
            throw writer.error ?? ProbeError.invalid("Append failed")
        }
    }
    writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? ProbeError.invalid("Encode failed") }
}

@main struct VerifyInterpolation {
    static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 || (args.count == 5 && args[3] == "--normalize-endpoint") else {
            throw ProbeError.invalid("Usage: verify-interpolation INPUT.mp4 RAW_RESULT.mp4 REPORT.json [--normalize-endpoint NEW.mp4]")
        }
        let reportURL = URL(fileURLWithPath: args[2])
        guard !FileManager.default.fileExists(atPath: reportURL.path) else { throw ProbeError.invalid("Report already exists") }
        let source = try await readClip(URL(fileURLWithPath: args[0]))
        let result = try await readClip(URL(fileURLWithPath: args[1]))
        var report: [String: Any] = ["schemaVersion": 1, "fixture": "moving-shapes-12fps-v1",
                                   "source": describe(source), "rawResult": describe(result),
                                   "rawAcceptance": try analyze(source: source, result: result)]
        if args.count == 5 {
            let normalizedURL = URL(fileURLWithPath: args[4])
            try await normalizeEndpoint(result, to: normalizedURL)
            let normalized = try await readClip(normalizedURL)
            report["normalizedResult"] = describe(normalized)
            report["normalizedAcceptance"] = try analyze(source: source, result: normalized)
            report["normalization"] = "Re-encoded on Mac; one 1/24-second terminal hold added. No generated intermediate frames replaced. Originals unchanged."
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: reportURL, options: .withoutOverwriting)
        print(String(data: data, encoding: .utf8)!)
    }
}
