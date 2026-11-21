import Darwin
import Foundation
import os

/// Append-only local measurements. A missing `finished` event means incomplete, never success.
/// Sampling and file I/O have overhead; compare runs with identical instrumentation settings.
public final class BenchmarkLog: @unchecked Sendable {
    public struct Snapshot: Codable, Sendable {
        public let footprintBytes: UInt64?
        public let processLifetimePeakBytes: UInt64?
        public let availableProcessMemoryBytes: UInt64?
        public let processCPUSeconds: Double?
        public let thermalState: String
    }

    struct Event: Codable {
        let schemaVersion: Int
        let sequence: Int
        let elapsedSeconds: Double
        let event: String
        let partition: String?
        let phase: String?
        let durationSeconds: Double?
        let snapshot: Snapshot
        let fields: [String: String]
    }

    public let url: URL
    private let lock = NSLock()
    private let handle: FileHandle
    private let encoder = JSONEncoder()
    private let started = ProcessInfo.processInfo.systemUptime
    private var sequence = 0
    private var closed = false
    private var writeFailure: String?
    private var activePartition: String?
    private var activePhase: String?
    private var timer: DispatchSourceTimer?
    private var sampledPeak: UInt64 = 0
    public var peakSampledMemoryBytes: UInt64 {
        lock.lock(); defer { lock.unlock() }; return sampledPeak
    }
    private let signpostLog = OSLog(subsystem: "com.agilejurf.localframes", category: .pointsOfInterest)

    public init(url: URL, kind: String, metadata: [String: String] = [:], sampleInterval: Double = 0.25) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        handle = try FileHandle(forWritingTo: url)
        var values = metadata
        values["kind"] = kind
        values["startedAt"] = ISO8601DateFormatter().string(from: Date())
        values["hardware"] = Self.hardwareIdentifier()
        values["os"] = ProcessInfo.processInfo.operatingSystemVersionString
        values["physicalMemoryBytes"] = String(ProcessInfo.processInfo.physicalMemory)
        values["logicalProcessorCount"] = String(ProcessInfo.processInfo.activeProcessorCount)
        values["sampleIntervalSeconds"] = String(sampleInterval)
        values["modelRevision"] = MOVDModel.revision
        values["expectedPartitions"] = MOVDModel.requiredNames.joined(separator: ",")
        values["gpuUtilization"] = "not measured; requires Instruments"
        values["memorySemantics"] = "phys_footprint samples; lifetime peak covers the entire app process, not this operation"
        values["availableMemorySemantics"] = "os_proc_available_memory: advisory additional bytes the app may allocate before its current limit; not device free RAM; absent on simulator"
        values["cpuSemantics"] = "getrusage process CPU seconds; includes logger overhead and excludes separate Core ML service processes"
        #if targetEnvironment(simulator)
        values["executionEnvironment"] = "simulator"
        #else
        values["executionEnvironment"] = "physical-device"
        #endif
        record("started", fields: values)
        try handle.synchronize()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.agilejurf.localframes.measurements", qos: .utility))
        timer.schedule(deadline: .now() + sampleInterval, repeating: sampleInterval, leeway: .milliseconds(25))
        timer.setEventHandler { [weak self] in self?.record("sample") }
        self.timer = timer
        timer.resume()
    }

    deinit { timer?.cancel(); try? handle.close() }

    public func record(_ event: String, partition: String? = nil, phase: String? = nil,
                       duration: Double? = nil, fields: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        if event == "begin" { activePartition = partition; activePhase = phase }
        let snapshot = Self.snapshot()
        sampledPeak = max(sampledPeak, snapshot.footprintBytes ?? 0)
        let entry = Event(schemaVersion: 1, sequence: sequence,
                          elapsedSeconds: ProcessInfo.processInfo.systemUptime - started,
                          event: event, partition: partition ?? activePartition, phase: phase ?? activePhase,
                          durationSeconds: duration, snapshot: snapshot, fields: fields)
        sequence += 1
        do {
            var data = try encoder.encode(entry)
            data.append(0x0A)
            try handle.write(contentsOf: data)
        } catch { writeFailure = error.localizedDescription }
        if event == "end" || event == "failure" { activePartition = nil; activePhase = nil }
    }

    public func begin(_ partition: String, phase: String, fields: [String: String] = [:]) -> Double {
        record("begin", partition: partition, phase: phase, fields: fields)
        return ProcessInfo.processInfo.systemUptime
    }

    public func end(_ partition: String, phase: String, started: Double, error: Error? = nil,
                    fields: [String: String] = [:]) {
        let duration = ProcessInfo.processInfo.systemUptime - started
        var values = fields
        if let error { values["error"] = String(describing: error) }
        record(error == nil ? "end" : "failure", partition: partition, phase: phase, duration: duration, fields: values)
    }

    public func measure<T>(_ partition: String, phase: String, fields: [String: String] = [:], _ body: () throws -> T) rethrows -> T {
        let time = begin(partition, phase: phase, fields: fields)
        let id = OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: "Model operation", signpostID: id, "%{public}s %{public}s", partition, phase)
        defer { os_signpost(.end, log: signpostLog, name: "Model operation", signpostID: id) }
        do {
            let value = try body()
            end(partition, phase: phase, started: time)
            return value
        } catch {
            end(partition, phase: phase, started: time, error: error)
            throw error
        }
    }

    public func finish(status: String, fields: [String: String] = [:]) throws {
        timer?.cancel()
        var values = fields
        values["status"] = status
        record("finished", fields: values)
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try handle.synchronize()
        try handle.close()
        if let writeFailure { throw NSError(domain: "LocalFrames.BenchmarkLog", code: 1, userInfo: [NSLocalizedDescriptionKey: writeFailure]) }
    }

    public static func snapshot() -> Snapshot {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        let usageStatus = getrusage(RUSAGE_SELF, &usage)
        let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        #if os(iOS) && !targetEnvironment(simulator)
        let availableMemory: UInt64? = UInt64(os_proc_available_memory())
        #else
        let availableMemory: UInt64? = nil
        #endif
        return Snapshot(footprintBytes: result == KERN_SUCCESS ? info.phys_footprint : nil,
                        processLifetimePeakBytes: result == KERN_SUCCESS && info.ledger_phys_footprint_peak > 0 ? UInt64(info.ledger_phys_footprint_peak) : nil,
                        availableProcessMemoryBytes: availableMemory,
                        processCPUSeconds: usageStatus == 0 ? seconds : nil, thermalState: thermal)
    }

    private static func hardwareIdentifier() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}
