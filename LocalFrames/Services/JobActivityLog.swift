import Foundation
import Combine
import VideoEngine

struct JobActivity: Identifiable, Equatable, Sendable {
    let id: Int
    let elapsed: Double
    let message: String
    var time: String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
}

/// Inference threads append short messages under a lock; UI refresh is 2 Hz.
final class JobActivityBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [JobActivity] = []
    private var nextID = 0
    let limit: Int
    init(limit: Int = 200) { self.limit = max(1, limit) }
    func append(elapsed: Double, message: String) {
        lock.lock(); defer { lock.unlock() }
        guard entries.last?.message != message else { return }
        entries.append(JobActivity(id: nextID, elapsed: max(0, elapsed), message: String(message.prefix(500))))
        nextID += 1
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }
    func snapshot() -> [JobActivity] { lock.lock(); defer { lock.unlock() }; return entries }
}

@MainActor
final class JobActivityLog: ObservableObject {
    @Published private(set) var entries: [JobActivity] = []
    @Published private(set) var recording = false
    private(set) var buffer = JobActivityBuffer()
    private var started = ProcessInfo.processInfo.systemUptime
    private var refresh: Task<Void, Never>?

    func start() {
        refresh?.cancel(); buffer = JobActivityBuffer(); entries = []; recording = true
        started = ProcessInfo.processInfo.systemUptime
        append("Preparing generation")
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                self?.flush()
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    func append(_ message: String) {
        guard recording else { return }
        buffer.append(elapsed: ProcessInfo.processInfo.systemUptime - started, message: message)
    }
    func flush() { let latest = buffer.snapshot(); if latest != entries { entries = latest } }
    func finish(_ message: String) {
        guard recording else { return }
        append(message); flush(); recording = false; refresh?.cancel(); refresh = nil
    }
    deinit { refresh?.cancel() }
}
