import CoreML
import CryptoKit
import Foundation
import VideoEngine

enum ModelInstallError: LocalizedError {
    case checksum(String), http(Int), incomplete, invalidArchive
    var errorDescription: String? {
        switch self {
        case .checksum(let name): return "\(name) failed its integrity check. Try installing again."
        case .http(let status): return "The model server returned error \(status). Try again later."
        case .incomplete: return "The model download did not finish. Resume installation to retry."
        case .invalidArchive: return "The model archive has unexpected contents. Reinstall the model."
        }
    }
}

enum ModelInstallationStage: String, Sendable {
    case preparing, downloading, verifying, extracting, compiling, complete

    var shouldPauseForMemoryWarning: Bool { self == .extracting || self == .compiling }
}

enum FileIntegrity {
    static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            // Foundation's FileHandle read buffers can remain autoreleased for this
            // entire synchronous loop. Bound their lifetime while hashing multi-GB archives.
            let count: Int = try autoreleasepool {
                guard let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty else { return 0 }
                hash.update(data: data)
                return data.count
            }
            if count == 0 { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

}

enum ModelActivation {
    static func rollbackURL(_ installed: URL) -> URL { installed.deletingLastPathComponent().appendingPathComponent("RollbackInstalled", isDirectory: true) }
    static func activate(staging: URL, installed: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: rollbackURL(installed).path) else {
            throw GenerationError.incompatibleModel("A rollback copy already exists; restore it before another model replacement.")
        }
        if fm.fileExists(atPath: installed.path) {
            _ = try fm.replaceItemAt(installed, withItemAt: staging, backupItemName: "RollbackInstalled", options: .withoutDeletingBackupItem)
        } else { try fm.moveItem(at: staging, to: installed) }
    }
    static func restore(installed: URL) throws {
        let fm = FileManager.default, backup = rollbackURL(installed)
        guard fm.fileExists(atPath: backup.path) else { throw GenerationError.incompatibleModel("No compatible rollback copy") }
        if fm.fileExists(atPath: installed.path) { _ = try fm.replaceItemAt(installed, withItemAt: backup) }
        else { try fm.moveItem(at: backup, to: installed) }
    }
}

/// Model downloads are separate from optional support requests and offline inference.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let resumeFile: URL
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var progress: (@Sendable (Int64) -> Void)?
    private var downloadError: Error?
    private var cancelled = false
    private var lastProgressTime: TimeInterval = 0
    private var sourceURL: URL?
    private var usedResumeData = false
    private var retriedWithoutResume = false

    init(destination: URL, resumeFile: URL) { self.destination = destination; self.resumeFile = resumeFile }

    func download(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.progress = progress
                self.sourceURL = url
                let config = URLSessionConfiguration.default
                config.allowsCellularAccess = false
                config.waitsForConnectivity = true
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                let identity = resumeFile.appendingPathExtension("source")
                if (try? String(contentsOf: identity, encoding: .utf8)) != url.absoluteString {
                    try? FileManager.default.removeItem(at: resumeFile)
                }
                try? url.absoluteString.write(to: identity, atomically: true, encoding: .utf8)
                if let data = try? Data(contentsOf: resumeFile) { usedResumeData = true; task = session.downloadTask(withResumeData: data) }
                else { task = session.downloadTask(with: url) }
                task?.resume()
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel(byProducingResumeData: { data in
                if let data { try? data.write(to: self.resumeFile, options: .atomic) }
            })
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProgressTime >= 0.2 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastProgressTime = now
        progress?(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw ModelInstallError.http((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { downloadError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // A host may invalidate a saved range/redirect. Retry once from the approved URL;
        // the complete length and SHA-256 must still pass before extraction.
        let rejectedRange = [403, 416].contains((task.response as? HTTPURLResponse)?.statusCode ?? 0)
        lock.lock()
        let shouldRetry = !cancelled && usedResumeData && !retriedWithoutResume && rejectedRange
        if shouldRetry, let sourceURL {
            retriedWithoutResume = true; downloadError = nil
            try? FileManager.default.removeItem(at: resumeFile)
            let retry = session.downloadTask(with: sourceURL); self.task = retry
            lock.unlock(); retry.resume(); return
        }
        lock.unlock()
        if let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? data.write(to: resumeFile, options: .atomic)
        }
        lock.lock()
        let completion = continuation
        continuation = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { completion?.resume(throwing: CancellationError()) }
        else if let error = downloadError ?? error { completion?.resume(throwing: error) }
        else if FileManager.default.fileExists(atPath: destination.path) { completion?.resume() }
        else { completion?.resume(throwing: ModelInstallError.incomplete) }
        session.finishTasksAndInvalidate()
        self.session = nil
    }
}
