import Foundation
import Security

/// Removal inventory audited against Build 44's installer. Never search by a
/// broad name or delete Documents, Library, OptionalModels, or a shared cache.
actor LegacyMigration {
    struct Entry: Codable, Equatable, Sendable {
        let path: String
        let logicalBytes: Int64
        let allocatedBytes: Int64
    }
    struct Report: Codable, Sendable {
        var version = 1
        var completed = false
        var entries: [Entry] = []
        var pending: Entry?
        var skipped: [String] = []
        var freeBefore: Int64?
        var freeAfter: Int64?
        var completedAt: Date?
        var removedBytes: Int64 { entries.reduce(0) { $0 + $1.logicalBytes } }
        var removedAllocatedBytes: Int64 { entries.reduce(0) { $0 + $1.allocatedBytes } }
    }
    let root: URL
    private var reportURL: URL { root.appendingPathComponent("Migrations/retirement-v1.json") }
    init(root: URL) { self.root = root }

    static let retiredRevision = "cc1839814d0e1b0cb01953831a55a557ff6682bf"
    static var retiredPartitions: [String] {
        ["t5embed-tokens", "t5final-layer-norm", "stdit3_part1", "stdit3_part2"]
        + (0..<24).map { "t5block-layer\($0)" }
        + (0..<28).map { "stdit3_ST_\($0)" }
        + (0..<28).map { "stdit3_TDTM_\($0)" }
        + ["vae_temporal_part1", "vae_temporal_part2_1", "vae_temporal_part2_2", "vae_temporal_part2_3_1", "vae_temporal_part2_3_2", "vae_temporal_part2_3_3", "vae_temporal_part2_3_4", "vae_temporal_part2_4", "vae_temporal_part3", "vae_spatial_part1", "vae_spatial_part2", "vae_spatial_part3_1", "vae_spatial_part3_2", "vae_spatial_part3_3", "vae_spatial_part3_4_1", "vae_spatial_part3_4_2", "vae_spatial_part3_4_3", "vae_spatial_part4"]
    }
    func run(removeCredential: Bool = true) throws -> Report {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var report: Report
        if fm.fileExists(atPath: reportURL.path) {
            report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: reportURL))
            guard report.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        } else { report = Report() }
        if report.completed { return report }
        if report.freeBefore == nil { report.freeBefore = availableBytes() }
        var paths: [String] = []
        for folder in ["Installed", "RollbackInstalled", "Staging", "Extracting"] {
            for name in Self.retiredPartitions {
                paths += ["Models/\(folder)/\(name).mlmodelc", "Models/\(folder)/\(name).mlpackage"]
            }
            let marker = root.appendingPathComponent("Models/\(folder)/installation.json")
            if let data = try? Data(contentsOf: marker), (try? JSONDecoder().decode(String.self, from: data)) == Self.retiredRevision {
                paths.append("Models/\(folder)/installation.json")
            }
        }
        for archive in ["STDiT-TDTM.zip", "T5.zip", "VAE.zip"] {
            for suffix in ["", ".resume", ".resume.source"] { paths.append("Models/" + archive + suffix) }
        }
        // Archives can contain a wrapper folder. Only an exact retired package
        // name within the old extraction root is eligible; unknown files stay.
        let extracting = root.appendingPathComponent("Models/Extracting")
        if let children = fm.enumerator(at: extracting, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let package as URL in children {
                if (try? package.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { children.skipDescendants(); continue }
                if ["mlpackage", "mlmodelc"].contains(package.pathExtension) {
                    children.skipDescendants()
                    if Self.retiredPartitions.contains(package.deletingPathExtension().lastPathComponent) {
                        paths.append(String(package.path.dropFirst(root.path.count + 1)))
                    }
                }
            }
        }
        paths += ["OnlineSupport/catalog-v1.json", "OnlineSupport/preferences.json", "pending-smoothing.json", "Benchmarks/timing-cache.data"]
        let pendingBaseline = root.appendingPathComponent("ResumableBaseline/pending.json")
        if let data = try? Data(contentsOf: pendingBaseline),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let id = json["id"] as? String, UUID(uuidString: id) != nil, json["request"] is [String: Any] {
            paths += ["ResumableBaseline/" + id + ".checkpoint", "ResumableBaseline/pending.json"]
        }
        let temporary = root.appendingPathComponent("Temporary")
        for name in (try? fm.contentsOfDirectory(atPath: temporary.path)) ?? [] {
            if name.hasPrefix("Smoothing-"), UUID(uuidString: String(name.dropFirst("Smoothing-".count))) != nil {
                paths.append("Temporary/" + name)
            }
        }
        // A journal is evidence, not permission to remove an arbitrary path.
        // Recover the one interrupted item first, even after its source is gone.
        if let pending = report.pending {
            let checkpoint = pending.path.split(separator: "/").count == 2 && pending.path.hasPrefix("ResumableBaseline/") && pending.path.hasSuffix(".checkpoint")
                && UUID(uuidString: URL(fileURLWithPath: pending.path).deletingPathExtension().lastPathComponent) != nil
            let smoothing = pending.path.hasPrefix("Temporary/Smoothing-")
                && UUID(uuidString: String(pending.path.dropFirst("Temporary/Smoothing-".count))) != nil
            let marker = ["Installed", "RollbackInstalled", "Staging", "Extracting"].contains { pending.path == "Models/\($0)/installation.json" }
            // Missing markers can be acknowledged after an interrupted deletion;
            // existing markers still require the retired revision check above.
            let deletedMarker = marker && !fm.fileExists(atPath: root.appendingPathComponent(pending.path).path)
            let extractedPackage = pending.path.hasPrefix("Models/Extracting/") && !pending.path.split(separator: "/").contains("..")
                && ["mlpackage", "mlmodelc"].contains(URL(fileURLWithPath: pending.path).pathExtension)
                && Self.retiredPartitions.contains(URL(fileURLWithPath: pending.path).deletingPathExtension().lastPathComponent)
            guard paths.contains(pending.path) || checkpoint || smoothing || deletedMarker || extractedPackage || pending.path == "ResumableBaseline/pending.json" else {
                throw CocoaError(.fileReadCorruptFile)
            }
            paths.removeAll { $0 == pending.path }; paths.insert(pending.path, at: 0)
        }
        for path in paths {
            try Task.checkCancellation()
            guard !report.entries.contains(where: { $0.path == path }) else { continue }
            let url = root.appendingPathComponent(path)
            guard isSafe(url) else {
                if !report.skipped.contains(path) { report.skipped.append(path) }
                continue
            }
            let exists = fm.fileExists(atPath: url.path)
            guard exists || report.pending?.path == path else { continue }
            let entry = report.pending?.path == path ? report.pending! : try measured(path: path, url: url)
            report.pending = entry; try save(report)
            if exists { try fm.removeItem(at: url) }
            report.entries.append(entry); report.pending = nil; try save(report)
        }
        if removeCredential {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.agilejurf.localframes.huggingface", kSecAttrAccount as String: "free-helper"]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        }
        report.freeAfter = availableBytes(); report.completed = report.pending == nil
        report.completedAt = Date(); try save(report)
        return report
    }
    private func save(_ report: Report) throws {
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
    }
    private func availableBytes() -> Int64? {
        (try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
    private func isSafe(_ url: URL) -> Bool {
        let fm = FileManager.default
        let base = root.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(base), !url.pathComponents.contains("..") else { return false }
        var cursor = url
        while cursor.path.hasPrefix(root.path) {
            if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return false }
            if cursor == root { break }; cursor.deleteLastPathComponent()
        }
        if let children = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let child as URL in children {
                if (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return false }
            }
        }
        return true
    }
    private func measured(path: String, url: URL) throws -> Entry {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        var logical: Int64 = 0, allocated: Int64 = 0
        func count(_ file: URL) throws {
            let values = try file.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                logical += Int64(values.fileSize ?? 0); allocated += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        try count(url)
        if let children = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) {
            for case let child as URL in children { try count(child) }
        }
        return Entry(path: path, logicalBytes: logical, allocatedBytes: allocated)
    }
}
