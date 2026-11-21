import AVFoundation
import CoreML
import Foundation

/// Encodes actual model frames. Never synthesizes, repeats, or interpolates frames.
final class VideoEncoder {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let output: URL
    private let width: Int
    private let height: Int
    private let fps: Int
    private(set) var frameCount = 0

    init(output: URL, width: Int, height: Int, fps: Int) throws {
        self.output = output
        self.width = width
        self.height = height
        self.fps = fps
        writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(input) else { throw GenerationError.encodingFailed("Unsupported encoder") }
        writer.add(input)
        guard writer.startWriting() else { throw GenerationError.encodingFailed(writer.error?.localizedDescription ?? "Encoder startup") }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ array: MLShapedArray<Float32>, limit: Int) async throws {
        let shape = array.shape
        guard shape.count == 5, shape[0] == 1, shape[1] == 3, shape[3] == height, shape[4] == width else {
            throw GenerationError.invalidTensor
        }
        let frames = shape[2]
        let plane = width * height
        let values = array.scalars
        for frame in 0..<frames where frameCount < limit {
            try Task.checkCancellation()
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                    throw GenerationError.encodingFailed(writer.error?.localizedDescription ?? "Encoder timed out")
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw GenerationError.encodingFailed("Pixel buffer pool unavailable") }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw GenerationError.memoryPressure
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            do {
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else {
                    throw GenerationError.invalidTensor
                }
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for y in 0..<height {
                    for x in 0..<width {
                        let pixel = y * width + x
                        for channel in 0..<3 {
                            let value = values[(channel * frames + frame) * plane + pixel]
                            guard value.isFinite else { throw GenerationError.invalidTensor }
                            base[y * stride + x * 4 + (2 - channel)] = UInt8(max(0, min(255, (value + 1) * 127.5)))
                        }
                        base[y * stride + x * 4 + 3] = 255
                    }
                }
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frameCount), timescale: Int32(fps))) else {
                throw GenerationError.encodingFailed(writer.error?.localizedDescription ?? "Frame rejected")
            }
            frameCount += 1
        }
    }

    func finish(expectedFrames: Int) async throws {
        guard frameCount == expectedFrames else { throw GenerationError.encodingFailed("Incorrect frame count") }
        writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: Int32(fps)))
        input.markAsFinished()
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw GenerationError.encodingFailed(writer.error?.localizedDescription ?? "Encoding failed") }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: output)
    }
}
