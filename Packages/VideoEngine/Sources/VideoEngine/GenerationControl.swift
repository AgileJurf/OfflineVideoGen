import Foundation

/// Cooperatively waits between model operations. It never bypasses thermal protection.
public final class GenerationControl: @unchecked Sendable {
    public enum PauseReason: String, Sendable { case cooling, foregroundRequired }
    private let lock = NSLock()
    private var foreground = true
    private var backgroundAllowed = false
    private var cooling = false
    private var pausedSeconds = 0.0
    private let thermalState: @Sendable () -> ProcessInfo.ThermalState
    private let wait: @Sendable () async throws -> Void
    private let onPause: @Sendable (PauseReason?) -> Void

    public init(onPause: @escaping @Sendable (PauseReason?) -> Void = { _ in }) {
        thermalState = { ProcessInfo.processInfo.thermalState }
        wait = { try await Task.sleep(nanoseconds: 2_000_000_000) }
        self.onPause = onPause
    }

    init(thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState,
         wait: @escaping @Sendable () async throws -> Void,
         onPause: @escaping @Sendable (PauseReason?) -> Void = { _ in }) {
        self.thermalState = thermalState
        self.wait = wait
        self.onPause = onPause
    }

    public func setForeground(_ value: Bool) { lock.withLock { foreground = value } }
    public func allowBackgroundExecution(_ value: Bool) { lock.withLock { backgroundAllowed = value } }
    public var totalPausedSeconds: Double { lock.withLock { pausedSeconds } }

    private func reason() -> PauseReason? {
        let thermal = thermalState()
        return lock.withLock {
            if thermal == .serious || thermal == .critical { cooling = true }
            // Hysteresis: after overheating, wait for nominal rather than repeatedly restarting at fair.
            if thermal == .nominal { cooling = false }
            if cooling { return .cooling }
            if !foreground && !backgroundAllowed { return .foregroundRequired }
            return nil
        }
    }

    public func checkpoint(benchmark: BenchmarkLog? = nil) async throws {
        var activeReason: PauseReason?
        var pauseStart: Double?
        var resumed = false
        defer {
            if let pauseStart {
                let duration = ProcessInfo.processInfo.systemUptime - pauseStart
                lock.withLock { pausedSeconds += duration }
                benchmark?.record("pause_end", duration: duration, fields: ["resumed": String(resumed)])
                onPause(nil)
            }
        }
        while true {
            try Task.checkCancellation()
            guard let next = reason() else { resumed = true; return }
            if pauseStart == nil { pauseStart = ProcessInfo.processInfo.systemUptime }
            if activeReason != next {
                benchmark?.record(activeReason == nil ? "pause_begin" : "pause_reason_changed", fields: ["reason": next.rawValue])
                activeReason = next
                onPause(next)
            }
            try await wait()
        }
    }
}
