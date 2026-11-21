import CoreML
import Foundation

/// Loads one partition at a time. No model or tensor is cached across generations.
final class ModelRunner {
    let directory: URL
    let benchmark: BenchmarkLog?
    let control: GenerationControl
    var predictionCompleted: ((String, Double) -> Void)?
    var peakMemory: UInt64 = 0
    var thermalStates = Set<String>()
    var modelLoadSeconds = 0.0
    var modelPredictionSeconds = 0.0

    init(directory: URL, benchmark: BenchmarkLog? = nil, control: GenerationControl = GenerationControl()) {
        self.directory = directory; self.benchmark = benchmark; self.control = control
    }

    func checkpoint() async throws {
        try Task.checkCancellation()
        let thermal = ProcessInfo.processInfo.thermalState
        let label: String
        switch thermal {
        case .nominal: label = "nominal"
        case .fair: label = "fair"
        case .serious: label = "serious"
        case .critical: label = "critical"
        @unknown default: label = "unknown"
        }
        thermalStates.insert(label)
        try await control.checkpoint(benchmark: benchmark)
        #if os(iOS) && !targetEnvironment(simulator)
        guard os_proc_available_memory() > 256 * 1024 * 1024 else { throw GenerationError.memoryPressure }
        #endif
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS { peakMemory = max(peakMemory, info.phys_footprint) }
    }

    func predict(_ name: String, _ inputs: [String: MLFeatureValue], cpuOnly: Bool = false) async throws -> [String: MLFeatureValue] {
        try await checkpoint()
        let started = ProcessInfo.processInfo.systemUptime
        let output: [String: MLFeatureValue] = try autoreleasepool {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
            #else
            config.computeUnits = cpuOnly ? .cpuOnly : .cpuAndGPU
            #endif
            let modelURL = directory.appendingPathComponent(name + ".mlmodelc")
            let unitLabel = config.computeUnits == .cpuOnly ? "cpuOnly" : "cpuAndGPU"
            let model: MLModel
            let load = { () throws -> MLModel in
                let begin = ProcessInfo.processInfo.systemUptime
                defer { self.modelLoadSeconds += ProcessInfo.processInfo.systemUptime - begin }
                return try MLModel(contentsOf: modelURL, configuration: config)
            }
            if let benchmark {
                model = try benchmark.measure(name, phase: "load", fields: ["requestedComputeUnits": unitLabel], load)
            } else { model = try load() }
            let provider = try MLDictionaryFeatureProvider(dictionary: inputs)
            let result: MLFeatureProvider
            let predict = { () throws -> MLFeatureProvider in
                let begin = ProcessInfo.processInfo.systemUptime
                defer { self.modelPredictionSeconds += ProcessInfo.processInfo.systemUptime - begin }
                return try model.prediction(from: provider)
            }
            if let benchmark {
                let shapes = inputs.keys.sorted().map { key in
                    "\(key):\(inputs[key]?.multiArrayValue?.shape.map(\.intValue) ?? [])"
                }.joined(separator: ";")
                let layouts = inputs.keys.sorted().compactMap { key -> String? in
                    guard let array = inputs[key]?.multiArrayValue else { return nil }
                    return "\(key):type=\(array.dataType.rawValue),strides=\(array.strides.map(\.intValue))"
                }.joined(separator: ";")
                result = try benchmark.measure(name, phase: "predict", fields: ["requestedComputeUnits": unitLabel, "inputShapes": shapes, "inputLayouts": layouts], predict)
            } else { result = try predict() }
            try Task.checkCancellation()
            return Dictionary(uniqueKeysWithValues: result.featureNames.compactMap { key in
                result.featureValue(for: key).map { (key, $0) }
            })
        }
        predictionCompleted?(name, ProcessInfo.processInfo.systemUptime - started)
        // Release the loaded model before waiting for cooling or foreground access.
        try await checkpoint()
        return output
    }
}

func feature(_ array: MLShapedArray<Float32>) -> MLFeatureValue {
    MLFeatureValue(multiArray: MLMultiArray(array))
}

func tensor(_ values: [String: MLFeatureValue], _ key: String) throws -> MLShapedArray<Float32> {
    guard let array = values[key]?.multiArrayValue else { throw GenerationError.incompatibleModel("Missing output \(key)") }
    return MLShapedArray<Float32>(converting: array)
}

func value(_ values: [String: MLFeatureValue], _ key: String) throws -> MLFeatureValue {
    guard let result = values[key] else { throw GenerationError.incompatibleModel("Missing output \(key)") }
    return result
}
