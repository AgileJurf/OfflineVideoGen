import Foundation
import VideoEngine

struct PartitionTiming: Identifiable, Sendable {
    let name: String
    var id: String { name }
    var loads = 0
    var predictions = 0
    var loadSeconds = 0.0
    var predictionSeconds = 0.0
    var failures = 0
}

/// Local-only journal reader. No network client or upload representation is used here.
struct BenchmarkSummary: Identifiable, Sendable {
    let id: String
    var status = "interrupted"
    var kind = "unknown"
    var appBuild = "unknown"
    var appVersion = "0.0.0"
    var osVersion = "0.0.0"
    var errorCategory = "none"
    var errorDomain = "none"
    var errorCode: Int?
    var modelRevision = "unknown"
    var configuration = "unknown"
    var prompt = ""
    var effectivePrompt = ""
    var style = VisualStyle.default.name
    var seed = ""
    var elapsedSeconds = 0.0
    var peakMemoryBytes: UInt64 = 0
    var memoryWarnings = 0
    var thermalStates = Set<String>()
    var restoredSteps = 0
    var completedSteps = 0
    var expectedEvaluations = 21
    var lastOperation: String?
    var failure: String?
    var hasIncompleteLines = false
    var width = "unknown"
    var height = "unknown"
    var fps = "unknown"
    var partitions: [PartitionTiming] = []
    var totalLoadSeconds: Double { partitions.reduce(0) { $0 + $1.loadSeconds } }
    var totalPredictionSeconds: Double { partitions.reduce(0) { $0 + $1.predictionSeconds } }
    var sessionLabel: String { restoredSteps > 0 ? "Resumed session" : "Generation session" }

    private struct Event: Decodable {
        struct Snapshot: Decodable { let footprintBytes: UInt64?; let thermalState: String }
        let sequence: Int
        let elapsedSeconds: Double
        let event: String
        let partition: String?
        let phase: String?
        let durationSeconds: Double?
        let snapshot: Snapshot
        let fields: [String: String]
    }

    static func read(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Self(id: url.lastPathComponent)
        var timings: [String: PartitionTiming] = [:]
        var partitionNames = Set(MOVDModel.requiredNames)
        let decoder = JSONDecoder()
        var sequence = 0, totalBytes = 0
        func consume(_ line: Data) {
            guard !line.isEmpty else { return }
            guard let e = try? decoder.decode(Event.self, from: line), e.elapsedSeconds.isFinite else {
                result.hasIncompleteLines = true; return
            }
            if e.sequence != sequence { result.hasIncompleteLines = true }
            sequence = e.sequence + 1
            result.elapsedSeconds = max(result.elapsedSeconds, e.elapsedSeconds)
            result.peakMemoryBytes = max(result.peakMemoryBytes, e.snapshot.footprintBytes ?? 0)
            result.thermalStates.insert(e.snapshot.thermalState)
            if e.event == "started" {
                result.kind = e.fields["kind"] ?? "unknown"
                result.appBuild = e.fields["appBuild"] ?? "unknown"
                result.appVersion = e.fields["appVersion"] ?? "0.0.0"
                result.osVersion = e.fields["osVersion"] ?? "0.0.0"
                result.modelRevision = e.fields["modelRevision"] ?? "unknown"
                if result.modelRevision == NeodragonModel.weightsRevision {
                    partitionNames = Set((e.fields["expectedPartitions"] ?? "").split(separator: ",").prefix(250)
                        .map(String.init).filter { !$0.isEmpty && $0.count <= 120 && $0.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) })
                    result.expectedEvaluations = Int(e.fields["expectedEvaluations"] ?? "") ?? 0
                }
                result.configuration = e.fields["configuration"] ?? "unknown"
                result.prompt = e.fields["prompt"] ?? ""
                result.effectivePrompt = e.fields["effectiveModelPrompt"] ?? result.prompt
                result.style = e.fields["visualStyle"].flatMap(VisualStyle.init(rawValue:))?.name ?? VisualStyle.default.name
                result.seed = e.fields["seed"] ?? ""
                result.width = e.fields["width"] ?? "unknown"
                result.height = e.fields["height"] ?? "unknown"
                result.fps = e.fields["fps"] ?? "unknown"
            }
            if e.event == "memory_warning" { result.memoryWarnings += 1 }
            if e.event == "checkpoint_restored" { result.restoredSteps = Int(e.fields["completedSteps"] ?? "") ?? 0 }
            if e.event == "checkpoint_saved" || e.event == "diffusion_step_completed" {
                result.completedSteps = max(result.completedSteps, Int(e.fields["completedSteps"] ?? "") ?? 0)
            }
            if e.event == "failure" || e.event == "finished" {
                // A final wrapper error must not erase the failing partition's more specific diagnosis.
                if let category = e.fields["errorCategory"],
                   category != "other" || result.errorCategory == "none" || result.errorCategory == "other" {
                    result.errorCategory = category
                    result.errorDomain = e.fields["errorDomain"] ?? "none"
                    result.errorCode = e.fields["errorCode"].flatMap(Int.init)
                }
            }
            if e.event == "finished" { result.status = e.fields["status"] ?? "unknown"; result.failure = e.fields["error"] }
            if let name = e.partition, partitionNames.contains(name), let phase = e.phase {
                if e.event == "begin" { result.lastOperation = name + " / " + phase }
                if e.event == "end" || e.event == "failure" {
                    result.lastOperation = nil
                    var timing = timings[name] ?? PartitionTiming(name: name)
                    let seconds = e.durationSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
                    if phase == "load" { timing.loads += 1; timing.loadSeconds += seconds }
                    if phase == "predict" { timing.predictions += 1; timing.predictionSeconds += seconds }
                    if e.event == "failure" { timing.failures += 1; result.failure = name + ": " + (e.fields["error"] ?? phase) }
                    timings[name] = timing
                }
            }
        }
        var pending = Data()
        while true {
            try Task.checkCancellation()
            let data = try autoreleasepool { try handle.read(upToCount: 64 * 1024) ?? Data() }
            if data.isEmpty { break }
            totalBytes += data.count
            guard totalBytes <= 128 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                autoreleasepool { consume(pending.subdata(in: pending.startIndex..<newline)) }
                pending.removeSubrange(pending.startIndex...newline)
            }
            guard pending.count <= 256 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
        }
        if !pending.isEmpty { result.hasIncompleteLines = true }
        result.completedSteps = max(result.completedSteps, result.restoredSteps)
        if result.status == "interrupted" { result.errorCategory = "interrupted" }
        else if result.status == "failed", result.errorCategory == "none" { result.errorCategory = "other" }
        result.partitions = timings.values.sorted { $0.loadSeconds + $0.predictionSeconds > $1.loadSeconds + $1.predictionSeconds }
        return result
    }

    static func list(in directory: URL) throws -> [Self] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "jsonl" }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        return try files.prefix(50).map { try read($0) }
    }
}
