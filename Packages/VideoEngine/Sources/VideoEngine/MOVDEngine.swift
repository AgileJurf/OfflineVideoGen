import CoreML
import Foundation
import Hub
import Tokenizers

/// Native temporal diffusion based on EAI Lab's MIT-licensed MOVD implementation.
/// This port has not yet passed real-model parity or physical-iPhone validation.
public actor MOVDEngine {
    public init() {}

    public func generate(_ request: GenerationRequest, modelsAt directory: URL, output: URL,
                         benchmark: BenchmarkLog? = nil,
                         progress: @Sendable (GenerationProgress) -> Void) async throws -> GenerationMetrics {
        try MOVDModel.validateInstallation(at: directory)
        let started = ProcessInfo.processInfo.systemUptime
        let runner = ModelRunner(directory: directory, benchmark: benchmark)
        try runner.checkpoint()
        progress(.init(0.01, "Encoding your prompt"))
        let encoding = try encode(request.prompt, runner: runner)
        let latent = try await denoise(request, encoding: encoding, runner: runner, progress: progress)
        progress(.init(0.8, "Decoding video frames"))
        try await decode(latent, request: request, output: output, runner: runner, progress: progress)
        #if targetEnvironment(simulator)
        let environment = "simulator-cpu"
        #else
        let environment = "physical-device-cpu-gpu"
        #endif
        progress(.init(1, "Video saved"))
        return GenerationMetrics(elapsedSeconds: ProcessInfo.processInfo.systemUptime - started,
                                 peakSampledMemoryBytes: runner.peakMemory,
                                 thermalStates: runner.thermalStates.sorted(), environment: environment,
                                 modelRevision: MOVDModel.revision)
    }

    private struct Encoding {
        let hidden: MLShapedArray<Float32>
        let unconditional: MLShapedArray<Float32>
        let mask: MLShapedArray<Float32>
        let count: Int
    }

    static func promptTokenIDs(_ prompt: String) throws -> [Int] {
        func config(_ name: String) throws -> Config {
            guard let resource = Bundle.module.url(forResource: name, withExtension: nil) else {
                throw GenerationError.modelMissing(name)
            }
            let data = try Data(contentsOf: resource)
            guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GenerationError.incompatibleModel("tokenizer configuration")
            }
            object["tokenizer_class"] = "T5Tokenizer"
            return Config(object)
        }
        let tokenizer = try PreTrainedTokenizer(tokenizerConfig: config("tokenizer_config.json"),
                                               tokenizerData: config("tokenizer.json"))
        let tokens = tokenizer.tokenize(text: prompt)
        // Attention masks scale with prompt length. Reject rather than silently changing the prompt.
        guard tokens.count <= 63 else { throw GenerationError.promptTooLong }
        return tokens.map { tokenizer.convertTokenToId($0) ?? 0 } + [tokenizer.eosTokenId ?? 1]
    }

    private func encode(_ prompt: String, runner: ModelRunner) throws -> Encoding {
        let ids = try Self.promptTokenIDs(prompt)
        let padded = ids + Array(repeating: 0, count: 300 - ids.count)
        let attention = MLShapedArray<Float32>(scalars: (0..<300).map { $0 < ids.count ? 0 : -Float32.greatestFiniteMagnitude }, shape: [1, 1, 1, 300])
        let embedded = try runner.predict("t5embed-tokens", ["input_ids": feature(.init(scalars: padded.map(Float32.init), shape: [1, 300]))])
        var hidden = try value(embedded, "output")
        var position: MLFeatureValue?
        var unconditional: MLShapedArray<Float32>?
        for index in 0..<24 {
            var input = ["hidden_states": hidden, "attention_mask": feature(attention)]
            if index == 0 {
                input["y_embedding"] = feature(.init(repeating: 1, shape: [300, 4096]))
            } else {
                guard let position else { throw GenerationError.incompatibleModel("T5 position bias") }
                input["position_bias"] = position
            }
            let result = try runner.predict("t5block-layer\(index)", input)
            hidden = try value(result, "output_hidden_states")
            if index == 0 {
                position = try value(result, "output_position_bias")
                unconditional = try tensor(result, "yNull")
            }
        }
        let norm = try runner.predict("t5final-layer-norm", ["input": hidden])
        guard let unconditional else { throw GenerationError.incompatibleModel("unconditional text embedding") }
        return Encoding(hidden: try tensor(norm, "output").expandingShape(at: 0),
                        unconditional: unconditional.expandingShape(at: 0).expandingShape(at: 0),
                        mask: .init(scalars: (0..<300).map { $0 < ids.count ? 1 : 0 }, shape: [1, 300]), count: ids.count)
    }

    private func denoise(_ request: GenerationRequest, encoding: Encoding, runner: ModelRunner,
                         progress: @Sendable (GenerationProgress) -> Void) async throws -> MLShapedArray<Float32> {
        let side = request.width / 8
        let latentFrames = 20 // The released VAE decodes four groups of five latents into 68 frames.
        let tokenCount = latentFrames * side * side / 4
        var latent = MLTensor(randomNormal: [1, 4, latentFrames, side, side], seed: request.seed, scalarType: Float32.self)
        let text = MLShapedArray(concatenating: [encoding.hidden, encoding.unconditional], alongAxis: 0)
        let steps = 30
        let leapStep = 20
        let mergeSteps = 10
        let ratio = Float32(request.width * request.height).squareRoot() / 512 * Float32(latentFrames).squareRoot()
        let timesteps: [Float32] = (0..<steps).map {
            let time = (1000 * (1 - Float32($0) / Float32(steps))).rounded() / 1000
            return 1000 * ratio * time / (1 + (ratio - 1) * time)
        }
        // The masked image-to-video path is intentionally absent: every latent is generated from noise.
        for index in 0...leapStep {
            try runner.checkpoint()
            progress(.init(0.12 + 0.66 * Double(index) / Double(leapStep + 1), "Generating motion · step \(index + 1) of \(leapStep + 1)"))
            let z = await MLTensor(concatenating: [latent, latent], alongAxis: 0).shapedArray(of: Float32.self)
            func scalar(_ x: Float32) -> MLFeatureValue { feature(.init(scalars: [x], shape: [1])) }
            let first = try runner.predict("stdit3_part1", [
                "z_in": feature(z), "t": feature(.init(scalars: [timesteps[index], timesteps[index]], shape: [2])),
                "y": feature(text), "mask": feature(encoding.mask), "fps": scalar(Float32(request.framesPerSecond)),
                "height": scalar(Float32(request.height)), "width": scalar(Float32(request.width)),
                "padH": scalar(0), "padW": scalar(0)
            ])
            let merged = index < mergeSteps
            let attention = attentionMask(tokens: encoding.count, spatialTokens: merged ? tokenCount / 2 : tokenCount)
            // Part 1 declares T as int32; the released blocks require float32 [1].
            let temporalCount = try tensor(first, "T").scalars
            guard temporalCount.count == 1 else { throw GenerationError.incompatibleModel("STDiT temporal count") }
            let temporalFeature = feature(MLShapedArray<Float32>(scalars: temporalCount, shape: [1]))
            var x = try value(first, "x")
            for block in 0..<28 {
                let next = try runner.predict("stdit3_\(merged ? "TDTM" : "ST")_\(block)", [
                    "x": x, "y": try value(first, "outY"), "attn": feature(attention),
                    "t_mlp": try value(first, "t_mlp"), "T": temporalFeature
                ])
                x = try value(next, "output")
            }
            let last = try runner.predict("stdit3_part2", ["z_in": feature(z), "x": x,
                "t": try value(first, "outT"), "padH": scalar(0), "padW": scalar(0)])
            let prediction = MLTensor(try tensor(last, "output"))
            guard prediction.shape == [2, 8, latentFrames, side, side] else {
                throw GenerationError.incompatibleModel("STDiT output shape \(prediction.shape)")
            }
            let velocity = prediction.split(sizes: [4, 4], alongAxis: 1)[0].split(sizes: [1, 1], alongAxis: 0)
            let guided = velocity[1] + 7 * (velocity[0] - velocity[1])
            let delta = index == leapStep ? timesteps[index] : timesteps[index] - timesteps[index + 1]
            // Materialize each step to bound the MLTensor computation graph.
            let next = await (latent + guided * (delta / 1000)).shapedArray(of: Float32.self)
            latent = MLTensor(next)
        }
        return await latent.shapedArray(of: Float32.self)
    }

    private func attentionMask(tokens: Int, spatialTokens: Int) -> MLShapedArray<Float32> {
        let zeros = MLShapedArray<Float32>(repeating: 0, shape: [spatialTokens, tokens])
        let masked = MLShapedArray<Float32>(repeating: -Float32.greatestFiniteMagnitude, shape: [spatialTokens, tokens])
        let top = MLShapedArray(concatenating: [zeros, masked], alongAxis: 1)
        let bottom = MLShapedArray(concatenating: [masked, zeros], alongAxis: 1)
        let mask = MLShapedArray(concatenating: [top, bottom], alongAxis: 0).expandingShape(at: 0).expandingShape(at: 0)
        return MLShapedArray(concatenating: Array(repeating: mask, count: 16), alongAxis: 1)
    }

    private func decode(_ latent: MLShapedArray<Float32>, request: GenerationRequest, output: URL,
                        runner: ModelRunner, progress: @Sendable (GenerationProgress) -> Void) async throws {
        let writer = try VideoEncoder(output: output, width: request.width, height: request.height, fps: request.framesPerSecond)
        var finished = false
        defer { if !finished { writer.cancel() } }
        let groups = MLTensor(latent).split(count: 4, alongAxis: 2)
        var temporal = [MLShapedArray<Float32>]()
        for group in groups {
            var chunk = await group.shapedArray(of: Float32.self)
            for name in MOVDModel.temporalParts {
                let result = try runner.predict(name, ["latents": feature(chunk)], cpuOnly: name != "vae_temporal_part2_2")
                chunk = try tensor(result, "output")
            }
            temporal.append(chunk)
        }
        let spatialInput = MLShapedArray(concatenating: temporal, alongAxis: 2)
        guard spatialInput.shape.count == 5, spatialInput.shape[2] == 68 else {
            throw GenerationError.incompatibleModel("VAE did not decode 68 frames")
        }
        let spatialChunks = MLTensor(spatialInput).split(count: 17, alongAxis: 2)
        for (index, group) in spatialChunks.enumerated() {
            if writer.frameCount >= request.frameCount { break }
            var chunk = await group.shapedArray(of: Float32.self)
            for name in MOVDModel.spatialParts {
                let cpu = name == "vae_spatial_part3_3" || name.hasPrefix("vae_spatial_part3_4")
                let result = try runner.predict(name, ["latents": feature(chunk)], cpuOnly: cpu)
                chunk = try tensor(result, "output")
            }
            try await writer.append(chunk, limit: request.frameCount)
            progress(.init(0.8 + 0.19 * Double(index + 1) / 17, "Saving generated frames"))
        }
        try await writer.finish(expectedFrames: request.frameCount)
        finished = true
    }
}
