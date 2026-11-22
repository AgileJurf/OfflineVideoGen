import CoreML
import Foundation
import VideoEngine
import ZIPFoundation

enum VideoModelChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case movd, neodragon
    var id: String { rawValue }
    var name: String { self == .movd ? "MOVD" : "Neodragon · experimental" }
}

struct NeodragonManifest: Codable, Sendable {
    struct Archive: Codable, Sendable {
        let name: String
        let url: URL
        let bytes: Int64
        let expandedBytes: Int64
        let sha256: String
        let models: [String]
        let supportFiles: [String]
    }
    let schemaVersion: Int
    let modelID: String
    let modelVersion: String
    let weightsRevision: String
    let sourceRevision: String
    let maximumSeconds: Int
    let minimumAppVersion: String
    let minimumFreeBytes: Int64
    let archives: [Archive]
    var downloadBytes: Int64 { archives.reduce(0) { $0 + $1.bytes } }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "neodragon-manifest", withExtension: "json") else {
            throw GenerationError.incompatibleModel("The optional Neodragon package is still being validated. No download is enabled in this build.")
        }
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }

    func validate() throws {
        guard schemaVersion == 1, modelID == NeodragonModel.identifier,
              weightsRevision == NeodragonModel.weightsRevision, sourceRevision == NeodragonModel.sourceRevision,
              (2...9).contains(maximumSeconds), (1...80).contains(archives.count), minimumFreeBytes > 0,
              SupportCompatibility.appVersion.compare(minimumAppVersion, options: .numeric) != .orderedAscending,
              Set(archives.map(\.name)).count == archives.count else { throw ModelInstallError.invalidArchive }
        var models = Set<String>(), files = Set<String>()
        for archive in archives {
            guard archive.name.hasSuffix(".zip"), archive.name == URL(fileURLWithPath: archive.name).lastPathComponent,
                  !archive.name.contains(".."), archive.bytes > 0, archive.bytes < 2_000_000_000,
                  archive.expandedBytes > 0, archive.expandedBytes < 4_000_000_000,
                  archive.sha256.count == 64, archive.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  archive.url.scheme == "https", archive.url.host == "github.com",
                  archive.url.path.hasPrefix("/AgileJurf/OfflineVideoGen/releases/download/neodragon-"),
                  archive.url.user == nil, archive.url.password == nil,
                  archive.url.query == nil, archive.url.fragment == nil else { throw ModelInstallError.invalidArchive }
            for name in archive.models {
                guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                      models.insert(name).inserted else { throw ModelInstallError.invalidArchive }
            }
            for path in archive.supportFiles {
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      !path.contains("\\"), !path.hasPrefix("/"),
                      ["json", "txt", "model"].contains(URL(fileURLWithPath: path).pathExtension),
                      files.insert(path).inserted else { throw ModelInstallError.invalidArchive }
            }
        }
        guard (60...250).contains(models.count), files.contains("neodragon-runtime.json") else { throw ModelInstallError.invalidArchive }
    }
}

