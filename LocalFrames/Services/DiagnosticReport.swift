import Foundation
import VideoEngine

/// A new typed payload, not a filtered raw journal. No prompt, seed, file, ID, timestamp,
/// tensor or free-form error string can be encoded by this type.
struct DiagnosticReport: Encodable, Sendable {
    struct Partition: Codable, Sendable {
        let name: String
        let loads: Int
        let predictions: Int
        let loadSeconds: Double
        let predictionSeconds: Double
        let failures: Int
    }
    struct Operation: Codable, Sendable { let partition: String; let phase: String }
    let schemaVersion = 1
    let appVersion: String
    let appBuild: Int
    let osVersion: String
    let modelVersion = SupportCompatibility.modelVersion
    let kind: String
    let outcome: String
    let resumed: Bool
    let elapsedSeconds: Double
    let peakSampledMemoryBytes: UInt64
    let memoryWarnings: Int
    let thermalState: String
    let partitions: [Partition]
    let lastOperation: Operation?
    let errorCategory: String
    let errorDomain: String
    let errorCode: Int?

    init(summary: BenchmarkSummary) throws {
        guard summary.modelRevision == MOVDModel.revision,
              ["generation", "installation", "compute-plans"].contains(summary.kind) else { throw SupportError.incompatibleModel }
        appVersion = SupportCompatibility.version(summary.appVersion) == nil ? "0.0.0" : summary.appVersion
        appBuild = min(1_000_000, max(0, Int(summary.appBuild) ?? 0))
        osVersion = SupportCompatibility.version(summary.osVersion) == nil ? "0.0.0" : summary.osVersion
        kind = summary.kind
        let outcomes = ["succeeded", "failed", "cancelled", "interrupted", "completed_with_possible_unsupported_plans"]
        outcome = outcomes.contains(summary.status) ? summary.status : "interrupted"
        resumed = summary.restoredSteps > 0
        elapsedSeconds = Self.seconds(summary.elapsedSeconds)
        peakSampledMemoryBytes = min(summary.peakMemoryBytes, 1 << 40)
        memoryWarnings = min(100_000, max(0, summary.memoryWarnings))
        thermalState = ["critical", "serious", "fair", "nominal"].first { summary.thermalStates.contains($0) } ?? "unknown"
        var seen = Set<String>()
        partitions = summary.partitions.filter { MOVDModel.requiredNames.contains($0.name) && seen.insert($0.name).inserted }.prefix(102).map {
            Partition(name: $0.name, loads: min(100_000, max(0, $0.loads)), predictions: min(100_000, max(0, $0.predictions)),
                      loadSeconds: Self.seconds($0.loadSeconds), predictionSeconds: Self.seconds($0.predictionSeconds), failures: min(100_000, max(0, $0.failures)))
        }
        if let parts = summary.lastOperation?.components(separatedBy: " / "), parts.count == 2,
           MOVDModel.requiredNames.contains(parts[0]), ["load", "predict", "compile"].contains(parts[1]) {
            lastOperation = Operation(partition: parts[0], phase: parts[1])
        } else { lastOperation = nil }
        let categories = ["none", "memory-pressure", "model-load", "inference", "invalid-tensor", "installation", "encoding", "other", "interrupted"]
        errorCategory = categories.contains(summary.errorCategory) ? summary.errorCategory : "other"
        let domains = ["none", "CoreML", "Foundation", "POSIX", "AVFoundation", "LocalFrames", "other"]
        errorDomain = domains.contains(summary.errorDomain) ? summary.errorDomain : "other"
        errorCode = summary.errorCode.flatMap { (-2_147_483_647...2_147_483_647).contains($0) ? $0 : nil }
    }
    private static func seconds(_ value: Double) -> Double { value.isFinite ? (min(604_800, max(0, value)) * 1000).rounded() / 1000 : 0 }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        // Explicit null fields keep the server's exact schema stable across Swift encoders.
        var object = try JSONSerialization.jsonObject(with: encoder.encode(self)) as! [String: Any]
        object["lastOperation"] = object["lastOperation"] ?? NSNull()
        object["errorCode"] = object["errorCode"] ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        guard data.count <= 32768 else { throw SupportError.tooLarge }
        return data
    }
}
