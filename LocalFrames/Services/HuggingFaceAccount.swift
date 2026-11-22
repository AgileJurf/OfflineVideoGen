import Combine
import Foundation
import Security

enum HFAccountError: Error, LocalizedError {
    case unavailable, pending, denied, expired, notFree, quota, secureStorage
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Hugging Face could not verify this connection. Check Wi-Fi and try again. No clip was uploaded."
        case .pending: return "Approve Local Frames on Hugging Face, then return here and finish connecting."
        case .denied: return "The connection was not approved. Your videos remain local."
        case .expired: return "This Hugging Face connection expired. Connect again before smoothing."
        case .notFree: return "This beta only uses a verified free personal account with no billing access or organization memberships. Paid or unverifiable accounts are blocked. No clip was uploaded."
        case .quota: return "Your free GPU allowance cannot cover this job yet. Wait for your Hugging Face quota to reset. No clip was uploaded and nothing will retry automatically."
        case .secureStorage: return "The connection could not be stored securely. Connect again after unlocking your device."
        }
    }
}

struct HFResponse: Sendable { let status: Int; let data: Data }
protocol HFTransport: Sendable { func request(_ request: URLRequest) async throws -> HFResponse }

/// Only the documented Hub authentication, identity and quota endpoints. No redirects or cookies.
final class HFHTTPTransport: NSObject, HFTransport, URLSessionTaskDelegate, @unchecked Sendable {
    static let paths: Set<String> = ["/oauth/device", "/oauth/token", "/oauth/userinfo", "/api/spaces/zero-gpu/quota"]
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    func request(_ request: URLRequest) async throws -> HFResponse {
        guard let url = request.url, url.scheme == "https", url.host == "huggingface.co", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, Self.paths.contains(url.path),
              request.value(forHTTPHeaderField: "Cookie") == nil else { throw HFAccountError.unavailable }
        let config = RIFEHTTPTransport.configuration()
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, [200, 400, 401, 403, 429].contains(response.statusCode),
              response.mimeType == "application/json", response.expectedContentLength <= 64 * 1024 else { throw HFAccountError.unavailable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 64 * 1024 else { throw HFAccountError.unavailable }
            data.append(byte)
        }
        return HFResponse(status: response.statusCode, data: data)
    }
}

struct HFCredential: Codable, Sendable {
    let accessToken: String
    let expiresAt: Date
    let subject: String
    let username: String
}
protocol HFCredentialStore: Sendable {
    func read() throws -> HFCredential?
    func write(_ value: HFCredential) throws
    func remove() throws
}
struct HFKeychainStore: HFCredentialStore {
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.agilejurf.localframes.huggingface", kSecAttrAccount as String: "free-helper"] }
    func read() throws -> HFCredential? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = try? JSONDecoder().decode(HFCredential.self, from: data) else { throw HFAccountError.secureStorage }
        return value
    }
    func write(_ value: HFCredential) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw HFAccountError.secureStorage }
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else { throw HFAccountError.secureStorage }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw HFAccountError.secureStorage }
    }
}

struct HFDeviceChallenge: Sendable {
    fileprivate let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    fileprivate let interval: TimeInterval
}

protocol RIFECredentials: Sendable { func authorizedToken() async throws -> String? }
struct AnonymousRIFECredentials: RIFECredentials { func authorizedToken() async throws -> String? { nil } }

/// A dated provider reading, never a locally estimated balance or an upload authorization.
struct HFQuotaSnapshot: Equatable, Sendable {
    static let helperRequiredSeconds: Double = 90
    let total: Double
    let remaining: Double
    let resetsAt: Date?
    let remainingRuns: Double?
    let checkedAt: Date
    var canSubmit: Bool { remaining >= Self.helperRequiredSeconds && (remainingRuns.map { $0 >= 1 } ?? true) }

    static func parse(_ data: Data, checkedAt: Date) throws -> Self {
        struct Reply: Decodable {
            let base: Double; let current: Double; let overquotaUsed: Double?
            let resetsAt: String?; let runs: Runs?
        }
        struct Runs: Decodable { let remaining: Double }
        guard let value = try? JSONDecoder().decode(Reply.self, from: data),
              value.base.isFinite, value.current.isFinite, value.base > 0, value.base <= 300,
              value.current >= 0, value.current <= value.base, (value.overquotaUsed ?? 0) == 0,
              value.runs.map({ $0.remaining.isFinite && $0.remaining >= 0 }) ?? true else { throw HFAccountError.notFree }
        var reset: Date?
        if let text = value.resetsAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            reset = formatter.date(from: text)
            if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: text) }
            guard reset != nil else { throw HFAccountError.unavailable }
        }
        return Self(total: value.base, remaining: value.current, resetsAt: reset,
                    remainingRuns: value.runs?.remaining, checkedAt: checkedAt)
    }
}

