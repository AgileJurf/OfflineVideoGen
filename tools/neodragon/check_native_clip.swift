import CoreML
import Foundation

/// Same original reference inputs used by the iOS Simulator precision test.
/// This distinguishes host-runtime behavior; it is not an iPhone benchmark.
@main
struct NativeCLIPCheck {
    struct Fixture: Decodable {
        struct Case: Decodable { let shape: [Int]; let embeddingFile: String; let groupFile: String }
        let cases: [Case]
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Usage: check-native-clip package.mlpackage reference-directory output.json")
        }
        let package = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let destination = URL(fileURLWithPath: CommandLine.arguments[3])
        guard !FileManager.default.fileExists(atPath: destination.path) else { fatalError("Preserve existing evidence") }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("fixture.json")))
        let compiled = try await MLModel.compileModel(at: package)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: config)
        func read(_ filename: String) throws -> [Float32] {
            let data = try Data(contentsOf: root.appendingPathComponent(filename))
            return data.withUnsafeBytes { buffer in
                stride(from: 0, to: data.count, by: 4).map { buffer.loadUnaligned(fromByteOffset: $0, as: Float32.self) }
            }
        }
        var cases: [[String: Any]] = []
        for (index, item) in fixture.cases.enumerated() {
            let input = MLFeatureValue(multiArray: MLMultiArray(MLShapedArray<Float32>(scalars: try read(item.embeddingFile), shape: item.shape)))
            let output = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["hidden": input]))
            guard let array = output.featureValue(for: "hidden_out")?.multiArrayValue else { fatalError("Missing group output") }
            let values = MLShapedArray<Float32>(converting: array).scalars
            let reference = try read(item.groupFile)
            let invalid = values.filter { !$0.isFinite }.count
            var delta = 0.0, energy = 0.0
            for (a, b) in zip(values, reference) {
                if a.isFinite { delta += pow(Double(a) - Double(b), 2) }
                energy += pow(Double(b), 2)
            }
            let relative = sqrt(delta / max(energy, 1e-30))
            let passed = invalid == 0 && values.count == reference.count && relative <= 0.01
            cases.append(["index": index, "nonFiniteValues": invalid, "finiteSubsetRelativeL2": relative, "passed": passed])
            print("Native macOS case \(index): invalid=\(invalid), relativeL2=\(relative), passed=\(passed)")
        }
        let report: [String: Any] = ["scope": "Native macOS CPU comparison; not iPhone validation", "package": package.lastPathComponent,
                                     "os": ProcessInfo.processInfo.operatingSystemVersionString, "cases": cases]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
    }
}
