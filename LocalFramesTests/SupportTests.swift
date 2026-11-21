import Foundation
import XCTest
@testable import LocalFrames
@testable import VideoEngine

final class SupportTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SupportTests-" + UUID().uuidString) }
    private func remoteManifest() throws -> Data {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ModelManifest.bundled())) as! [String: Any]
        json["modelVersion"] = "movd-v1"; json["manifestVersion"] = 1; json["minimumAppVersion"] = "0.1.0"
        return try JSONSerialization.data(withJSONObject: json)
    }
    private func snapshot() throws -> SupportSnapshot {
        SupportSnapshot(configuration: try .bundled(), manifest: try JSONDecoder().decode(ModelManifest.self, from: remoteManifest()), checkedAt: Date())
    }
    private func summary() -> BenchmarkSummary {
        var value = BenchmarkSummary(id: "PRIVATE_FILE_PATH")
        value.kind = "generation"; value.status = "failed"; value.appBuild = "22"; value.appVersion = "0.1.0"; value.osVersion = "27.3.0"
        value.modelRevision = MOVDModel.revision
        value.prompt = "PRIVATE_PROMPT"; value.effectivePrompt = "PRIVATE_PROMPT_STYLE"; value.seed = "PRIVATE_SEED"
        value.failure = "PRIVATE_ERROR_WITH_PERSONAL_PATH"; value.elapsedSeconds = 10.00123
        value.thermalStates = ["nominal", "serious"]; value.errorCategory = "model-load"; value.errorDomain = "CoreML"; value.errorCode = 1
        value.partitions = [PartitionTiming(name: "stdit3_ST_0", loads: 1, loadSeconds: 2, failures: 1)]
        return value
    }

    func testCatalogRejectsChangedHashesInventoryHostsAndMinimumVersion() throws {
        try snapshot().validate(appVersion: "0.1.0")
        var object = try JSONSerialization.jsonObject(with: remoteManifest()) as! [String: Any]
        var files = object["archives"] as! [[String: Any]]
        for key in ["sha256", "name", "url"] {
            var changed = files
            changed[0][key] = key == "url" ? "https://unapproved.example/model.zip" : "changed"
            var bad = object; bad["archives"] = changed
            let value = try JSONDecoder().decode(ModelManifest.self, from: JSONSerialization.data(withJSONObject: bad))
            XCTAssertThrowsError(try value.validateRemote(appVersion: "0.1.0"))
        }
        files[0]["bytes"] = 1; object["archives"] = files
        XCTAssertThrowsError(try JSONDecoder().decode(ModelManifest.self, from: JSONSerialization.data(withJSONObject: object)).validateRemote(appVersion: "0.1.0"))
        XCTAssertThrowsError(try SupportCompatibility.requireApp("0.2.0", appVersion: "0.1.9"))
        XCTAssertNoThrow(try SupportCompatibility.requireApp("0.2.0", appVersion: "0.10.0"))
        XCTAssertNil(SupportCompatibility.version("0.1.0/path"))
    }
    func testHubMirrorRequiresImmutableRevisionAndPinnedBytes() throws {
        let original = try ModelManifest.bundled().archives[0].url
        XCTAssertTrue(ModelManifest.isApprovedDownloadURL(URL(string: "https://huggingface.co/owner/model/resolve/0123456789abcdef0123456789abcdef01234567/model.zip")!, original: original))
        for url in ["https://huggingface.co/owner/model/resolve/main/model.zip", "http://huggingface.co/owner/model/resolve/0123456789abcdef0123456789abcdef01234567/model.zip", "https://huggingface.co.evil.test/model.zip", "https://user:secret@huggingface.co/owner/model/resolve/0123456789abcdef0123456789abcdef01234567/model.zip"] {
            XCTAssertFalse(ModelManifest.isApprovedDownloadURL(URL(string: url)!, original: original))
        }
    }
    func testCacheRetainsLastValidCatalogAndCorruptCacheUsesBundledDefaults() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = SupportCache(directory: root), value = try snapshot()
        try cache.write(value, appVersion: "0.1.0")
        let original = try Data(contentsOf: cache.url)
        var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        var config = data["configuration"] as! [String: Any]; config["modelManifestPath"] = "https://attacker.example/"; data["configuration"] = config
        let invalid = try JSONDecoder().decode(SupportSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
        XCTAssertThrowsError(try cache.write(invalid, appVersion: "0.1.0"))
        XCTAssertEqual(try Data(contentsOf: cache.url), original)
        XCTAssertNotNil(cache.read(appVersion: "0.1.0"))
        try Data("corrupt".utf8).write(to: cache.url)
        XCTAssertNil(cache.read(appVersion: "0.1.0"))
        XCTAssertNoThrow(try SupportConfiguration.bundled().validate(appVersion: "0.1.0"))
    }
    func testUnapprovedInferenceParametersCannotEnterCache() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SupportConfiguration.bundled())) as! [String: Any]
        var profiles = json["inferenceProfiles"] as! [[String: Any]]
        profiles[0]["diffusionEvaluations"] = 4; json["inferenceProfiles"] = profiles
        let value = try JSONDecoder().decode(SupportConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try value.validate(appVersion: "0.1.0"))
    }
    @MainActor func testSupportMakesNoAutomaticRequestsAndOfflineRefreshPreservesCache() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        try SupportCache(directory: root).write(snapshot(), appVersion: "0.1.0")
        let transport = StubSupportTransport([])
        let service = OnlineSupport(directory: root, transport: transport)
        XCTAssertFalse(service.enabled); XCTAssertNotNil(service.snapshot)
        var count = await transport.count; XCTAssertEqual(count, 0)
        await service.refresh(); count = await transport.count; XCTAssertEqual(count, 0)
        service.enabled = true; await service.refresh()
        XCTAssertNotNil(service.snapshot)
        let relaunched = OnlineSupport(directory: root, transport: transport)
        XCTAssertTrue(relaunched.enabled); XCTAssertNotNil(relaunched.snapshot)
        count = await transport.count; XCTAssertEqual(count, 1, "Relaunch must not contact the server")
    }
    @MainActor func testCatalogRefreshCommitsOnlyAfterBothResponsesValidate() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let config = try JSONEncoder().encode(SupportConfiguration.bundled())
        let transport = StubSupportTransport([(config, 200), (try remoteManifest(), 200)])
        let service = OnlineSupport(directory: root, transport: transport); service.enabled = true
        await service.refresh()
        XCTAssertNotNil(service.snapshot)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/api/v1/config.json", "/api/v1/models/movd-v1.json"])
        XCTAssertTrue(requests.allSatisfy { $0.httpBody == nil })
    }
    func testReportHasNoPrivateFreeformFieldsAndUsesExactServerSchema() throws {
        let report = try DiagnosticReport(summary: summary()), data = try report.encoded()
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE_"))
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let keys = ["schemaVersion","appVersion","appBuild","osVersion","modelVersion","kind","outcome","resumed","elapsedSeconds","peakSampledMemoryBytes","memoryWarnings","thermalState","partitions","lastOperation","errorCategory","errorDomain","errorCode"]
        XCTAssertEqual(Set(object.keys), Set(keys)); XCTAssertTrue(object["lastOperation"] is NSNull)
        XCTAssertEqual(report.thermalState, "serious")
        var injected = summary(); injected.errorDomain = "PRIVATE_DOMAIN"; injected.errorCategory = "PRIVATE_ERROR"; injected.appVersion = "PRIVATE_VERSION"
        XCTAssertFalse(String(decoding: try DiagnosticReport(summary: injected).encoded(), as: UTF8.self).contains("PRIVATE_"))
    }
    @MainActor func testConsentRequiredPerUploadAndFailureNeverQueuesRetry() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = StubSupportTransport([(Data(#"{"status":"stored","retentionDays":30}"#.utf8), 201), (Data(#"{"error":"report-slot-used"}"#.utf8), 429)])
        let service = OnlineSupport(directory: root, transport: transport), report = try DiagnosticReport(summary: summary())
        do { try await service.send(report, consent: true); XCTFail("Disabled support sent a report") } catch { }
        service.enabled = true
        do { try await service.send(report, consent: false); XCTFail("Missing consent sent a report") } catch { }
        var count = await transport.count; XCTAssertEqual(count, 0)
        try await service.send(report, consent: true)
        do { try await service.send(report, consent: true); XCTFail("Quota overflow reported success") } catch SupportError.rateLimited { }
        count = await transport.count; XCTAssertEqual(count, 2)
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "X-LocalFrames-Consent"), "report-v1")
        XCTAssertEqual(requests.first?.httpBody, try report.encoded())
    }
    func testModelActivationRetainsPreviousAndRollbackRestoresIt() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("Installed"), staging = root.appendingPathComponent("Staging")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("original-model".utf8).write(to: installed.appendingPathComponent("weights"))
        try Data("candidate-model".utf8).write(to: staging.appendingPathComponent("weights"))
        try ModelActivation.activate(staging: staging, installed: installed)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("weights"), encoding: .utf8), "candidate-model")
        XCTAssertEqual(try String(contentsOf: ModelActivation.rollbackURL(installed).appendingPathComponent("weights"), encoding: .utf8), "original-model")
        XCTAssertThrowsError(try ModelActivation.activate(staging: staging, installed: installed))
        try ModelActivation.restore(installed: installed)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("weights"), encoding: .utf8), "original-model")
    }
    func testCoreMLErrorDiagnosticsContainCodeAndCategoryWithoutUserInfo() {
        let error = NSError(domain: "com.apple.CoreML", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_PROMPT_PATH"])
        let fields = BenchmarkLog.diagnosticErrorFields(error, phase: "predict")
        XCTAssertEqual(fields, ["errorCategory":"inference", "errorDomain":"CoreML", "errorCode":"1"])
    }
}

private actor StubSupportTransport: SupportTransport {
    var responses: [(Data, Int)]
    var requests: [URLRequest] = []
    var count: Int { requests.count }
    init(_ responses: [(Data, Int)]) { self.responses = responses }
    func request(_ request: URLRequest, maximumBytes: Int) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
        let next = responses.removeFirst()
        guard next.0.count <= maximumBytes else { throw SupportError.tooLarge }
        return next
    }
}
