import Foundation

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
    public var modelLoadSeconds: Double? = nil
    public var modelPredictionSeconds: Double? = nil
    public var diffusionEvaluations: Int? = nil
    public var profileID: String? = nil
    public var precision: String? = nil
}

public enum GenerationError: LocalizedError {
    case invalidPrompt, promptTooLong, invalidDuration, modelMissing(String)
    case incompatibleModel(String), memoryPressure, tooHot, interrupted, insufficientStorage
    case encodingFailed(String), invalidTensor, invalidCheckpoint
    case conditioningTooLong(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidPrompt: return "Describe the motion you want to generate."
        case .promptTooLong: return "Use a shorter prompt (up to 500 characters; all installed encoder limits also apply)."
        case .conditioningTooLong(let count): return "Your scene and style use \(count) model tokens; check the installed encoder limits. Shorten your scene or choose Default. Nothing has been truncated."
        case .invalidDuration: return "Choose a duration from 2 to 9 seconds."
        case .modelMissing(let name): return "The model is incomplete (\(name)). Reinstall the model in Models."
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
