import CoreML
import Foundation

public enum NeodragonMotionComputePolicy: String, Codable, Sendable {
    case originalCPUAndGPU = "motion-cpu-gpu-v1"
    case cpuCompatibility = "motion-cpu-compatibility-v1"

    public var profileID: String {
        self == .cpuCompatibility ? "neodragon-hybrid-motion-cpu-v2" : "neodragon-hybrid-experimental-v1"
    }
}

public struct NeodragonGenerationRequest: Codable, Sendable, Equatable {
    public let prompt: String
    public let duration: Int
    public let seed: UInt64
    public let style: VisualStyle
    public let modelPrompt: String?
    public var effectivePrompt: String { modelPrompt ?? style.applying(to: prompt) }

    public init(prompt: String, duration: Int, seed: UInt64, style: VisualStyle = .default, modelPrompt: String? = nil) throws {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GenerationError.invalidPrompt }
        guard clean.count <= 500 else {
            throw GenerationError.incompatibleModel("Use a prompt up to 500 characters. The complete scene and style must also fit the installed model’s token limits.")
        }
        _ = try NeodragonModel.geometry(seconds: duration)
        guard (modelPrompt?.count ?? 0) <= 2500 else { throw GenerationError.promptTooLong }
        self.prompt = clean; self.duration = duration; self.seed = seed; self.style = style; self.modelPrompt = modelPrompt
    }
}

