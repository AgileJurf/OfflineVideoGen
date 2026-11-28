// Native macOS single-block workspace probe. Not an iPhone or full-video benchmark.
// Usage: compiled-probe package.mlpackage new-output-directory
import CoreML
import Foundation
import Darwin

func footprint() -> UInt64 {
    var info = task_vm_info_data_t(), count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return status == KERN_SUCCESS ? info.phys_footprint : 0
}
final class Samples: @unchecked Sendable {
    let lock = NSLock(); var phase = "prepare"; var peaks: [String: UInt64] = [:]
    func sample() { let bytes = footprint(); lock.lock(); peaks[phase] = max(peaks[phase] ?? 0, bytes); lock.unlock() }
    func set(_ value: String) { lock.lock(); phase = value; lock.unlock(); sample() }
    func values() -> [String: UInt64] { lock.lock(); defer { lock.unlock() }; return peaks }
}
func input(_ values: [Float32], _ shape: [Int]) -> MLFeatureValue { MLFeatureValue(multiArray: MLMultiArray(MLShapedArray(scalars: values, shape: shape))) }
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Usage: attention-probe package.mlpackage new-output-directory") }
let source = URL(fileURLWithPath: args[1]), destination = URL(fileURLWithPath: args[2], isDirectory: true)
guard !FileManager.default.fileExists(atPath: destination.path) else { fatalError("Use a new output directory") }
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let compiled = try MLModel.compileModel(at: source)
defer { try? FileManager.default.removeItem(at: compiled) }
let imageTokens = 1960, tokens = imageTokens + 128
let positions = [Int](repeating: 0, count: 128) + ([Int](repeating: 40, count: 13) + [160, 640, 640]).enumerated().flatMap { [Int](repeating: $0.offset, count: $0.element) }
let allowed = (0..<tokens).map { $0 < 19 || $0 >= 128 }
var mask = [Float32](repeating: 0, count: tokens * tokens), cosine = [Float32](repeating: 0, count: tokens * 32), sine = cosine
for q in 0..<tokens {
    for k in 0..<tokens where allowed[q] == allowed[k] && positions[q] >= positions[k] { mask[q * tokens + k] = 1 }
    for d in 0..<32 { let angle = Double(positions[q]) / pow(10_000, Double(d * 2) / 64); cosine[q * 32 + d] = Float32(cos(angle)); sine[q * 32 + d] = Float32(sin(angle)) }
}
let inputs = try MLDictionaryFeatureProvider(dictionary: [
    "hidden": input((0..<(imageTokens * 1536)).map { Float32(sin(Double($0) * 0.013)) * 0.2 }, [1, imageTokens, 1536]),
    "context": input((0..<(128 * 1536)).map { Float32(cos(Double($0) * 0.017)) * 0.2 }, [1, 128, 1536]),
    "time_embedding": input((0..<1536).map { Float32(sin(Double($0) * 0.019)) * 0.2 }, [1,1536]),
    "attention_mask": input(mask, [1,1,tokens,tokens]), "rope_cos": input(cosine,[1,tokens,1,32]), "rope_sin": input(sine,[1,tokens,1,32])])
let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
let samples = Samples(), timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
timer.setEventHandler { samples.sample() }; timer.schedule(deadline: .now(), repeating: .milliseconds(10)); timer.resume()
var trials: [[String: Any]] = []
for trial in 0..<3 {
    try autoreleasepool {
        samples.set("load-\(trial)"); let before = footprint(); let start = ProcessInfo.processInfo.systemUptime
        let model = try MLModel(contentsOf: compiled, configuration: config)
        let loaded = ProcessInfo.processInfo.systemUptime
        samples.set("predict-\(trial)")
        let result = try model.prediction(from: inputs)
        samples.sample(); let predicted = ProcessInfo.processInfo.systemUptime
        samples.set("verify-\(trial)")
        for name in ["hidden_out", "context_out"] {
            guard let array = result.featureValue(for: name)?.multiArrayValue else { throw NSError(domain: "ProbeMissingOutput", code: 1) }
            let values = MLShapedArray<Float32>(converting: array).scalars
            guard values.allSatisfy(\.isFinite) else { throw NSError(domain: "ProbeNonFinite", code: 1) }
            if trial == 0 { try values.withUnsafeBufferPointer { try Data(buffer: $0).write(to: destination.appendingPathComponent(name + ".bin")) } }
        }
        trials.append(["trial":trial,"beforeLoadFootprintBytes":before,"modelLoadSeconds":loaded-start,"predictionSeconds":predicted-loaded])
    }
    samples.set("released-\(trial)")
}
timer.cancel()
let report: [String:Any] = ["scope":"One real-weight Core ML transformer block, identical synthetic activations, fresh macOS process; not iPhone or full-video validation","model":source.path,"imageTokens":imageTokens,"totalTokens":tokens,"computeUnits":"cpuOnly","samplesIntervalSeconds":0.01,"sampledPeaksByPhaseBytes":samples.values(),"trials":trials,"outputsFinite":true]
let data = try JSONSerialization.data(withJSONObject:report, options:[.prettyPrinted,.sortedKeys])
try data.write(to:destination.appendingPathComponent("native-report.json"));print(String(decoding:data,as:UTF8.self))
