import CoreML
import CryptoKit
import Foundation

/// Stores exact Float32 tensor bytes, never a substitute video or a changed diffusion schedule.
public enum GenerationCheckpoint {
    public struct Summary: Sendable {
        public let request: GenerationRequest
        public let completedSteps: Int
    }

    struct Tensor: Codable {
        let shape: [Int]
        let bytes: Data

        init(_ array: MLShapedArray<Float32>) {
            shape = array.shape
            bytes = array.scalars.withUnsafeBytes { Data($0) }
        }

        func array(expectedShape: [Int]) throws -> MLShapedArray<Float32> {
            guard shape == expectedShape, bytes.count == expectedShape.reduce(1, *) * MemoryLayout<Float32>.size else {
                throw GenerationError.invalidCheckpoint
            }
            let values = [Float32](unsafeUninitializedCapacity: bytes.count / 4) { buffer, count in
                bytes.copyBytes(to: UnsafeMutableRawBufferPointer(buffer))
                count = buffer.count
            }
            guard values.allSatisfy(\.isFinite) else { throw GenerationError.invalidCheckpoint }
            return MLShapedArray(scalars: values, shape: shape)
        }
    }

    struct State: Codable {
        let version: Int
        let modelRevision: String
        let configuration: String
        let request: GenerationRequest
        let completedSteps: Int
        let latent: Tensor
        let hidden: Tensor
        let unconditional: Tensor
        let mask: Tensor
        let tokenCount: Int
    }

    private struct Envelope: Codable { let payload: Data; let sha256: String }
    // Identifies stored text/diffusion tensors. A decoder-only placement change
    // must not invalidate completed diffusion work from an earlier app build.
    static let configuration = "fp32-stdit-vae-t5-int8-rflow30-leap20-cfg7-tdtm10-latent20-v1"

    public static func summary(at url: URL) throws -> Summary {
        let state = try read(at: url)
        return Summary(request: state.request, completedSteps: state.completedSteps)
    }

    static func read(at url: URL) throws -> State {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size < 32 * 1024 * 1024 else { throw GenerationError.invalidCheckpoint }
        let decoder = PropertyListDecoder()
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: url))
        guard digest(envelope.payload) == envelope.sha256 else { throw GenerationError.invalidCheckpoint }
        let state = try decoder.decode(State.self, from: envelope.payload)
        guard state.version == 1, state.modelRevision == MOVDModel.revision,
              state.configuration == configuration, (0...21).contains(state.completedSteps),
              (1...64).contains(state.tokenCount),
              state.request == (try GenerationRequest(prompt: state.request.prompt, duration: state.request.duration, seed: state.request.seed)) else {
            throw GenerationError.invalidCheckpoint
        }
        return state
    }

    static func write(_ state: State, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(state)
        let data = try encoder.encode(Envelope(payload: payload, sha256: digest(payload)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