/// Optional weights have a separate root from MOVD. Removing or updating one
/// model cannot remove the other's weights, rollback copy, or saved videos.
actor NeodragonInstaller {
    let root: URL
    var installed: URL { root.appendingPathComponent("Installed", isDirectory: true) }
    init(root: URL) { self.root = root }

    func isInstalled() -> Bool { (try? NeodragonEngine.validateInstallation(at: installed)) != nil }

    func remove() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func install(_ manifest: NeodragonManifest, benchmark: BenchmarkLog?,
                 stage: @escaping @Sendable (ModelInstallationStage) -> Void,
                 progress: @escaping @Sendable (GenerationProgress) -> Void) async throws {
        try manifest.validate()
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var excludedRoot = root, resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(resources)
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        let extracting = root.appendingPathComponent("Extracting", isDirectory: true)
        // Interrupted preparation is rebuilt, but completed downloads are reused.
        // Measure free space after removing abandoned preparation and avoid asking
        // for the same archive storage again when resuming a large installation.
        for directory in [staging, extracting] where fm.fileExists(atPath: directory.path) {
            try fm.removeItem(at: directory)
        }
        let cachedBytes = manifest.archives.reduce(Int64(0)) { total, archive in
            let size = try? root.appendingPathComponent(archive.name).resourceValues(forKeys: [.fileSizeKey]).fileSize
            return total + min(Int64(size ?? 0), archive.bytes)
        }
        let requiredFreeBytes = max(0, manifest.minimumFreeBytes - cachedBytes)
        let free = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free >= requiredFreeBytes else { throw GenerationError.insufficientStorage }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var completed: Int64 = 0
        for archive in manifest.archives {
            try Task.checkCancellation()
            let zip = root.appendingPathComponent(archive.name)
            let resume = root.appendingPathComponent(archive.name + ".resume")
            let offset = completed
            if !fm.fileExists(atPath: zip.path) {
                stage(.downloading)
                try await ModelDownloader(destination: zip, resumeFile: resume).download(archive.url) { count in
                    progress(.init((Double(offset) + 0.6 * Double(count)) / Double(manifest.downloadBytes), "Downloading Neodragon · \(archive.name)"))
                }
            }
            stage(.verifying)
            progress(.init((Double(offset) + 0.6 * Double(archive.bytes)) / Double(manifest.downloadBytes), "Verifying Neodragon · \(archive.name)"))
            let size = try zip.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let hash = try ModelInstaller.sha256(zip)
            guard size.map(Int64.init) == archive.bytes, hash == archive.sha256 else {
                try? fm.removeItem(at: zip); try? fm.removeItem(at: resume)
                throw ModelInstallError.checksum(archive.name)
            }
            if fm.fileExists(atPath: extracting.path) { try fm.removeItem(at: extracting) }
            defer { try? fm.removeItem(at: extracting) }
            stage(.extracting)
            let extraction = Progress()
            try await withTaskCancellationHandler {
                try fm.unzipItem(at: zip, to: extracting, progress: extraction)
            } onCancel: { extraction.cancel() }
            let expectedRoots = Set(archive.models.map { $0 + ".mlpackage" } + archive.supportFiles.map { String($0.split(separator: "/")[0]) })
            let roots = try fm.contentsOfDirectory(at: extracting, includingPropertiesForKeys: [.isSymbolicLinkKey])
            guard Set(roots.map(\.lastPathComponent)) == expectedRoots else { throw ModelInstallError.invalidArchive }
            guard let entries = fm.enumerator(at: extracting, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) else {
                throw ModelInstallError.invalidArchive
            }
            var expanded: Int64 = 0
            while let entry = entries.nextObject() as? URL {
                let attributes = try entry.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                guard attributes.isSymbolicLink != true else { throw ModelInstallError.invalidArchive }
                if attributes.isRegularFile == true { expanded += Int64(attributes.fileSize ?? 0) }
            }
            guard expanded == archive.expandedBytes else { throw ModelInstallError.invalidArchive }
            for (index, name) in archive.models.enumerated() {
                try Task.checkCancellation()
                stage(.compiling)
                progress(.init((Double(offset) + Double(archive.bytes) * (0.6 + 0.39 * Double(index) / Double(max(archive.models.count, 1)))) / Double(manifest.downloadBytes),
                               "Preparing Neodragon · \(name)"))
                let started = benchmark?.begin(name, phase: "compile")
                do {
                    let compiled = try await MLModel.compileModel(at: extracting.appendingPathComponent(name + ".mlpackage"))
                    defer { try? fm.removeItem(at: compiled) }
                    try fm.moveItem(at: compiled, to: staging.appendingPathComponent(name + ".mlmodelc"))
                    if let started { benchmark?.end(name, phase: "compile", started: started) }
                } catch {
                    if let started { benchmark?.end(name, phase: "compile", started: started, error: error) }
                    throw error
                }
            }
            for path in archive.supportFiles {
                try Task.checkCancellation()
                let destination = staging.appendingPathComponent(path)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard !fm.fileExists(atPath: destination.path) else { throw ModelInstallError.invalidArchive }
                try fm.copyItem(at: extracting.appendingPathComponent(path), to: destination)
            }
            completed += archive.bytes
        }
        try Task.checkCancellation()
        let installedMetadata = try NeodragonEngine.validateInstallation(at: staging)
        guard installedMetadata.maximumSeconds == manifest.maximumSeconds,
              Set(installedMetadata.modelNames) == Set(manifest.archives.flatMap(\.models)) else { throw ModelInstallError.invalidArchive }
        try ModelActivation.activate(staging: staging, installed: installed)
        for archive in manifest.archives {
            for suffix in ["", ".resume", ".resume.source"] { try? fm.removeItem(at: root.appendingPathComponent(archive.name + suffix)) }
        }
        stage(.complete)
        progress(.init(1, "Optional Neodragon model installed"))
    }
}
