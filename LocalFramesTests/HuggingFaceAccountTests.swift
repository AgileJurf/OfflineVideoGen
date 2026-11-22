import Foundation
import XCTest
@testable import LocalFrames

final class HuggingFaceAccountTests: XCTestCase {
    func testQuotaReadingsIncludeZeroBalanceAndProviderResetDate() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let zero = try HFQuotaSnapshot.parse(Data(#"{"base":300,"current":0,"resetsAt":"2026-11-22T20:30:00.123Z","overquotaUsed":0}"#.utf8), checkedAt: now)
        XCTAssertEqual(zero.remaining, 0); XCTAssertEqual(zero.checkedAt, now)
        XCTAssertNotNil(zero.resetsAt); XCTAssertFalse(zero.canSubmit)
        let unused = try HFQuotaSnapshot.parse(Data(#"{"base":300,"current":300,"resetsAt":null}"#.utf8), checkedAt: now)
        XCTAssertNil(unused.resetsAt); XCTAssertTrue(unused.canSubmit)
        for invalid in [#"{"base":300,"current":-1}"#, #"{"base":300,"current":301}"#,
                        #"{"base":300,"current":90,"runs":{"remaining":-1}}"#,
                        #"{"base":300,"current":90,"resetsAt":"tomorrow"}"#] {
            XCTAssertThrowsError(try HFQuotaSnapshot.parse(Data(invalid.utf8), checkedAt: now))
        }
    }

    func testQuotaReadCanShowExhaustionWithoutAuthorizingUpload() async throws {
        let store = MemoryHFStore(); try store.write(credential())
        let zero = Data(#"{"base":300,"current":0,"resetsAt":"2026-11-22T20:30:00Z"}"#.utf8)
        let transport = FakeHFTransport([.init(status: 200, data: try profile()), .init(status: 200, data: zero),
                                         .init(status: 200, data: try profile()), .init(status: 200, data: zero)])
        let client = HFAccountClient(transport: transport, store: store)
        let quota = try await client.quota()
        XCTAssertEqual(quota?.remaining, 0)
        do { _ = try await client.authorizedToken(); XCTFail() } catch HFAccountError.quota { }
        let count = await transport.count; XCTAssertEqual(count, 4)
    }

    @MainActor func testQuotaRefreshDoesNothingWhenSupportIsOffAndKeepsLastReadingOnFailure() async throws {
        let store = MemoryHFStore(); try store.write(credential())
        let transport = FakeHFTransport([.init(status: 200, data: try profile()), .init(status: 200, data: quota),
                                         .init(status: 503, data: Data())])
        let model = HFAccountModel(client: HFAccountClient(transport: transport, store: store))
        await model.restore(); model.refreshQuota(enabled: false)
        var count = await transport.count; XCTAssertEqual(count, 0)
        model.refreshQuota(enabled: true)
        while model.quotaBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.quota?.remaining, 120)
        let date = model.quota?.checkedAt
        model.refreshQuota(enabled: true)
        while model.quotaBusy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(model.quota?.checkedAt, date)
        XCTAssertTrue(model.quotaMessage?.contains("last reading") == true)
        model.disconnect()
        while model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(model.quota)
        count = await transport.count; XCTAssertEqual(count, 3)
    }

    @MainActor func testOpeningProviderToApproveDoesNotDiscardDeviceChallenge() async throws {
        let clock = HFTestClock(), store = MemoryHFStore()
        let transport = FakeHFTransport([.init(status: 200, data: challenge),
                                        .init(status: 200, data: try tokenReply()), .init(status: 200, data: try profile())])
        let account = HFAccountModel(client: HFAccountClient(transport: transport, store: store, now: { clock.now }))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(root: root, helperAccount: account)
        await app.load(); app.support.enabled = true
        account.begin()
        while account.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(account.challenge)
        app.sceneChanged(.background)
        XCTAssertNotNil(account.challenge, "Leaving to approve on Hugging Face must retain the device code")
        clock.advance(6); app.sceneChanged(.active); account.finish()
        while account.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(account.name, "test-user")
        XCTAssertNotNil(try store.read())
    }

    private let token = "hf_oauth_FAKE_TEST_TOKEN_ONLY"
    private func profile(_ changes: [String: Any] = [:]) throws -> Data {
        var value: [String: Any] = ["sub": "synthetic-user", "preferred_username": "test-user", "isPro": false,
                                   "canPay": false, "groups": [String](), "orgs": [[String: Any]]()]
        value.merge(changes) { _, new in new }; return try JSONSerialization.data(withJSONObject: value)
    }
    private var quota: Data { Data(#"{"base":300,"current":120,"overquotaUsed":0,"resetsAt":null,"runs":{"remaining":2}}"#.utf8) }
    private func credential() -> HFCredential {
        HFCredential(accessToken: token, expiresAt: Date().addingTimeInterval(3600), subject: "synthetic-user", username: "test-user")
    }
    private var challenge: Data {
        Data(#"{"device_code":"private-device-code-test-only","user_code":"ABCD-EFGH","verification_uri":"https://hf.co/oauth/device","expires_in":300,"interval":5}"#.utf8)
    }
    private func tokenReply(scope: String = HFAccountClient.scopes) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["access_token": token, "token_type": "Bearer", "expires_in": 28800, "scope": scope])
    }

    func testFreeOnlyGateRejectsPaidUnknownAndOrganizationAccounts() throws {
        XCTAssertNoThrow(try HFAccountClient.requireFree(profile()))
        for change: [String: Any] in [["isPro": true], ["canPay": true], ["canPay": NSNull()],
                                     ["groups": ["org"]], ["orgs": [["plan": "team"]]], ["sub": ""]] {
            XCTAssertThrowsError(try HFAccountClient.requireFree(profile(change)))
        }
        XCTAssertThrowsError(try HFAccountClient.requireFree(Data(#"{"isPro":false}"#.utf8)))
        XCTAssertNoThrow(try HFAccountClient.requireQuota(quota))
        for value in [#"{"base":300,"current":89}"#, #"{"base":2400,"current":2400}"#,
                      #"{"base":300,"current":120,"overquotaUsed":1}"#,
                      #"{"base":300,"current":120,"runs":{"remaining":0}}"#, #"{}"#] {
            XCTAssertThrowsError(try HFAccountClient.requireQuota(Data(value.utf8)))
        }
    }

    func testNoCredentialMeansNoAccountRequestAndExpiredCredentialNeverFallsBack() async throws {
        let store = MemoryHFStore(), transport = FakeHFTransport([]), client = HFAccountClient(transport: transport, store: store)
        let anonymous = try await client.authorizedToken(); XCTAssertNil(anonymous)
        var count = await transport.count; XCTAssertEqual(count, 0)
        try store.write(HFCredential(accessToken: token, expiresAt: .distantPast, subject: "synthetic-user", username: "test-user"))
        do { _ = try await client.authorizedToken(); XCTFail() } catch HFAccountError.expired { }
        count = await transport.count; XCTAssertEqual(count, 0)
    }

    func testEveryAuthorizedUploadRechecksFreePlanIdentityAndQuota() async throws {
        let store = MemoryHFStore(); try store.write(credential())
        let transport = FakeHFTransport([.init(status: 200, data: try profile()), .init(status: 200, data: quota),
                                         .init(status: 200, data: try profile(["isPro": true]))])
        let client = HFAccountClient(transport: transport, store: store)
        let approved = try await client.authorizedToken(); XCTAssertEqual(approved, token)
        do { _ = try await client.authorizedToken(); XCTFail() } catch HFAccountError.notFree { }
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/oauth/userinfo", "/api/spaces/zero-gpu/quota", "/oauth/userinfo"])
        XCTAssertTrue(requests.allSatisfy { $0.url!.host == "huggingface.co" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        try await client.disconnect(); XCTAssertNil(try store.read())
        let again = try await client.authorizedToken(); XCTAssertNil(again)
        let count = await transport.count; XCTAssertEqual(count, 3)
    }

    func testDeviceFlowHonorsPendingIntervalAndStoresOnlyVerifiedScopedConnection() async throws {
        let clock = HFTestClock(), store = MemoryHFStore()
        let transport = FakeHFTransport([.init(status: 200, data: challenge),
            .init(status: 400, data: Data(#"{"error":"authorization_pending"}"#.utf8)),
            .init(status: 200, data: try tokenReply()), .init(status: 200, data: try profile())])
        let client = HFAccountClient(transport: transport, store: store, now: { clock.now })
        let code = try await client.begin(); XCTAssertEqual(code.userCode, "ABCD-EFGH")
        XCTAssertEqual(code.verificationURL.absoluteString, "https://huggingface.co/oauth/device")
        do { _ = try await client.finish(); XCTFail() } catch HFAccountError.pending { }
        var count = await transport.count; XCTAssertEqual(count, 1, "No early poll")
        clock.advance(6)
        do { _ = try await client.finish(); XCTFail() } catch HFAccountError.pending { }
        XCTAssertNil(try store.read()); clock.advance(6)
        let name = try await client.finish(); XCTAssertEqual(name, "test-user")
        XCTAssertEqual(try store.read()?.accessToken, token)
        count = await transport.count; XCTAssertEqual(count, 4)
        let requests = await transport.requests
        XCTAssertTrue(requests[0].httpBody.map { String(decoding: $0, as: UTF8.self).contains("read-billing") } ?? false)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(String(decoding: requests[0].httpBody!, as: UTF8.self).contains("client_secret"))
    }

    func testCancelledOrOverScopedSignInCannotCreateCredential() async throws {
        let clock = HFTestClock(), store = MemoryHFStore()
        let transport = FakeHFTransport([.init(status: 200, data: challenge), .init(status: 200, data: challenge),
                                         .init(status: 200, data: try tokenReply(scope: HFAccountClient.scopes + " write-repos"))])
        let client = HFAccountClient(transport: transport, store: store, now: { clock.now })
        _ = try await client.begin(); await client.cancelSignIn(); clock.advance(6)
        do { _ = try await client.finish(); XCTFail() } catch HFAccountError.expired { }
        XCTAssertNil(try store.read())
        _ = try await client.begin(); clock.advance(6)
        do { _ = try await client.finish(); XCTFail() } catch HFAccountError.unavailable { }
        XCTAssertNil(try store.read()); let count = await transport.count; XCTAssertEqual(count, 3)
    }

    func testQuotaIdentityAndAuthenticationFailuresAreFailClosed() async throws {
        for (responses, expected) in [
            ([HFResponse(status: 200, data: try profile()), HFResponse(status: 200, data: Data(#"{"base":300,"current":61}"#.utf8))], "quota"),
            ([HFResponse(status: 200, data: try profile(["sub":"other-user"]))], "expired"),
            ([HFResponse(status: 401, data: Data())], "expired"),
            ([HFResponse(status: 503, data: Data())], "unavailable")
        ] {
            let store = MemoryHFStore(); try store.write(credential())
            let client = HFAccountClient(transport: FakeHFTransport(responses), store: store)
            do { _ = try await client.authorizedToken(); XCTFail() } catch { XCTAssertEqual(String(describing: error), expected) }
        }
    }
}

private final class MemoryHFStore: HFCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: HFCredential?
    func read() throws -> HFCredential? { lock.lock(); defer { lock.unlock() }; return value }
    func write(_ value: HFCredential) throws { lock.lock(); defer { lock.unlock() }; self.value = value }
    func remove() throws { lock.lock(); defer { lock.unlock() }; value = nil }
}
private final class HFTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
}
private actor FakeHFTransport: HFTransport {
    var requests: [URLRequest] = []
    var responses: [HFResponse]
    var count: Int { requests.count }
    init(_ responses: [HFResponse]) { self.responses = responses }
    func request(_ request: URLRequest) async throws -> HFResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw HFAccountError.unavailable }
        return responses.removeFirst()
    }
}
