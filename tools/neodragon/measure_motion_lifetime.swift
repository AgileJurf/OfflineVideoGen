// Repeated real-weight block I/O lifetime probe, not a video or device benchmark.
import CoreML
import CryptoKit
import Foundation
import Darwin

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return status == KERN_SUCCESS ? info.phys_footprint : 0
}

func feature(_ values: MLShapedArray<Float32>) -> MLFeatureValue {
    MLFeatureValue(multiArray: MLMultiArray(values))
}

func predict(_ directory: URL, _ inputs: [String: MLFeatureValue]) async throws -> [String: MLFeatureValue] {
    try Task.checkCancellation()
    return try autoreleasepool {
        let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: directory, configuration: config)
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
        return Dictionary(uniqueKeysWithValues: result.featureNames.compactMap { name in
            result.featureValue(for: name).map { (name, $0) }
        })
    }
}

func runProbe(_ args: [String]) async throws {
    guard args.count == 4, ["borrowed", "owned", "scoped-owned", "scoped-borrowed"].contains(args[2]) else {
        fatalError("Usage: motion-lifetime compiled-block.mlmodelc borrowed|owned|scoped-owned|scoped-borrowed new-output-directory")
    }
    let source = URL(fileURLWithPath: args[1]), destination = URL(fileURLWithPath: args[3], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: destination.path) else { fatalError("Preserve existing evidence") }
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let owned = ["owned", "scoped-owned"].contains(args[2]), imageTokens = 1600, tokens = 1728
    let lengths = [40,40,40,40,160,640,640]
    let positions = [Int](repeating: 0, count: 128) + lengths.enumerated().flatMap { [Int](repeating: $0.offset, count: $0.element) }
    let allowed = (0..<tokens).map { $0 < 19 || $0 >= 128 }
    var mask = [Float32](repeating: 0, count: tokens * tokens)
    var cosine = [Float32](repeating: 0, count: tokens * 32), sine = cosine
    for q in 0..<tokens {
        for k in 0..<tokens where allowed[q] == allowed[k] && positions[q] >= positions[k] { mask[q * tokens + k] = 1 }
        for d in 0..<32 {
            let angle = Double(positions[q]) / pow(10_000, Double(d * 2) / 64)
            cosine[q * 32 + d] = Float32(cos(angle)); sine[q * 32 + d] = Float32(sin(angle))
        }
    }
    var inputs: [String: MLFeatureValue] = [
        "hidden":feature(.init(scalars:(0..<(imageTokens * 1536)).map { Float32(sin(Double($0) * 0.013)) * 0.2 },shape:[1,imageTokens,1536])),
        "context":feature(.init(scalars:(0..<(128 * 1536)).map { Float32(cos(Double($0) * 0.017)) * 0.2 },shape:[1,128,1536])),
        "time_embedding":feature(.init(scalars:(0..<1536).map { Float32(sin(Double($0) * 0.019)) * 0.2 },shape:[1,1536])),
        "attention_mask":feature(.init(scalars:mask,shape:[1,1,tokens,tokens])),
        "rope_cos":feature(.init(scalars:cosine,shape:[1,tokens,1,32])),
        "rope_sin":feature(.init(scalars:sine,shape:[1,tokens,1,32]))]
    var observations: [[String: Any]] = []
    let started = ProcessInfo.processInfo.systemUptime
    for iteration in 0..<24 {
        let before = footprint()
        let outputs = try await predict(source, inputs)
        let predicted = footprint()
        for (output, input) in [("hidden_out", "hidden"), ("context_out", "context")] {
            let transfer = { () throws -> MLFeatureValue in
                guard let array = outputs[output]?.multiArrayValue else { fatalError("Missing output") }
                let next = MLShapedArray<Float32>(converting: array)
                guard next.scalars.allSatisfy(\.isFinite) else { fatalError("Nonfinite") }
                let value: MLFeatureValue
                if owned {
                    value = autoreleasepool { feature(.init(scalars: next.scalars, shape: next.shape)) }
                } else {
                    value = feature(next)
                }
                if iteration == 23 {
                    try next.scalars.withUnsafeBufferPointer {
                        try Data(buffer: $0).write(to: destination.appendingPathComponent(output + ".bin"))
                    }
                }
                return value
            }
            inputs[input] = try args[2].hasPrefix("scoped-") ? autoreleasepool(invoking: transfer) : transfer()
        }
        observations.append(["iteration":iteration + 1,"beforePredictionBytes":before,
                             "afterPredictionBytes":predicted,"afterInputUpdateBytes":footprint()])
    }
    let report: [String: Any] = ["scope":"24 recurrent calls of one real Core ML block with synthetic activations, CPU-only on Mac. Not full-network quality or iPhone performance.",
        "mode":args[2],"imageTokens":imageTokens,"observations":observations,
        "elapsedSeconds":ProcessInfo.processInfo.systemUptime-started,"outputsFinite":true]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        .write(to:destination.appendingPathComponent("report.json"))
    print("Completed \(args[2]) motion lifetime probe")
}

@main struct Main {
    static func main() async throws { try await runProbe(CommandLine.arguments) }
}
