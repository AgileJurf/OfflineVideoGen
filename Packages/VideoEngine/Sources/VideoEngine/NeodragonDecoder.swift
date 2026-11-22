import CoreML
import Foundation

/// Experimental native decoder for the separately converted Neodragon package.
/// Exposed history preserves the upstream causal decoder across latent frames.
/// No app selection or download is enabled by the presence of this component.
final class NeodragonDecoder {
    private let runner: ModelRunner
    private var memories: [[MLFeatureValue]]
    private var producedFrames = 0
    private static let memoryShapes = [[1, 256, 40, 64], [1, 128, 80, 128], [1, 64, 160, 256]]
    private static let outputShapes = [[1, 256, 40, 64], [2, 128, 80, 128], [2, 64, 160, 256], [2, 3, 320, 512]]

    init(runner: ModelRunner) {
        self.runner = runner
        memories = Self.memoryShapes.map { shape in
            (0..<3).map { _ in feature(MLShapedArray<Float32>(repeating: 0, shape: shape)) }
        }
    }

    /// Input is normalized diffusion latents [1,16,T,40,64]. Only real decoded
    /// frames are sent to the existing encoder; seven causal warm-up frames drop.
    func decode(_ latents: MLShapedArray<Float32>, output: URL, exportFrames: Int,
                progress: @escaping @Sendable (GenerationProgress) -> Void) async throws {
        guard latents.shape.count == 5 else { throw GenerationError.invalidTensor }
        let nativeFrames = latents.shape[2] * 8 - 7
        guard exportFrames > 0, exportFrames <= nativeFrames, nativeFrames - exportFrames < 8 else {
            throw GenerationError.invalidTensor
        }
        let encoder = try VideoEncoder(output: output, width: 512, height: 320, fps: 24)
        do {
            try await frames(latents, progress: progress) { frame in
                try await encoder.append(frame, limit: exportFrames)
            }
            try await encoder.finish(expectedFrames: exportFrames)
        } catch {
            encoder.cancel()
            throw error
        }
    }

    /// Streams finite RGB tensors before lossy encoding. This also permits
    /// numerical comparison with the original decoder without storing a movie.
    func frames(_ latents: MLShapedArray<Float32>,
                progress: @escaping @Sendable (GenerationProgress) -> Void,
                receive: (MLShapedArray<Float32>) async throws -> Void) async throws {
        guard latents.shape.count == 5, (1...28).contains(latents.shape[2]),
              latents.shape == [1, 16, latents.shape[2], 40, 64], producedFrames == 0 else { throw GenerationError.invalidTensor }
        let latentCount = latents.shape[2]
        let values = latents.scalars
        guard values.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        let plane = 40 * 64
        let started = ProcessInfo.processInfo.systemUptime
        let pausedAtStart = runner.control.totalPausedSeconds
        for time in 0..<latentCount {
            try await runner.checkpoint()
            let scale: Float32 = time == 0 ? 0.5430 : 0.3031
            let shift: Float32 = time == 0 ? 0.1490 : -0.2343
            var input = [Float32](repeating: 0, count: 16 * plane)
            for channel in 0..<16 {
                for pixel in 0..<plane {
                    input[channel * plane + pixel] = values[(channel * latentCount + time) * plane + pixel] / scale + shift
                }
            }
            try await advance(stage: 0, array: .init(scalars: input, shape: [1, 16, 40, 64]), receive: receive)
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - started - (runner.control.totalPausedSeconds - pausedAtStart))
            let estimate = GenerationEstimate(seconds: elapsed / Double(time + 1) * Double(latentCount - time - 1),
                                              scope: "Estimated time remaining", isFullJob: true)
            progress(.init(0.85 + Double(time + 1) / Double(latentCount) * 0.14,
                           "Decoding Neodragon video · \(time + 1) of \(latentCount)", estimate: estimate))
        }
        guard producedFrames == latentCount * 8 else { throw GenerationError.invalidTensor }
    }

    private func advance(stage: Int, array: MLShapedArray<Float32>,
                         receive: (MLShapedArray<Float32>) async throws -> Void) async throws {
        var inputs = ["value": feature(array)]
        if stage < 3 {
            for index in 0..<3 { inputs["past\(index)"] = memories[stage][index] }
        }
        let result = try await runner.predict(NeodragonModel.decoderNames[stage], inputs)
        let output = try tensor(result, "value_out")
        guard output.shape == Self.outputShapes[stage] else { throw GenerationError.invalidTensor }
        let scalars = output.scalars
        guard scalars.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        if stage < 3 {
            for index in 0..<3 {
                let memory = try tensor(result, "past\(index)_out")
                guard memory.shape == Self.memoryShapes[stage], memory.scalars.allSatisfy(\.isFinite) else {
                    throw GenerationError.invalidTensor
                }
                memories[stage][index] = feature(memory)
            }
        }
        let rows = output.shape[0]
        let count = scalars.count / rows
        for row in 0..<rows {
            let frame = Array(scalars[row * count..<(row + 1) * count])
            if stage < 3 {
                var shape = output.shape; shape[0] = 1
                try await advance(stage: stage + 1, array: .init(scalars: frame, shape: shape), receive: receive)
            } else {
                if producedFrames >= 7 {
                    try await receive(.init(scalars: frame, shape: [1, 3, 1, 320, 512]))
                }
                producedFrames += 1
            }
        }
    }
}
