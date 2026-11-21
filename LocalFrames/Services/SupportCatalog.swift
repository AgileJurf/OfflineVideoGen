import Foundation
import VideoEngine

enum SupportError: LocalizedError {
    case invalidConfiguration, incompatibleApp, incompatibleModel, unavailable, tooLarge, consentRequired, disabled, rateLimited
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "The support response was not valid. Your previous configuration and installed model are unchanged."
        case .incompatibleApp: return "This catalog requires a newer app. Your installed model remains available offline."
        case .incompatibleModel: return "This model is not approved for this app version. Update the app before installing new model weights."
        case .unavailable: return "Online support is unavailable. Your installed model and local reports are still available."
        case .tooLarge: return "The support response or report exceeded its size limit."
        case .consentRequired: return "Review this report and explicitly consent before sending it."
        case .disabled: return "Enable optional online support before making a support request."
        case .rateLimited: return "The free diagnostic intake is full for this two-hour interval. Nothing is queued; you can choose to try again later."
        }
    }
}

enum SupportCompatibility {
    static let modelVersion = "movd-v1"
    static func version(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    static func requireApp(_ minimum: String, appVersion: String) throws {
        guard let required = version(minimum), let current = version(appVersion) else { throw SupportError.invalidConfiguration }
        guard !current.lexicographicallyPrecedes(required) else { throw SupportError.incompatibleApp }
    }
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
}

struct SupportConfiguration: Codable, Equatable, Sendable {
    struct Profile: Codable, Equatable, Sendable {
        let id: String
        let modelVersion: String
        let diffusionEvaluations: Int
        let guidance: Int
        let width: Int
        let height: Int
        let framesPerSecond: Int
        let validatedDurations: [Int]
        let sampler: String
        let decoderPolicy: String
    }
    struct Diagnostics: Codable, Equatable, Sendable {
        let enabled: Bool
        let path: String
        let maximumBytes: Int
        let retentionDays: Int
        let globalSlotHours: Int
    }
    let schemaVersion: Int
    let configurationVersion: Int
    let minimumAppVersion: String
    let supportedModelVersions: [String]
    let modelManifestPath: String
    let inferenceProfiles: [Profile]
    let diagnostics: Diagnostics

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "support-config", withExtension: "json") else { throw SupportError.invalidConfiguration }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func validate(appVersion: String) throws {
        try SupportCompatibility.requireApp(minimumAppVersion, appVersion: appVersion)
        guard schemaVersion == 1, (1...1_000_000).contains(configurationVersion),
              supportedModelVersions == [SupportCompatibility.modelVersion],
              modelManifestPath == "/api/v1/models/movd-v1.json", inferenceProfiles.count == 1,
              let profile = inferenceProfiles.first,
              profile.id == GenerationProfile.baselineID, profile.modelVersion == SupportCompatibility.modelVersion,
              profile.diffusionEvaluations == GenerationProfile.evaluationCount, profile.guidance == 7,
              profile.width == 256, profile.height == 256, profile.framesPerSecond == 12,
              profile.validatedDurations == [2], profile.sampler == "rectified-flow",
              profile.decoderPolicy == MOVDModel.decoderExecutionPolicy,
              diagnostics.path == "/api/v1/diagnostics", diagnostics.maximumBytes == 32768,
              diagnostics.retentionDays == 30, diagnostics.globalSlotHours == 2 else { throw SupportError.invalidConfiguration }
        // Remote data describes the locally approved profile. It cannot change sampler arithmetic,
        // precision, model contracts, generation availability or existing user selections.
    }
}

struct SupportSnapshot: Codable, Sendable {
    let configuration: SupportConfiguration
    let manifest: ModelManifest
    let checkedAt: Date
    func validate(appVersion: String) throws {
        try configuration.validate(appVersion: appVersion)
        try manifest.validateRemote(appVersion: appVersion)
        guard manifest.modelVersion == configuration.supportedModelVersions.first else { throw SupportError.invalidConfiguration }
    }
}

struct SupportCache {
    let directory: URL
    var url: URL { directory.appendingPathComponent("catalog-v1.json") }
    func read(appVersion: String) -> SupportSnapshot? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128 * 1024,
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(SupportSnapshot.self, from: data),
              (try? value.validate(appVersion: appVersion)) != nil else { return nil }
        return value
    }
    func write(_ snapshot: SupportSnapshot, appVersion: String) throws {
        try snapshot.validate(appVersion: appVersion)
        if let old = read(appVersion: appVersion), old.configuration.configurationVersion > snapshot.configuration.configurationVersion {
            throw SupportError.invalidConfiguration
        }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 128 * 1024 else { throw SupportError.tooLarge }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension ModelManifest {
    func validateRemote(appVersion: String) throws {
        guard schemaVersion == 1, modelVersion == SupportCompatibility.modelVersion,
              let minimumAppVersion, let manifestVersion, (1...1_000_000).contains(manifestVersion) else { throw SupportError.invalidConfiguration }
        try SupportCompatibility.requireApp(minimumAppVersion, appVersion: appVersion)
        let trusted = try Self.bundled()
        guard revision == trusted.revision, minimumFreeBytes >= trusted.minimumFreeBytes,
              minimumFreeBytes <= 200_000_000_000, archives.count == trusted.archives.count else { throw SupportError.incompatibleModel }
        for (file, original) in zip(archives, trusted.archives) {
            guard file.name == original.name, file.bytes == original.bytes, file.expandedBytes == original.expandedBytes,
                  file.sha256 == original.sha256, file.models == original.models,
                  Self.isApprovedDownloadURL(file.url, original: original.url) else { throw SupportError.incompatibleModel }
        }
    }
    static func isApprovedDownloadURL(_ url: URL, original: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil, url.fragment == nil else { return false }
        if url == original { return true }
        // A future mirror must use an immutable Hub commit; weight hashes stay pinned in the app.
        let parts = url.path.split(separator: "/")
        guard url.host == "huggingface.co", url.query == nil, parts.count >= 5,
              parts[2] == "resolve", parts[3].count == 40,
              parts[3].allSatisfy({ "0123456789abcdef".contains($0) }),
              !parts.contains("..") else { return false }
        return true
    }
}
