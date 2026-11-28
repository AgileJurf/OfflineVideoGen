import Foundation

/// Files contains copies only. Models, settings and the live library stay private.
actor LocalExports {
    struct Source: Sendable {
        let url: URL
        let folder: Folder
        let filename: String
        var key: String { folder.rawValue + "/" + filename }
    }
    enum Folder: String, CaseIterable, Sendable { case videos = "Videos", benchmarks = "Benchmarks" }
    nonisolated let root: URL
    private let historyURL: URL
    private var history: [String: String]?

    init(root: URL, historyURL: URL) { self.root = root; self.historyURL = historyURL }

    /// Automatic publishing respects copies moved/deleted in Files. An explicit
    /// export can restore them. Existing user-edited files are never overwritten.
    func publish(_ sources: [Source], explicit: Bool = false) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        for folder in Folder.allCases {
            let url = root.appendingPathComponent(folder.rawValue, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        }
        if history == nil {
            history = (try? Data(contentsOf: historyURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        }
        var results: [URL] = []
        for source in sources {
            guard source.filename == URL(fileURLWithPath: source.filename).lastPathComponent,
                  !source.filename.hasPrefix("."), !source.filename.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
            if !explicit, history?[source.key] != nil { continue }
            let directory = root.appendingPathComponent(source.folder.rawValue, isDirectory: true)
            let remembered = history?[source.key].map { URL(fileURLWithPath: $0).lastPathComponent }
            let preferred = directory.appendingPathComponent(remembered ?? source.filename)
            var coordinationError: NSError?
            var outcome: Result<URL, Error>?
            NSFileCoordinator().coordinate(writingItemAt: directory, options: .forMerging, error: &coordinationError) { coordinated in
                outcome = Result {
                    var destination = coordinated.appendingPathComponent(preferred.lastPathComponent)
                    var suffix = 2
                    let digest = try FileIntegrity.sha256(source.url)
                    while fm.fileExists(atPath: destination.path) {
                        let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        if values.isRegularFile == true, values.isSymbolicLink != true,
                           (try? FileIntegrity.sha256(destination)) == digest { return destination }
                        let base = URL(fileURLWithPath: source.filename)
                        destination = coordinated.appendingPathComponent("\(base.deletingPathExtension().lastPathComponent) (\(suffix)).\(base.pathExtension)")
                        suffix += 1
                    }
                    let staging = coordinated.appendingPathComponent(".\(UUID().uuidString).partial")
                    defer { try? fm.removeItem(at: staging) }
                    try fm.copyItem(at: source.url, to: staging)
                    try fm.moveItem(at: staging, to: destination)
                    return destination
                }
            }
            if let coordinationError { throw coordinationError }
            guard let outcome else { throw CocoaError(.fileWriteUnknown) }
            let destination = try outcome.get()
            history?[source.key] = source.folder.rawValue + "/" + destination.lastPathComponent
            try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history ?? [:]).write(to: historyURL, options: .atomic)
            results.append(destination)
        }
        return results
    }
}
