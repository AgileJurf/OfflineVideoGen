import CoreML
import Foundation

/// Native port of the hybrid checkpoint's three-stage autoregressive flow.
/// This is experimental and is not selected by the shipping MOVD generation UI.
struct NeodragonDenoiser {
    let runner: ModelRunner
    let maximumLatentFrames: Int

    func generate(firstFrame: MLShapedArray<Float32>, encoding: NeodragonTextEncoding,
                  latentFrames: Int, seed: UInt64,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> MLShapedArray<Float32> {
        guard firstFrame.shape == [1, 16, 1, 40, 64], firstFrame.scalars.allSatisfy(\.isFinite),
              (7...28).contains(latentFrames), latentFrames <= maximumLatentFrames,
              encoding.context.shape == [1, 128, 1536], encoding.pooled.shape == [1, 2048],
              (1...128).contains(encoding.tokenCount) else { throw GenerationError.invalidTensor }
        var random = NeodragonRandom(seed: seed)
        let plane = 40 * 64
        let noise = random.normals(count: 16 * latentFrames * plane)
        let scheduler = NeodragonScheduler()
        var history = [NeodragonGrid(values: firstFrame.scalars, height: 40, width: 64)]
        var recentUnitSeconds: [Double] = []
        var timeEmbeddings: [MLFeatureValue] = []
        for stage in scheduler.stages {
            let result = try await runner.predict("time_embedding", [
                "timestep": feature(.init(scalars: [stage.timestep], shape: [1])), "pooled": feature(encoding.pooled)])
            let time = try tensor(result, "time_embedding")
            guard time.shape == [1, 1536], time.scalars.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
            timeEmbeddings.append(feature(time))
        }
        for unit in 1..<latentFrames {
            try await runner.checkpoint()
            let unitStart = ProcessInfo.processInfo.systemUptime
            let pausedAtStart = runner.control.totalPausedSeconds
            var initial = [Float32](repeating: 0, count: 16 * plane)
            for channel in 0..<16 {
                for pixel in 0..<plane { initial[channel * plane + pixel] = noise[(channel * latentFrames + unit) * plane + pixel] }
            }
            var latent = NeodragonGrid(values: initial, height: 40, width: 64)
                .downsample(variancePreserving: true).downsample(variancePreserving: true)
            let pastPyramids = history.map(\.pyramid)
            for stage in 0..<3 {
                if stage > 0 { latent = upsample(latent, stage: scheduler.stages[stage], random: &random) }
                var inputs: [(grid: NeodragonGrid, scale: Int)] = history.indices.map { index in
                    let scale = max(stage - (history.count - 1 - index), 0)
                    return (pastPyramids[index][scale], scale)
                }
                inputs.append((latent, stage))
                var patches: [MLShapedArray<Float32>] = []
                for input in inputs {
                    let result = try await runner.predict("patch_s\(input.scale)_p\(stage)", [
                        "latent": feature(.init(scalars: input.grid.values, shape: [1, 16, 1, input.grid.height, input.grid.width]))])
                    let patch = try tensor(result, "hidden")
                    guard patch.shape == [1, input.grid.height * input.grid.width / 4, 1536], patch.scalars.allSatisfy(\.isFinite) else {
                        throw GenerationError.invalidTensor
                    }
                    patches.append(patch)
                }
                let layout = NeodragonAttentionLayout(lengths: patches.map { $0.shape[1] }, textTokenCount: encoding.tokenCount)
                let combined = MLShapedArray(concatenating: patches, alongAxis: 1)
                var hidden = feature(combined)
                var context = feature(encoding.context)
                let mask = feature(.init(scalars: layout.mask, shape: [1, 1, layout.totalTokens, layout.totalTokens]))
                let cosine = feature(.init(scalars: layout.cosine, shape: [1, layout.totalTokens, 1, 32]))
                let sine = feature(.init(scalars: layout.sine, shape: [1, layout.totalTokens, 1, 32]))
                for block in 0..<18 {
                    let result = try await runner.predict(String(format: "transformer_block_%02d", block), [
                        "hidden": hidden, "context": context, "time_embedding": timeEmbeddings[stage],
                        "attention_mask": mask, "rope_cos": cosine, "rope_sin": sine])
                    let next = try tensor(result, "hidden_out")
                    guard next.shape == [1, layout.imageTokens, 1536], next.scalars.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
                    hidden = feature(next)
                    if block < 17 {
                        let nextContext = try tensor(result, "context_out")
                        guard nextContext.shape == [1, 128, 1536], nextContext.scalars.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
                        context = feature(nextContext)
                    }
                    let completed = Double((unit - 1) * 54 + stage * 18 + block + 1)
                    let elapsed = ProcessInfo.processInfo.systemUptime - unitStart - (runner.control.totalPausedSeconds - pausedAtStart)
                    let estimate: GenerationEstimate? = recentUnitSeconds.isEmpty ? nil : .init(
                        seconds: max(0, recentUnitSeconds.reduce(0, +) / Double(recentUnitSeconds.count) * Double(latentFrames - unit) - elapsed),
                        scope: "Motion estimate", isFullJob: false)
                    progress(.init(0.2 + 0.64 * completed / Double((latentFrames - 1) * 54),
                                   "Generating Neodragon motion · unit \(unit) of \(latentFrames - 1) · stage \(stage + 1) · block \(block + 1) of 18", estimate: estimate))
                }
                guard let array = hidden.multiArrayValue else { throw GenerationError.invalidTensor }
                let currentTokens = latent.height * latent.width / 4
                let tail = Array(MLShapedArray<Float32>(converting: array).scalars.suffix(currentTokens * 1536))
                let result = try await runner.predict("output_s\(stage)", [
                    "hidden": feature(.init(scalars: tail, shape: [1, currentTokens, 1536])), "time_embedding": timeEmbeddings[stage]])
                let flow = try tensor(result, "predicted_flow")
                guard flow.shape == [1, 16, 1, latent.height, latent.width] else { throw GenerationError.invalidTensor }
                latent = .init(values: try scheduler.step(sample: latent.values, predictedFlow: flow.scalars), height: latent.height, width: latent.width)
                runner.benchmark?.record("diffusion_step_completed", fields: ["completedSteps": String(4 + (unit - 1) * 3 + stage + 1), "stage": "motion"])
            }
            history.append(latent)
            recentUnitSeconds.append(max(0, ProcessInfo.processInfo.systemUptime - unitStart - (runner.control.totalPausedSeconds - pausedAtStart)))
            recentUnitSeconds = Array(recentUnitSeconds.suffix(2))
            runner.benchmark?.record("neodragon_unit_completed", fields: ["latentUnits": String(history.count), "totalLatentUnits": String(latentFrames)])
        }
        let frames = history.map { MLShapedArray<Float32>(scalars: $0.values, shape: [1, 16, 1, 40, 64]) }
        return MLShapedArray(concatenating: frames, alongAxis: 2)
    }

    private func upsample(_ latent: NeodragonGrid, stage: NeodragonScheduler.Stage,
                          random: inout NeodragonRandom) -> NeodragonGrid {
        let larger = latent.nearestUpsample()
        var result = larger.values
        // Cholesky of the original Float32 covariance (gamma = 1/3), recorded
        // independently in tools/neodragon/fixtures/block-noise.json.
        let lower: [[Float32]] = [[1, 0, 0, 0], [-0.3333333432674408, 0.9428090453147888, 0, 0],
            [-0.3333333432674408, -0.471404492855072, 0.8164966106414795, 0],
            [-0.3333333432674408, -0.471404492855072, -0.8164964914321899, 0.00040744792204350233]]
        for channel in 0..<16 {
            for y in stride(from: 0, to: larger.height, by: 2) {
                for x in stride(from: 0, to: larger.width, by: 2) {
                    let normals = random.normals(count: 4)
                    for row in 0..<4 {
                        let noise = zip(lower[row], normals).reduce(Float32(0)) { $0 + $1.0 * $1.1 }
                        let index = channel * larger.height * larger.width + (y + row / 2) * larger.width + x + row % 2
                        result[index] = stage.upsampleSignal * result[index] + stage.upsampleNoise * noise
                    }
                }
            }
        }
        return .init(values: result, height: larger.height, width: larger.width)
    }
}
