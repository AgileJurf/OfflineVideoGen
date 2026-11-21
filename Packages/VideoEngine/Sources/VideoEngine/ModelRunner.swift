import CoreML
import Foundation

/// Loads one partition at a time. No model or tensor is cached across generations.
final class ModelRunner {
    let directory: URL
    var peakMemory: UInt64 = 0
    var thermalStates = Set<String>()

    init(directory: URL) { self.directory = directory }

    func checkpoint() throws {
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
        guard thermal != .serious && thermal != .critical else { throw GenerationError.tooHot }
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

    func predict(_ name: String, _ inputs: [String: MLFeatureValue], cpuOnly: Bool = false) throws -> [String: MLFeatureValue] {
        try checkpoint()
        let output: [String: MLFeatureValue] = try autoreleasepool {
            let config = MLModelConfiguration()
            #if targetEnvironment(simulator)
            config.computeUnits = .cpuOnly
            #else
            config.computeUnits = cpuOnly ? .cpuOnly : .cpuAndGPU
            #endif
            let model = try MLModel(contentsOf: directory.appendingPathComponent(name + ".mlmodelc"), configuration: config)
            let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
            try checkpoint()
            return Dictionary(uniqueKeysWithValues: result.featureNames.compactMap { key in
                result.featureValue(for: key).map { (key, $0) }
            })
        }
        try checkpoint()
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