actor HFAccountClient: RIFECredentials {
    // Registered public client: no client secret, repository access or paid inference scopes.
    static let clientID = "fa5e78af-cabb-485e-9cd8-6f1238e1c52c"
    static let scopes = "openid profile read-billing read-memberships"
    private let transport: any HFTransport
    private let store: any HFCredentialStore
    private let now: @Sendable () -> Date
    private var challenge: HFDeviceChallenge?
    private var nextPoll = Date.distantPast
    private var pollInterval: TimeInterval = 5
    private var revision = 0
    init(transport: any HFTransport = HFHTTPTransport(), store: any HFCredentialStore = HFKeychainStore(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport; self.store = store; self.now = now
    }
    func connectedName() throws -> String? {
        guard let value = try store.read(), value.expiresAt > now() else { return nil }
        return value.username
    }
    private func request(_ path: String, fields: [String: String]? = nil, token: String? = nil) async throws -> HFResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://huggingface.co" + path)!)
        if let fields {
            request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            request.httpBody = fields.sorted { $0.key < $1.key }.map {
                $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
            }.joined(separator: "&").data(using: .utf8)
        }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return try await transport.request(request)
    }
    func begin() async throws -> HFDeviceChallenge {
        revision += 1; let current = revision; challenge = nil
        let response = try await request("/oauth/device", fields: ["client_id": Self.clientID, "scope": Self.scopes])
        struct Reply: Decodable { let device_code: String; let user_code: String; let verification_uri: String; let expires_in: Double; let interval: Double? }
        guard response.status == 200, let reply = try? JSONDecoder().decode(Reply.self, from: response.data),
              reply.device_code.count >= 16, reply.device_code.count <= 4096,
              reply.user_code.range(of: #"^[A-Za-z0-9-]{4,32}$"#, options: .regularExpression) != nil,
              let url = URL(string: reply.verification_uri), url.scheme == "https", ["huggingface.co", "hf.co"].contains(url.host ?? ""),
              url.path == "/oauth/device", url.port == nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              reply.expires_in.isFinite, (30...1800).contains(reply.expires_in), current == revision else { throw HFAccountError.unavailable }
        try Task.checkCancellation()
        // The live API returns the official hf.co short domain. Present the canonical provider URL.
        let value = HFDeviceChallenge(deviceCode: reply.device_code, userCode: reply.user_code, verificationURL: URL(string: "https://huggingface.co/oauth/device")!,
                                      expiresAt: now().addingTimeInterval(reply.expires_in), interval: max(5, min(reply.interval ?? 5, 60)))
        challenge = value; pollInterval = value.interval; nextPoll = now().addingTimeInterval(value.interval)
        return value
    }
    func finish() async throws -> String {
        guard let challenge, challenge.expiresAt > now() else { throw HFAccountError.expired }
        guard now() >= nextPoll else { throw HFAccountError.pending }
        nextPoll = now().addingTimeInterval(pollInterval)
        let current = revision
        let response = try await request("/oauth/token", fields: ["client_id": Self.clientID,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": challenge.deviceCode])
        if response.status != 200 {
            struct Failure: Decodable { let error: String }
            switch (try? JSONDecoder().decode(Failure.self, from: response.data))?.error {
            case "authorization_pending": throw HFAccountError.pending
            case "slow_down": pollInterval += 5; nextPoll = now().addingTimeInterval(pollInterval); throw HFAccountError.pending
            case "access_denied": self.challenge = nil; throw HFAccountError.denied
            case "expired_token": self.challenge = nil; throw HFAccountError.expired
            default: throw HFAccountError.unavailable
            }
        }
        struct Token: Decodable { let access_token: String; let token_type: String; let expires_in: Double; let scope: String }
        guard let token = try? JSONDecoder().decode(Token.self, from: response.data), token.token_type.lowercased() == "bearer",
              Self.validToken(token.access_token), token.expires_in.isFinite, token.expires_in >= 180,
              Set(token.scope.split(separator: " ")) == Set(Self.scopes.split(separator: " ")) else { throw HFAccountError.unavailable }
        let profile = try await freeProfile(token.access_token)
        try Task.checkCancellation()
        guard current == revision else { throw CancellationError() }
        try store.write(HFCredential(accessToken: token.access_token, expiresAt: now().addingTimeInterval(min(token.expires_in, 86400)),
                                     subject: profile.sub, username: profile.preferred_username ?? "Free account"))
        self.challenge = nil
        return profile.preferred_username ?? "Free account"
    }
    static func validToken(_ token: String) -> Bool {
        token.range(of: #"^hf_[A-Za-z0-9_.-]{12,8192}$"#, options: .regularExpression) != nil
    }
    struct Profile: Decodable { let sub: String; let preferred_username: String?; let isPro: Bool; let canPay: Bool?; let groups: [String]; let orgs: [Organization] }
    struct Organization: Decodable { }
    static func requireFree(_ data: Data) throws -> Profile {
        guard let profile = try? JSONDecoder().decode(Profile.self, from: data), !profile.sub.isEmpty,
              profile.canPay == false, !profile.isPro, profile.groups.isEmpty, profile.orgs.isEmpty else { throw HFAccountError.notFree }
        return profile
    }
    private func freeProfile(_ token: String) async throws -> Profile {
        let response = try await request("/oauth/userinfo", token: token)
        if response.status == 401 || response.status == 403 { throw HFAccountError.expired }
        guard response.status == 200 else { throw HFAccountError.unavailable }
        return try Self.requireFree(response.data)
    }
    static func requireQuota(_ data: Data) throws {
        guard try HFQuotaSnapshot.parse(data, checkedAt: Date()).canSubmit else { throw HFAccountError.quota }
    }
    private func verifiedQuota() async throws -> (HFCredential, HFQuotaSnapshot)? {
        guard let value = try store.read() else { return nil }
        guard value.expiresAt > now().addingTimeInterval(180), Self.validToken(value.accessToken) else { throw HFAccountError.expired }
        let current = revision, profile = try await freeProfile(value.accessToken)
        guard profile.sub == value.subject else { throw HFAccountError.expired }
        let response = try await request("/api/spaces/zero-gpu/quota", token: value.accessToken)
        if response.status == 401 || response.status == 403 { throw HFAccountError.expired }
        guard response.status == 200 else { throw HFAccountError.unavailable }
        let quota = try HFQuotaSnapshot.parse(response.data, checkedAt: now())
        try Task.checkCancellation()
        guard revision == current else { throw CancellationError() }
        return (value, quota)
    }
    func quota() async throws -> HFQuotaSnapshot? { try await verifiedQuota()?.1 }
    func authorizedToken() async throws -> String? {
        guard let (value, quota) = try await verifiedQuota() else { return nil }
        guard quota.canSubmit else { throw HFAccountError.quota }
        return value.accessToken
    }
    func cancelSignIn() { revision += 1; challenge = nil }
    func disconnect() throws { revision += 1; challenge = nil; try store.remove() }
}

@MainActor final class HFAccountModel: ObservableObject {
    @Published private(set) var name: String?
    @Published private(set) var challenge: HFDeviceChallenge?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    @Published private(set) var quota: HFQuotaSnapshot?
    @Published private(set) var quotaMessage: String?
    @Published private(set) var quotaBusy = false
    let client: HFAccountClient
    private var operation: Task<Void, Never>?
    private var quotaOperation: Task<Void, Never>?
    private var revision = 0
    private var quotaRevision = 0
    init(client: HFAccountClient = HFAccountClient()) { self.client = client }
    func restore() async { name = try? await client.connectedName() }
    func begin() { perform { self.challenge = try await self.client.begin(); self.message = "Open Hugging Face and enter this code, approve the connection, then return here." } }
    func finish() { perform { self.name = try await self.client.finish(); self.challenge = nil; self.message = "Connected. Free-account status and quota are checked again before each approved clip upload." } }
    func disconnect() {
        cancelQuotaRefresh(); quota = nil; quotaMessage = nil
        perform { try await self.client.disconnect(); self.name = nil; self.challenge = nil; self.message = "Disconnected on this device. You can also revoke Local Frames in Hugging Face’s application settings." }
    }
    func refreshQuota(enabled: Bool) {
        guard enabled, !quotaBusy, !busy else { return }
        quotaBusy = true; quotaMessage = nil; let current = quotaRevision
        quotaOperation = Task {
            defer { if current == quotaRevision { quotaBusy = false; quotaOperation = nil } }
            do {
                let reading = try await client.quota()
                try Task.checkCancellation()
                guard current == quotaRevision else { return }
                quota = reading
                if reading == nil { quotaMessage = "Connect a free account to see its balance. Anonymous access uses a shared allowance that this app cannot measure." }
            } catch is CancellationError { }
            catch {
                if current == quotaRevision {
                    let reason: String
                    switch error as? HFAccountError {
                    case .expired: reason = "Reconnect your free Hugging Face account."
                    case .notFree: reason = "The provider could not verify a free personal account."
                    default: reason = "Check your connection and try again."
                    }
                    quotaMessage = "Could not refresh. Any balance below is the last reading, not a current allowance. " + reason
                }
            }
        }
    }
    func cancelQuotaRefresh() {
        quotaRevision += 1; quotaOperation?.cancel(); quotaOperation = nil; quotaBusy = false
    }
    func cancel() {
        revision += 1; operation?.cancel(); operation = nil; busy = false; challenge = nil
        cancelQuotaRefresh()
        Task { await client.cancelSignIn() }
    }
    private func perform(_ body: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; message = nil; let current = revision
        operation = Task {
            defer { if current == revision { busy = false; operation = nil } }
            do { try await body() }
            catch is CancellationError { }
            catch { if current == revision { message = (error as? HFAccountError)?.localizedDescription ?? HFAccountError.unavailable.localizedDescription } }
        }
    }
}
