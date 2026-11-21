import CoreML
import CryptoKit
import Foundation
import VideoEngine
import ZIPFoundation

struct ModelManifest: Codable, Sendable {
    struct ArchiveFile: Codable, Sendable {
        let name: String
        let url: URL
        let bytes: Int64
        let expandedBytes: Int64
        let sha256: String
        let models: [String]
    }
    let schemaVersion: Int
    let revision: String
    let minimumFreeBytes: Int64
    let archives: [ArchiveFile]
    var modelVersion: String? = nil
    var manifestVersion: Int? = nil
    var minimumAppVersion: String? = nil

    static func bundled() throws -> ModelManifest {
        guard let url = Bundle.main.url(forResource: "model-manifest", withExtension: "json") else {
            throw GenerationError.modelMissing("download manifest")
        }
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard manifest.schemaVersion == 1, manifest.revision == MOVDModel.revision,
              manifest.archives.allSatisfy({ $0.url.scheme == "https" && $0.sha256.count == 64 }) else {
            throw GenerationError.incompatibleModel("Download manifest version")
        }
        return manifest
    }
}

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

actor ModelInstaller {
    let root: URL
    var installed: URL { root.appendingPathComponent("Installed", isDirectory: true) }
    init(root: URL) { self.root = root }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: installed.appendingPathComponent("installation.json")),
              let revision = try? JSONDecoder().decode(String.self, from: data), revision == MOVDModel.revision else { return false }
        return (try? MOVDModel.validateInstallation(at: installed)) != nil
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func install(_ manifest: ModelManifest, benchmark: BenchmarkLog? = nil,
                 stage: @escaping @Sendable (ModelInstallationStage) -> Void = { _ in },
                 progress: @escaping @Sendable (GenerationProgress) -> Void) async throws {
        // Remote catalogs can relocate approved bytes, never introduce an arbitrary Core ML graph.
        if manifest.modelVersion != nil { try manifest.validateRemote(appVersion: SupportCompatibility.appVersion) }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(resources)
        let free = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free >= manifest.minimumFreeBytes else { throw GenerationError.insufficientStorage }
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let totalBytes = manifest.archives.reduce(Int64(0)) { $0 + $1.bytes }
        var completedBytes: Int64 = 0
        for archive in manifest.archives {
            try Task.checkCancellation()
            let zip = root.appendingPathComponent(archive.name)
            let resume = root.appendingPathComponent(archive.name + ".resume")
            let offset = completedBytes
            if !fm.fileExists(atPath: zip.path) {
                stage(.downloading)
                let downloader = ModelDownloader(destination: zip, resumeFile: resume)
                let start = benchmark?.begin(archive.name, phase: "download", fields: ["expectedBytes": String(archive.bytes)])
                do {
                    try await downloader.download(archive.url) { bytes in
                        progress(.init((Double(offset) + 0.6 * Double(bytes)) / Double(totalBytes), "Downloading \(archive.name)"))
                    }
                    if let start { benchmark?.end(archive.name, phase: "download", started: start) }
                } catch {
                    if let start { benchmark?.end(archive.name, phase: "download", started: start, error: error) }
                    throw error
                }
            } else { benchmark?.record("archive_reused", partition: archive.name) }
            stage(.verifying)
            progress(.init((Double(offset) + 0.6 * Double(archive.bytes)) / Double(totalBytes), "Verifying \(archive.name)"))
            guard let fileBytes = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(fileBytes) == archive.bytes else {
                try? fm.removeItem(at: zip); try? fm.removeItem(at: resume)
                throw ModelInstallError.incomplete
            }
            let checksum: String
            if let benchmark {
                checksum = try benchmark.measure(archive.name, phase: "checksum") { try Self.sha256(zip) }
            } else { checksum = try Self.sha256(zip) }
            benchmark?.record("checksum_result", partition: archive.name, fields: ["actual": checksum, "expected": archive.sha256])
            guard checksum == archive.sha256 else {
                try? fm.removeItem(at: zip)
                try? fm.removeItem(at: resume)
                throw ModelInstallError.checksum(archive.name)
            }
            let extracted = root.appendingPathComponent("Extracting", isDirectory: true)
            if fm.fileExists(atPath: extracted.path) { try fm.removeItem(at: extracted) }
            let extractionProgress = Progress()
            stage(.extracting)
            progress(.init((Double(offset) + 0.6 * Double(archive.bytes)) / Double(totalBytes), "Extracting \(archive.name)"))
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                if let benchmark {
                    try benchmark.measure(archive.name, phase: "extract") {
                        try fm.unzipItem(at: zip, to: extracted, progress: extractionProgress)
                    }
                } else { try fm.unzipItem(at: zip, to: extracted, progress: extractionProgress) }
            } onCancel: { extractionProgress.cancel() }
            defer { try? fm.removeItem(at: extracted) }
            guard let enumerator = fm.enumerator(at: extracted, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                throw ModelInstallError.invalidArchive
            }
            var packages: [String: URL] = [:]
            while let url = enumerator.nextObject() as? URL {
                if url.lastPathComponent == "__MACOSX" { enumerator.skipDescendants(); continue }
                if url.pathExtension == "mlpackage" {
                    enumerator.skipDescendants()
                    let name = url.deletingPathExtension().lastPathComponent
                    guard packages[name] == nil else { throw ModelInstallError.invalidArchive }
                    packages[name] = url
                }
            }
            guard Set(packages.keys) == Set(archive.models) else { throw ModelInstallError.invalidArchive }
            let neededModels = archive.models.filter { MOVDModel.requiredNames.contains($0) }
            for (index, name) in neededModels.enumerated() {
                try Task.checkCancellation()
                stage(.compiling)
                progress(.init((Double(offset) + Double(archive.bytes) * (0.6 + 0.39 * Double(index) / Double(neededModels.count))) / Double(totalBytes), "Compiling \(name) · \(index + 1) of \(neededModels.count)"))
                guard let source = packages[name] else { throw ModelInstallError.invalidArchive }
                let start = benchmark?.begin(name, phase: "compile")
                let compiled: URL
                do {
                    compiled = try await MLModel.compileModel(at: source)
                    if let start { benchmark?.end(name, phase: "compile", started: start) }
                } catch {
                    if let start { benchmark?.end(name, phase: "compile", started: start, error: error) }
                    throw error
                }
                defer { try? fm.removeItem(at: compiled) }
                try fm.moveItem(at: compiled, to: staging.appendingPathComponent(name + ".mlmodelc"))
            }
            completedBytes += archive.bytes
            try fm.removeItem(at: extracted)
        }
        try Task.checkCancellation()
        try MOVDModel.validateInstallation(at: staging)
        try JSONEncoder().encode(manifest.revision).write(to: staging.appendingPathComponent("installation.json"), options: .atomic)
        try ModelActivation.activate(staging: staging, installed: installed)
        for archive in manifest.archives {
            try? fm.removeItem(at: root.appendingPathComponent(archive.name))
            try? fm.removeItem(at: root.appendingPathComponent(archive.name + ".resume"))
            try? fm.removeItem(at: root.appendingPathComponent(archive.name + ".resume.source"))
        }
        stage(.complete)
        progress(.init(1, "Model installed"))
    }

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

    func hasRollback() -> Bool { FileManager.default.fileExists(atPath: ModelActivation.rollbackURL(installed).path) }
    func restoreRollback() throws {
        let rollback = ModelActivation.rollbackURL(installed)
        guard let data = try? Data(contentsOf: rollback.appendingPathComponent("installation.json")),
              (try? JSONDecoder().decode(String.self, from: data)) == MOVDModel.revision else { throw SupportError.incompatibleModel }
        try MOVDModel.validateInstallation(at: rollback)
        try ModelActivation.restore(installed: installed)
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
        guard fm.fileExists(atPath: backup.path) else { throw SupportError.incompatibleModel }
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
