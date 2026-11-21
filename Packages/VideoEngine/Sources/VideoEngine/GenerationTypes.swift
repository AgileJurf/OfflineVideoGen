import Foundation

public struct GenerationRequest: Codable, Sendable, Equatable {
    public let prompt: String
    public let duration: Int
    public let seed: UInt64
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int

    public init(prompt: String, duration: Int, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) throws {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw GenerationError.invalidPrompt }
        guard clean.count <= 500 else { throw GenerationError.promptTooLong }
        guard (2...5).contains(duration) else { throw GenerationError.invalidDuration }
        self.prompt = clean
        self.duration = duration
        self.seed = seed
        width = 256
        height = 256
        framesPerSecond = 12
    }

    public var frameCount: Int { duration * framesPerSecond }
}

public struct GenerationProgress: Sendable {
    public let fraction: Double
    public let message: String
    public let estimate: GenerationEstimate?
    public init(_ fraction: Double, _ message: String, estimate: GenerationEstimate? = nil) {
        self.fraction = min(1, max(0, fraction))
        self.message = message
        self.estimate = estimate
    }
}

public struct GenerationEstimate: Sendable {
    public let seconds: Double
    public let scope: String
    public let isFullJob: Bool

    public var displayText: String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return "\(scope): about \(minutes) min" + (isFullJob ? "" : " · Total finish time is still being estimated")
    }
}

public struct GenerationMetrics: Codable, Sendable {
    /// Wall time for this invocation only; includes cooling and checkpoint writes.
    public var elapsedSeconds: Double
    public var peakSampledMemoryBytes: UInt64
    public var thermalStates: [String]
    public var environment: String
    public var modelRevision: String
    public var pausedSeconds: Double? = nil
    public var resumedFromStep: Int? = nil
    public var decoderExecutionPolicy: String? = nil
}

public enum GenerationError: LocalizedError {
    case invalidPrompt, promptTooLong, invalidDuration, modelMissing(String)
    case incompatibleModel(String), memoryPressure, tooHot, interrupted, insufficientStorage
    case encodingFailed(String), invalidTensor, invalidCheckpoint

    public var errorDescription: String? {
        switch self {
        case .invalidPrompt: return "Describe the motion you want to generate."
        case .promptTooLong: return "Use a shorter prompt (up to 500 characters and 63 model tokens)."
        case .invalidDuration: return "Choose a duration from 2 to 5 seconds."
        case .modelMissing(let name): return "The model is incomplete (\(name)). Reinstall the model in Setup."
        case .incompatibleModel(let detail): return "This model cannot run with the current engine: \(detail)"
        case .memoryPressure: return "Generation stopped because memory was low. Close other apps and try again."
        case .tooHot: return "Your device needs to cool down before generation can continue."
        case .interrupted: return "Generation was interrupted. Keep the app open during generation."
        case .insufficientStorage: return "There is not enough free storage. Free space and try again."
        case .encodingFailed(let detail): return "The video could not be saved: \(detail)"
        case .invalidTensor: return "The model produced invalid video data. Generation stopped."
        case .invalidCheckpoint: return "This saved baseline is damaged or incompatible. Discard the saved baseline to start a new one."
        }
    }
}

public enum MOVDModel {
    public static let revision = "cc1839814d0e1b0cb01953831a55a557ff6682bf"
    /// Decoder placement is separate from the diffusion-state checkpoint format.
    public static let decoderExecutionPolicy = "spatial-cpu-v2"
    public static let temporalParts = ["vae_temporal_part1", "vae_temporal_part2_1", "vae_temporal_part2_2", "vae_temporal_part2_3_1", "vae_temporal_part2_3_2", "vae_temporal_part2_3_3", "vae_temporal_part2_3_4", "vae_temporal_part2_4", "vae_temporal_part3"]
    public static let spatialParts = ["vae_spatial_part1", "vae_spatial_part2", "vae_spatial_part3_1", "vae_spatial_part3_2", "vae_spatial_part3_3", "vae_spatial_part3_4_1", "vae_spatial_part3_4_2", "vae_spatial_part3_4_3", "vae_spatial_part4"]
    public static let requiredNames: [String] = {
        var names = ["t5embed-tokens", "t5final-layer-norm", "stdit3_part1", "stdit3_part2"]
        names += (0..<24).map { "t5block-layer\($0)" }
        names += (0..<28).map { "stdit3_ST_\($0)" }
        names += (0..<28).map { "stdit3_TDTM_\($0)" }
        names += temporalParts
        names += spatialParts
        return names
    }()

    public static func validateInstallation(at directory: URL) throws {
        for name in requiredNames {
            let path = directory.appendingPathComponent(name + ".mlmodelc")
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  let files = try? FileManager.default.contentsOfDirectory(atPath: path.path), !files.isEmpty else {
                throw GenerationError.modelMissing(name)
            }
        }
    }
}
