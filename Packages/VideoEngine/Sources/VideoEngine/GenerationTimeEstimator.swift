import Foundation

/// Estimates remaining model work from observed load + prediction durations on this device.
/// Unknown decoder costs never become an invented full-job finish time.
// Owned by one generation task; Sendable closures report immutable progress outside that task.
final class GenerationTimeEstimator: @unchecked Sendable {
    enum Stage: String, Codable {
        case prompt, mergedMotion, motion, temporalDecode, spatialDecode
        var label: String {
            switch self {
            case .prompt: return "Prompt preparation"
            case .mergedMotion, .motion: return "Current motion phase"
            case .temporalDecode, .spatialDecode: return "Current decoding phase"
            }
        }
    }
    struct Operation { let name: String; let stage: Stage }
    private struct History: Codable { let signature: String; let samples: [String: [Double]] }
    private let signature = MOVDModel.revision + GenerationCheckpoint.configuration + ProcessInfo.processInfo.operatingSystemVersionString
    private let plan: [Operation]
    private let historyURL: URL?
    private var samples: [String: [Double]] = [:]
    private var completed = 0
    private var valid = true
    var currentProgress = GenerationProgress(0, "Preparing generation")

    init(request: GenerationRequest, restoredSteps: Int?, historyURL: URL?) {
        plan = Self.operations(request: request, restoredSteps: restoredSteps)
        self.historyURL = historyURL
        if let historyURL, let data = try? Data(contentsOf: historyURL), data.count < 256 * 1024,
           let history = try? JSONDecoder().decode(History.self, from: data), history.signature == signature {
            let allowed = Set(MOVDModel.requiredNames)
            samples = history.samples.filter { allowed.contains($0.key) }.mapValues { $0.filter { $0.isFinite && $0 > 0 && $0 < 86400 }.suffix(8).map { $0 } }
        }
    }

    static func operations(request: GenerationRequest, restoredSteps: Int?) -> [Operation] {
        var result: [Operation] = []
        if restoredSteps == nil {
            result += (["t5embed-tokens"] + (0..<24).map { "t5block-layer\($0)" } + ["t5final-layer-norm"]).map { .init(name: $0, stage: .prompt) }
        }
        for step in min(21, max(0, restoredSteps ?? 0))..<21 {
            let stage: Stage = step < 10 ? .mergedMotion : .motion
            result.append(.init(name: "stdit3_part1", stage: stage))
            result += (0..<28).map { .init(name: "stdit3_\(step < 10 ? "TDTM" : "ST")_\($0)", stage: stage) }
            result.append(.init(name: "stdit3_part2", stage: stage))
        }
        for _ in 0..<4 { result += MOVDModel.temporalParts.map { .init(name: $0, stage: .temporalDecode) } }
        for _ in 0..<((request.frameCount + 3) / 4) { result += MOVDModel.spatialParts.map { .init(name: $0, stage: .spatialDecode) } }
        return result
    }

    func record(_ name: String, seconds: Double) {
        guard valid, completed < plan.count, plan[completed].name == name else { valid = false; return }
        completed += 1
        if seconds.isFinite, seconds > 0, seconds < 86400 {
            samples[name, default: []].append(seconds)
            samples[name] = Array(samples[name]!.suffix(8))
        }
        if completed % 30 == 0 { persist() }
    }

    func persist() {
        guard let historyURL, let data = try? JSONEncoder().encode(History(signature: signature, samples: samples)) else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }

    private func cost(_ name: String) -> Double? {
        if let values = samples[name], !values.isEmpty {
            // Recent measurements have more weight, so thermal throttling changes the estimate.
            let weighted = values.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * $1.element }
            return weighted / Double(values.count * (values.count + 1) / 2)
        }
        // Transformer blocks within a family share a structure. Do not infer ST from TDTM,
        // or decoder costs from transformer timings.
        let prefix: String
        if name.hasPrefix("stdit3_TDTM_") { prefix = "stdit3_TDTM_" }
        else if name.hasPrefix("stdit3_ST_") { prefix = "stdit3_ST_" }
        else { return nil }
        let measured = samples.filter { $0.key.hasPrefix(prefix) && !$0.value.isEmpty }
        guard measured.count >= 3 else { return nil }
        let means = measured.values.map { $0.reduce(0, +) / Double($0.count) }
        return means.reduce(0, +) / Double(means.count)
    }

    var estimate: GenerationEstimate? {
        guard valid, completed < plan.count else { return nil }
        let remaining = plan.dropFirst(completed)
        func sum(_ operations: ArraySlice<Operation>) -> Double? {
            var result = 0.0
            for operation in operations {
                guard let seconds = cost(operation.name) else { return nil }
                result += seconds
            }
            return result
        }
        if let total = sum(remaining) { return .init(seconds: total, scope: "Estimated time remaining", isFullJob: true) }
        let phase = remaining.prefix { $0.stage == remaining.first!.stage }
        if let total = sum(phase) { return .init(seconds: total, scope: remaining.first!.stage.label, isFullJob: false) }
        return nil
    }

    func decorate(_ progress: GenerationProgress) -> GenerationProgress {
        currentProgress = progress
        return .init(progress.fraction, progress.message, estimate: estimate)
    }
}
