// Fabricated moving shapes for remote interpolation acceptance; no user media.
import AVFoundation
import Foundation

@main struct Fixture {
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 256, AVVideoHeightKey: 256])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 256, kCVPixelBufferHeightKey as String: 256])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else { fatalError("buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<256 { for x in 0..<256 {
                let moving = abs(x - (28 + frame * 8)) < 18 && abs(y - 128) < 25
                let grid = (x / 16 + y / 16).isMultiple(of: 2)
                bytes[y * stride + x * 4] = moving ? 30 : (grid ? 50 : 70)
                bytes[y * stride + x * 4 + 1] = moving ? 180 : (grid ? 50 : 70)
                bytes[y * stride + x * 4 + 2] = moving ? 245 : (grid ? 50 : 70)
                bytes[y * stride + x * 4 + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 12)) else { throw writer.error! }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 12))
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        print("Created synthetic fixture: 24 frames, 12 FPS, 2 seconds, 256 x 256")
    }
}
