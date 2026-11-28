import BackgroundTasks
import Foundation
import UIKit
import VideoEngine

/// Requests real, system-managed GPU runtime. A foreground task is the safe fallback.
@MainActor
final class BackgroundGeneration {
    static let shared = BackgroundGeneration()
    static let identifierPrefix = "com.agilejurf.localframes.generation"
    private var identifier: String?
    private var launch: (() -> Void)?
    private var expired: (() -> Void)?
    private var control: GenerationControl?
    private var log: BenchmarkLog?
    private var completion: ((Bool) -> Void)?
    private var update: ((GenerationProgress, String?) -> Void)?
    private var launchTimeout: Task<Void, Never>?
    var statusChanged: ((String) -> Void)?

    var availabilityMessage: String {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            return BGTaskScheduler.supportedResources.contains(.gpu)
                ? "Background GPU access is supported. Each job still needs permission from iOS."
                : "This device or iOS build is not offering background GPU access. Keep Local Frames open; switching apps pauses generation."
        }
        #endif
        return "Background GPU generation needs iOS 26 or later and a build made with its SDK. Keep Local Frames open."
    }

    func start(control: GenerationControl, log: BenchmarkLog?, onExpiration: @escaping () -> Void,
               work: @escaping () -> Void) {
        finish(success: false)
        self.control = control; self.log = log; self.expired = onExpiration
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), BGTaskScheduler.supportedResources.contains(.gpu) {
            let id = Self.identifierPrefix + "." + UUID().uuidString
            // Continued-processing handlers may be registered at submission. Register this exact
            // identifier, not a wildcard handler; the plist still permits the dynamic suffix.
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
                guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                Task { @MainActor in
                    guard let self else { task.setTaskCompleted(success: false); return }
                    self.accept(task)
                }
            }
            guard registered else {
                log?.record("background_unavailable", fields: ["gpuSupported": "true", "registered": "false", "reason": "Exact task identifier registration was rejected"])
                statusChanged?("iOS rejected background task registration. Keep the app open to generate.")
                work(); return
            }
            identifier = id; launch = work
            let request = BGContinuedProcessingTaskRequest(identifier: id, title: "Local Frames video", subtitle: "Preparing generation")
            request.requiredResources = .gpu
            request.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(request)
                log?.record("background_requested", fields: ["gpuSupported": "true", "registered": "true", "strategy": "fail", "registration": "exact-per-job"])
                statusChanged?("Requesting background generation from iOS…")
                launchTimeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                    guard let self, self.identifier == id, let pending = self.launch else { return }
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
                    self.identifier = nil; self.launch = nil
                    self.log?.record("background_unavailable", fields: ["reason": "No launch callback within 10 seconds; continuing in foreground"])
                    self.statusChanged?("iOS did not start the background task. Keep the app open; switching apps pauses generation.")
                    pending()
                }
                return
            } catch {
                identifier = nil; launch = nil
                let error = error as NSError
                log?.record("background_unavailable", fields: ["errorDomain": error.domain, "errorCode": String(error.code), "reason": "System declined GPU task submission"])
                statusChanged?("iOS declined background execution (code \(error.code)). Keep the app open; switching apps pauses generation.")
                work(); return
            }
        }
        #endif
        log?.record("background_unavailable", fields: ["reason": availabilityMessage, "registration": "not attempted", "gpuSupported": "false"])
        statusChanged?(availabilityMessage)
        work()
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private func accept(_ task: BGContinuedProcessingTask) {
        guard identifier == task.identifier, let launch else { task.setTaskCompleted(success: false); return }
        self.launch = nil
        launchTimeout?.cancel(); launchTimeout = nil
        task.progress.totalUnitCount = 10_000
        completion = { task.setTaskCompleted(success: $0) }
        update = { progress, paused in
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(progress.fraction * 10_000))
            let estimate = progress.estimate.map { " · " + $0.displayText } ?? ""
            task.updateTitle("Local Frames video", subtitle: paused ?? (progress.message + estimate))
        }
        let sessionControl = control
        let id = task.identifier
        task.expirationHandler = { [weak self] in
            // Revoke permission immediately; the in-flight Core ML call may still need to return.
            sessionControl?.allowBackgroundExecution(false)
            Task { @MainActor in
                guard let self, self.identifier == id else { return }
                self.log?.record("background_expired", fields: ["reason": "System expiration or cancellation in the system progress UI"])
                self.statusChanged?("iOS ended this background task. The current job was interrupted; completed videos remain in Library.")
                self.expired?()
                self.finish(success: false)
            }
        }
        control?.allowBackgroundExecution(true)
        log?.record("background_granted", fields: ["resource": "gpu"])
        statusChanged?("Background generation is active. iOS may pause or end it.")
        launch()
    }
    #endif

    func report(_ progress: GenerationProgress, paused: String? = nil) { update?(progress, paused) }

    func finish(success: Bool) {
        launchTimeout?.cancel(); launchTimeout = nil
        control?.allowBackgroundExecution(false)
        completion?(success)
        if completion != nil { statusChanged?((success ? "Last job completed. " : "Background execution ended. ") + availabilityMessage) }
        if let identifier {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        identifier = nil; launch = nil; expired = nil; completion = nil; update = nil; control = nil; log = nil
    }
}
