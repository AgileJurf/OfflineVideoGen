import Foundation
import SwiftUI

protocol SupportTransport: Sendable {
    func request(_ request: URLRequest, maximumBytes: Int) async throws -> (Data, Int)
}

/// Separate from Core ML and the multi-GB model downloader. Requests are explicit, Wi-Fi only,
/// bounded, cookie-free and never redirected to another recipient.
final class SupportHTTPTransport: NSObject, SupportTransport, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func request(_ request: URLRequest, maximumBytes: Int) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw SupportError.unavailable }
        guard response.expectedContentLength <= maximumBytes else { throw SupportError.tooLarge }
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else { throw SupportError.invalidConfiguration }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw SupportError.tooLarge }
            data.append(byte)
        }
        return (data, response.statusCode)
    }
}

@MainActor
final class OnlineSupport: ObservableObject {
    // This is the public support origin only. No API key, user credential or model prompt is sent.
    static let origin = URL(string: "https://localframes-support.vercel.app")!
    @Published var enabled = false { didSet { persistPreference(); if !enabled { cancel() } } }
    @Published private(set) var busy = false
    @Published private(set) var snapshot: SupportSnapshot?
    @Published var message: String?
    private let cache: SupportCache
    private let transport: any SupportTransport
    private let appVersion: String
    private let preferenceURL: URL
    private var preferencesLoaded = false
    private var refreshTask: Task<SupportSnapshot, Error>?
    private var uploadTask: Task<Void, Error>?
    private struct Preferences: Codable { let enabled: Bool }

    init(directory: URL, transport: any SupportTransport = SupportHTTPTransport(), appVersion: String = SupportCompatibility.appVersion) {
        cache = SupportCache(directory: directory)
        self.transport = transport; self.appVersion = appVersion
        preferenceURL = directory.appendingPathComponent("preferences.json")
        snapshot = cache.read(appVersion: appVersion)
        if let data = try? Data(contentsOf: preferenceURL), let pref = try? JSONDecoder().decode(Preferences.self, from: data) { enabled = pref.enabled }
        preferencesLoaded = true
    }
    var configuration: SupportConfiguration? { snapshot?.configuration ?? (try? SupportConfiguration.bundled()) }
    var installationManifest: ModelManifest? { snapshot?.manifest ?? (try? ModelManifest.bundled()) }
    var catalogLabel: String { snapshot == nil ? "Bundled offline defaults" : "Last verified online catalog" }
    private func persistPreference() {
        guard preferencesLoaded else { return }
        do {
            try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Preferences(enabled: enabled)).write(to: preferenceURL, options: .atomic)
        } catch { message = "This selection could not be saved. Online support remains optional." }
    }
    func cancel() { refreshTask?.cancel(); uploadTask?.cancel() }

    func refresh() async {
        guard enabled, !busy else { message = SupportError.disabled.localizedDescription; return }
        busy = true; message = nil
        let transport = self.transport, appVersion = self.appVersion
        let task = Task<SupportSnapshot, Error> {
            let request = URLRequest(url: Self.origin.appendingPathComponent("api/v1/config.json"), cachePolicy: .reloadIgnoringLocalCacheData)
            let (data, status) = try await transport.request(request, maximumBytes: 32 * 1024)
            guard status == 200 else { throw SupportError.unavailable }
            let config = try JSONDecoder().decode(SupportConfiguration.self, from: data)
            try config.validate(appVersion: appVersion)
            try Task.checkCancellation()
            let url = Self.origin.appendingPathComponent(String(config.modelManifestPath.dropFirst()))
            let (manifestData, manifestStatus) = try await transport.request(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData), maximumBytes: 64 * 1024)
            guard manifestStatus == 200 else { throw SupportError.unavailable }
            let manifest = try JSONDecoder().decode(ModelManifest.self, from: manifestData)
            let result = SupportSnapshot(configuration: config, manifest: manifest, checkedAt: Date())
            try result.validate(appVersion: appVersion)
            try Task.checkCancellation()
            return result
        }
        refreshTask = task
        defer { refreshTask = nil; busy = false }
        do {
            let result = try await task.value
            guard enabled, !task.isCancelled else { throw CancellationError() }
            try cache.write(result, appVersion: appVersion)
            snapshot = result
            message = "Catalog verified and saved for offline use. MOVD v1 is the compatible model; no replacement weights or faster preset is available."
        } catch is CancellationError { message = "Support request cancelled. Offline configuration is unchanged." }
        catch { message = (error as? SupportError)?.localizedDescription ?? SupportError.unavailable.localizedDescription }
    }

    func send(_ report: DiagnosticReport, consent: Bool) async throws {
        guard consent else { throw SupportError.consentRequired }
        guard enabled, !busy else { throw SupportError.disabled }
        guard configuration?.diagnostics.enabled == true else { throw SupportError.unavailable }
        let body = try report.encoded()
        busy = true
        let transport = self.transport
        let task = Task<Void, Error> {
            try Task.checkCancellation()
            var request = URLRequest(url: Self.origin.appendingPathComponent("api/v1/diagnostics"), cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpMethod = "POST"; request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("report-v1", forHTTPHeaderField: "X-LocalFrames-Consent")
            let (data, status) = try await transport.request(request, maximumBytes: 4096)
            if status == 429 { throw SupportError.rateLimited }
            guard status == 201, let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  response["status"] as? String == "stored", response["retentionDays"] as? Int == 30 else { throw SupportError.unavailable }
        }
        uploadTask = task
        defer { uploadTask = nil; busy = false }
        try await task.value
    }
}