/// Genuine local video diffusion. New checkpoints and sampler changes require device validation.
public actor NeodragonEngine {
    public init() {}

    public static func promptTokenCount(_ prompt: String, modelsAt directory: URL) throws -> Int {
        for name in ["tokenizer", "tokenizer_2", "ssd_1b_tokenizer", "ssd_1b_tokenizer_2"] {
            _ = try NeodragonCLIPTokenizer(directory: directory.appendingPathComponent(name)).encode(prompt)
        }
        return try NeodragonTextEncoder(runner: ModelRunner(directory: directory)).t5Tokens(prompt).count
    }

    public struct Installation: Codable, Sendable {
        public let schemaVersion: Int
        public let modelID: String
        public let sourceRevision: String
        public let weightsRevision: String
        public let conversionVersion: Int
        public let maximumSeconds: Int
        public let modelNames: [String]
    }

    public static func validateInstallation(at directory: URL) throws -> Installation {
        let url = directory.appendingPathComponent("neodragon-runtime.json")
        let data = try Data(contentsOf: url)
        guard data.count <= 100_000 else { throw GenerationError.invalidTensor }
        let installed = try JSONDecoder().decode(Installation.self, from: data)
        guard installed.schemaVersion == 1, installed.conversionVersion == 1,
              installed.modelID == NeodragonModel.identifier,
              installed.sourceRevision == NeodragonModel.sourceRevision,
              installed.weightsRevision == NeodragonModel.weightsRevision,
              (2...9).contains(installed.maximumSeconds), (60...250).contains(installed.modelNames.count),
              Set(installed.modelNames).count == installed.modelNames.count else {
            throw GenerationError.incompatibleModel("Neodragon package metadata")
        }
        for name in installed.modelNames {
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else {
                throw GenerationError.incompatibleModel("Neodragon partition name")
            }
            let path = directory.appendingPathComponent(name + ".mlmodelc")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let files = try? FileManager.default.contentsOfDirectory(atPath: path.path), !files.isEmpty else {
                throw GenerationError.modelMissing(name)
            }
        }
        let pipelines = ["text_encoder", "text_encoder_2", "ssd_1b_text_encoder", "ssd_1b_text_encoder_2", "ssd_1b_unet", "ssd_1b_vae"]
        var supportFiles = pipelines.map { $0 + "_pipeline.json" }
        for tokenizer in ["tokenizer", "tokenizer_2", "ssd_1b_tokenizer", "ssd_1b_tokenizer_2"] {
            supportFiles += ["vocab.json", "merges.txt", "tokenizer_config.json", "special_tokens_map.json"].map { tokenizer + "/" + $0 }
        }
        supportFiles += ["tokenizer_3/sentencepiece-native.json", "THIRD-PARTY-NOTICES.txt"]
        for name in supportFiles {
            let url = directory.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size < 6_000_000 else {
                throw GenerationError.modelMissing("Neodragon support file " + name)
            }
        }
        return installed
    }

    public func generate(_ request: NeodragonGenerationRequest, modelsAt directory: URL, output: URL,
                         benchmark: BenchmarkLog? = nil, control: GenerationControl = GenerationControl(),
                         computeOnCPUOnly: Bool = false,
                         motionComputePolicy: NeodragonMotionComputePolicy = .originalCPUAndGPU,
                         attentionVariantAt variantDirectory: URL? = nil,
                         progress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GenerationMetrics {
        let installed = try Self.validateInstallation(at: directory)
        var overrides: [String: URL] = [:]
        if let variantDirectory {
            let variant = try NeodragonAttentionVariant.validateInstallation(at: variantDirectory)
            guard motionComputePolicy == .cpuCompatibility,
                  request.duration <= NeodragonAttentionVariant.deviceTrialMaximumSeconds,
                  installed.maximumSeconds == variant.maximumSeconds,
                  Set(variant.modelNames).isSubset(of: Set(installed.modelNames)) else {
                throw GenerationError.incompatibleModel("This attention trial requires the nine-second base package, CPU motion compatibility, and a duration of at most five seconds.")
            }
            overrides = Dictionary(uniqueKeysWithValues: variant.modelNames.map { ($0, variantDirectory.appendingPathComponent($0 + ".mlmodelc")) })
        }
        let profileID = variantDirectory == nil ? motionComputePolicy.profileID : NeodragonAttentionVariant.profileID
        guard request.duration <= installed.maximumSeconds else {
            throw GenerationError.incompatibleModel("This Neodragon package supports up to \(installed.maximumSeconds) seconds. Install the verified longer-duration package first.")
        }
        let geometry = try NeodragonModel.geometry(seconds: request.duration)
        let started = ProcessInfo.processInfo.systemUptime
        let runner = ModelRunner(directory: directory, benchmark: benchmark, control: control,
                                 retainingSmallModels: Set(NeodragonModel.decoderNames), forceCPUOnly: computeOnCPUOnly,
                                 modelOverrides: overrides)
        benchmark?.record("neodragon_execution_policy", fields: ["motionComputePolicy": motionComputePolicy.rawValue,
            "forceAllComponentsCPUOnly": String(computeOnCPUOnly), "profileID": profileID,
            "motionTensorTransfer": "independent-float32-v1",
            "attentionVariant": variantDirectory == nil ? "original-24-heads" : NeodragonAttentionVariant.identifier])
        try await runner.checkpoint()
        // Validate every tokenizer before expensive work, with no truncation.
        _ = try Self.promptTokenCount(request.effectivePrompt, modelsAt: directory)
        let first = try await NeodragonFirstFrame(runner: runner).generate(prompt: request.effectivePrompt, seed: request.seed, progress: progress)
        progress(.init(0.18, "Encoding the Neodragon motion prompt"))
        let encoding = try await NeodragonTextEncoder(runner: runner).video(request.effectivePrompt)
        let maximum = try NeodragonModel.geometry(seconds: installed.maximumSeconds).latentFrames
        let latents = try await NeodragonDenoiser(runner: runner, maximumLatentFrames: maximum,
            motionComputePolicy: motionComputePolicy).generate(
            firstFrame: first, encoding: encoding, latentFrames: geometry.latentFrames,
            seed: request.seed &+ 0x4E454F445241474F, progress: progress)
        try await NeodragonDecoder(runner: runner).decode(latents, output: output, exportFrames: geometry.exportFrames, progress: progress)
        #if targetEnvironment(simulator)
        let environment = "simulator-cpu"
        #elseif os(macOS)
        let environment = computeOnCPUOnly ? "macos-cpu" : "macos-cpu-gpu"
        #else
        let environment = computeOnCPUOnly ? "physical-device-cpu" : "physical-device-cpu-gpu"
        #endif
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        benchmark?.record("neodragon_generation_completed", fields: ["wallSecondsIncludingPauses": String(elapsed),
            "pausedSeconds": String(control.totalPausedSeconds), "latentFrames": String(geometry.latentFrames),
            "nativeFrames": String(geometry.nativeFrames), "exportFrames": String(geometry.exportFrames),
            "randomGenerator": "SplitMix64-BoxMuller-v1; reproducible locally, not PyTorch seed-equivalent"])
        progress(.init(1, "Video saved"))
        return GenerationMetrics(elapsedSeconds: elapsed,
            peakSampledMemoryBytes: max(runner.peakMemory, benchmark?.peakSampledMemoryBytes ?? 0),
            thermalStates: runner.thermalStates.sorted(), environment: environment,
            modelRevision: NeodragonModel.weightsRevision, pausedSeconds: control.totalPausedSeconds,
            decoderExecutionPolicy: "neodragon-streaming-causal-v1", modelLoadSeconds: runner.modelLoadSeconds,
            modelPredictionSeconds: runner.modelPredictionSeconds,
            diffusionEvaluations: 4 + (geometry.latentFrames - 1) * 3,
            profileID: profileID, precision: "Mixed FP16/FP32; T5 Float32")
    }
}
