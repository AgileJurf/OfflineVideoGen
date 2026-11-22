import CoreML
import Foundation

/// Genuine SSD-1B text-to-image diffusion, followed by the original image-to-
/// latent bridge. The hybrid video checkpoint expects this first-frame path.
struct NeodragonFirstFrame {
    let runner: ModelRunner

    func generate(prompt: String, seed: UInt64,
                  progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> MLShapedArray<Float32> {
        progress(.init(0.01, "Encoding Neodragon first-image prompt"))
        let encoding = try await NeodragonTextEncoder(runner: runner).firstFrame(prompt)
        var random = NeodragonRandom(seed: seed)
        let count = 4 * 80 * 128
        var sample = random.normals(count: count)
        let scheduler = NeodragonImageScheduler()
        let graph = NeodragonImageGraph(runner: runner)
        let conditions: [String: MLFeatureValue] = ["context": feature(encoding.hidden), "pooled": feature(encoding.pooled),
            "time_ids": feature(.init(scalars: [640, 1024, 0, 0, 640, 1024], shape: [1, 6]))]
        for (index, step) in scheduler.steps.enumerated() {
            progress(.init(0.03 + Double(index) * 0.025, "Generating first image · step \(index + 1) of 4"))
            var inputs = conditions
            inputs["sample"] = feature(.init(scalars: sample, shape: [1, 4, 80, 128]))
            inputs["timestep"] = feature(.init(scalars: [step.timestep], shape: [1]))
            let prediction = try await graph.run(component: "ssd_1b_unet", inputs: inputs)
            let noise = index < 3 ? random.normals(count: count) : Array(repeating: Float32(0), count: count)
            sample = try scheduler.advance(index: index, sample: sample, prediction: prediction.scalars, noise: noise)
            runner.benchmark?.record("diffusion_step_completed", fields: ["completedSteps": String(index + 1), "stage": "first-image"])
        }
        progress(.init(0.14, "Decoding the first image"))
        let image = try await graph.run(component: "ssd_1b_vae", inputs: ["latent": feature(.init(scalars: sample, shape: [1, 4, 80, 128]))])
        let input = try NeodragonImageProcessing.videoInput(decoded: image.scalars)
        progress(.init(0.17, "Preparing image conditioning for motion"))
        let encoded = try await runner.predict("image_encoder", ["image": feature(.init(scalars: input, shape: [1, 3, 1, 320, 512]))])
        let moments = try tensor(encoded, "moments")
        guard moments.shape == [1, 32, 1, 40, 64] else { throw GenerationError.invalidTensor }
        let values = moments.scalars
        guard values.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        let latentCount = 16 * 40 * 64
        let posteriorNoise = random.normals(count: latentCount)
        let latent = (0..<latentCount).map { index -> Float32 in
            let logVariance = min(max(values[latentCount + index], -30), 20)
            let sample = values[index] + exp(0.5 * logVariance) * posteriorNoise[index]
            return (sample - 0.1490) * 0.5430
        }
        guard latent.allSatisfy(\.isFinite) else { throw GenerationError.invalidTensor }
        return .init(scalars: latent, shape: [1, 16, 1, 40, 64])
    }
}
