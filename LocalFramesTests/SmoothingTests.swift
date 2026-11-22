import AVFoundation
import XCTest
@testable import LocalFrames
@testable import VideoEngine

final class SmoothingTests: XCTestCase {
    @MainActor func testUnifiedJobRestoresReviewAndRequiresNewConsentBeforeSaving24FPSCopy() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeRIFETransport(try responses())
        let account = HFAccountModel(client: HFAccountClient(store: EmptyWorkflowCredentialStore()))
        var app = AppModel(root: root, smoothingClient: RIFEClient(transport: transport), helperAccount: account)
        await app.load(); app.support.enabled = true; app.smoothAfterGeneration = true
        let source = root.appendingPathComponent("source.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: source)
        let original = try await app.library.add(temporaryURL: source, request: GenerationRequest(prompt: "Synthetic workflow fixture", duration: 2, seed: 1), metrics: record().metrics)
        let originalHash = try SmoothingMedia.fingerprint(app.library.videoURL(original.id)).hash
        // This fixture represents the saved output boundary, not a claimed device diffusion run.
        try app.offerSmoothingForGeneratedVideo(original)
        XCTAssertEqual(app.workflowReview?.id, original.id)
        var count = await transport.count; XCTAssertEqual(count, 0)
        app = AppModel(root: root, smoothingClient: RIFEClient(transport: transport), helperAccount: account)
        await app.load()
        XCTAssertTrue(app.smoothAfterGeneration)
        XCTAssertEqual(app.pendingSmoothingVideo?.id, original.id)
        XCTAssertNil(app.workflowReview); XCTAssertNil(app.smoothingPreview)
        app.workflowReview = original
        app.prepareSmoothing(original)
        while app.working { try await Task.sleep(for: .milliseconds(10)) }
        let firstPreview = try XCTUnwrap(app.smoothingPreview)
        app.startSmoothing(previewID: firstPreview.id, consent: false)
        count = await transport.count; XCTAssertEqual(count, 0)
        app.closeSmoothingReview(); app.prepareSmoothing(original)
        while app.working { try await Task.sleep(for: .milliseconds(10)) }
        app.startSmoothing(previewID: firstPreview.id, consent: true)
        count = await transport.count; XCTAssertEqual(count, 0, "Reopening a review invalidates earlier approval")
        let approved = try XCTUnwrap(app.smoothingPreview)
        app.startSmoothing(previewID: approved.id, consent: true)
        while app.working { try await Task.sleep(for: .milliseconds(10)) }
        let copy = try XCTUnwrap(app.smoothingResult, app.smoothingMessage ?? "Missing result")
        let frames = try await SmoothingMedia.inspect(app.library.videoURL(copy.id), fps: 24, acceptedCounts: [48])
        XCTAssertEqual(frames, 48); XCTAssertEqual(copy.parentVideoID, original.id)
        XCTAssertNil(app.pendingSmoothingVideo)
        XCTAssertEqual(try SmoothingMedia.fingerprint(app.library.videoURL(original.id)).hash, originalHash)
        app.reuseSettings(copy)
        XCTAssertNil(app.workflowReview, "Reusing a finished job must reveal Create, not leave its review sheet open")
        XCTAssertTrue(app.smoothAfterGeneration)
        let restored = AppModel(root: root, helperAccount: account); await restored.load()
        XCTAssertNil(restored.pendingSmoothingVideo); XCTAssertEqual(restored.videos.count, 2)
    }

    @MainActor func testUnifiedJobBlocksUnsupportedSettingsAndKeepingOriginalNeverUploads() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeRIFETransport([])
        let app = AppModel(root: root, smoothingClient: RIFEClient(transport: transport),
                           helperAccount: HFAccountModel(client: HFAccountClient(store: EmptyWorkflowCredentialStore())))
        await app.load(); app.smoothAfterGeneration = true
        XCTAssertNotNil(app.smoothingSelectionIssue)
        app.support.enabled = true; app.duration = 5; XCTAssertNotNil(app.smoothingSelectionIssue)
        app.duration = 2; app.outputFraming = .portrait; XCTAssertNotNil(app.smoothingSelectionIssue)
        app.outputFraming = .square; XCTAssertNil(app.smoothingSelectionIssue)
        let source = root.appendingPathComponent("source.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: source)
        let original = try await app.library.add(temporaryURL: source, request: GenerationRequest(prompt: "fixture", duration: 2, seed: 1), metrics: record().metrics)
        try app.offerSmoothingForGeneratedVideo(original)
        app.support.enabled = false; app.keepOriginalWithoutSmoothing()
        XCTAssertNil(app.pendingSmoothingVideo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.library.videoURL(original.id).path))
        let count = await transport.count; XCTAssertEqual(count, 0)
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SmoothingTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "mp4"))
    }
    private func record() -> VideoRecord {
        VideoRecord(id: UUID(), prompt: "PRIVATE_PROMPT", duration: 2, width: 256, height: 256, framesPerSecond: 12,
                    seed: 123456, createdAt: .distantPast,
                    metrics: GenerationMetrics(elapsedSeconds: 123, peakSampledMemoryBytes: 1024, thermalStates: ["nominal"], environment: "synthetic-test", modelRevision: MOVDModel.revision))
    }
    private func prepare(_ root: URL) async throws -> PreparedSmoothing {
        try await SmoothingMedia.prepare(record(), source: fixture("source-12fps"), temporaryRoot: root)
    }
    private func responses() throws -> [Data] {
        [Data(#"{"api_prefix":"/gradio_api","protocol":"sse_v3","dependencies":[{"id":7,"api_name":"interpolate_video","inputs":[1,2,3,4,5],"outputs":[6],"backend_fn":true,"queue":true},{"id":8,"api_name":false,"inputs":[],"outputs":[],"backend_fn":true,"queue":true}]}"#.utf8), Data(#"["/tmp/gradio/abc/clip.mp4"]"#.utf8), Data(#"{"event_id":"0123456789abcdef0123456789abcdef"}"#.utf8),
         Data(#"data: {"msg":"process_completed","event_id":"0123456789abcdef0123456789abcdef","success":true,"output":{"data":[{"video":{"url":"https://1inkusface-rife.hf.space/gradio_api/file=/tmp/gradio/abc/final_interp_123.mp4"},"subtitles":null}]}}"#.utf8),
         try Data(contentsOf: fixture("rife-24fps-raw"))]
    }

    func testPerClipConsentDisabledAndSingleUseEvenAfterFailure() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await prepare(root), transport = FakeRIFETransport([]), client = RIFEClient(transport: transport)
        do { _ = try await client.smooth(preview, consentID: preview.id, enabled: false); XCTFail() } catch SmoothingError.disabled { }
        do { _ = try await client.smooth(preview, consentID: nil, enabled: true); XCTFail() } catch SmoothingError.consentRequired { }
        do { _ = try await client.smooth(preview, consentID: UUID(), enabled: true); XCTFail() } catch SmoothingError.consentRequired { }
        var count = await transport.count; XCTAssertEqual(count, 0)
        do { _ = try await client.smooth(preview, consentID: preview.id, enabled: true); XCTFail() } catch SmoothingError.quota { }
        do { _ = try await client.smooth(preview, consentID: preview.id, enabled: true); XCTFail() } catch SmoothingError.consentRequired { }
        count = await transport.count; XCTAssertEqual(count, 1, "A failed request never retries or reuses consent")
    }

    func testPreviewIsFrozenAndTamperStopsUpload() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("original.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: source)
        let preview = try await SmoothingMedia.prepare(record(), source: source, temporaryRoot: root)
        let transport = FakeRIFETransport([]), client = RIFEClient(transport: transport)
        try Data("changed-original".utf8).write(to: source)
        XCTAssertEqual(try SmoothingMedia.fingerprint(preview.clipURL).hash, preview.sha256, "Preview remains bound to the copied clip")
        try Data("tampered-preview".utf8).write(to: preview.clipURL)
        do { _ = try await client.smooth(preview, consentID: preview.id, enabled: true); XCTFail() } catch SmoothingError.changedClip { }
        let count = await transport.count; XCTAssertEqual(count, 0)
    }

    func testFullProtocolUsesOnlySelectedClipAndSavesIndependent24FPSCopy() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = VideoLibrary(root: root.appendingPathComponent("Library"))
        let file = root.appendingPathComponent("source.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: file)
        let original = try await library.add(temporaryURL: file, request: GenerationRequest(prompt: "PRIVATE_PROMPT", duration: 2, seed: 123456), metrics: record().metrics)
        let originalHash = try SmoothingMedia.fingerprint(library.videoURL(original.id)).hash
        let preview = try await SmoothingMedia.prepare(original, source: library.videoURL(original.id), temporaryRoot: root)
        let transport = FakeRIFETransport(try responses()), client = RIFEClient(transport: transport)
        let result = try await client.smooth(preview, consentID: preview.id, enabled: true)
        XCTAssertEqual(result.provenance.returnedFrames, 47); XCTAssertEqual(result.provenance.terminalHoldFrames, 1)
        XCTAssertEqual(result.provenance.sourceSHA256, originalHash)
        let copy = try await library.addSmoothed(result, original: original)
        let frames = try await SmoothingMedia.inspect(library.videoURL(copy.id), fps: 24, acceptedCounts: [48])
        XCTAssertEqual(frames, 48); XCTAssertNotEqual(copy.id, original.id); XCTAssertEqual(copy.parentVideoID, original.id)
        XCTAssertEqual(copy.prompt, original.prompt); XCTAssertEqual(copy.seed, original.seed)
        XCTAssertEqual(copy.metrics.elapsedSeconds, 123, "MOVD generation time must not be replaced with smoothing time")
        XCTAssertEqual(copy.framesPerSecond, 24); XCTAssertFalse(SmoothingMedia.supports(copy))
        XCTAssertEqual(try SmoothingMedia.fingerprint(library.videoURL(original.id)).hash, originalHash)
        var saved = try await library.list(); XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first { $0.id == copy.id }?.smoothing, result.provenance)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requests.map { $0.httpMethod ?? "GET" }, ["GET", "POST", "POST", "GET", "GET"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil })
        let upload = String(decoding: requests[1].httpBody!, as: UTF8.self)
        XCTAssertTrue(upload.contains("filename=\"clip.mp4\"")); XCTAssertFalse(upload.contains(original.id.uuidString))
        XCTAssertTrue(requests[1].httpBody!.range(of: try Data(contentsOf: fixture("source-12fps"))) != nil)
        let submit = String(decoding: requests[2].httpBody!, as: UTF8.self)
        XCTAssertFalse(submit.contains("PRIVATE_PROMPT")); XCTAssertFalse(submit.contains("123456"))
        let object = try JSONSerialization.jsonObject(with: requests[2].httpBody!) as! [String: Any]
        let settings = object["data"] as! [Any]
        XCTAssertEqual(settings[1] as? String, "2"); XCTAssertEqual(settings[2] as? Bool, false)
        XCTAssertEqual(settings[3] as? String, "native"); XCTAssertEqual(settings[4] as? String, "mp4")
        XCTAssertEqual(object["fn_index"] as? Int, 7, "Resolve the named function instead of hard-coding its index")
        XCTAssertEqual(URLComponents(url: requests[3].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
                       object["session_hash"] as? String)
        try await library.delete(copy); saved = try await library.list(); XCTAssertEqual(saved.map(\.id), [original.id])
        XCTAssertEqual(try SmoothingMedia.fingerprint(library.videoURL(original.id)).hash, originalHash)
    }

    func testConnectedAccountAuthenticatesOnlyUploadAndJobAndStopsBeforeUploadOnQuotaFailure() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await prepare(root), token = "hf_oauth_SYNTHETIC_TEST_CREDENTIAL"
        let transport = FakeRIFETransport(try responses())
        _ = try await RIFEClient(transport: transport, credentials: FakeRIFECredentials(token: token))
            .smooth(preview, consentID: preview.id, enabled: true)
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       [nil, "Bearer " + token, "Bearer " + token, "Bearer " + token, nil])
        let blocked = FakeRIFETransport([]), again = try await prepare(root)
        do {
            _ = try await RIFEClient(transport: blocked, credentials: FakeRIFECredentials(token: nil))
                .smooth(again, consentID: again.id, enabled: true)
            XCTFail()
        } catch HFAccountError.quota { }
        let count = await blocked.count; XCTAssertEqual(count, 0, "Free quota must be checked before any media request")
    }

    func testQueueErrorsAreClassifiedWithoutExposingRemoteBodyAndSessionURLsAreBounded() throws {
        let id = "0123456789abcdef0123456789abcdef"
        let event = Data((#"data: {"msg":"process_completed","event_id":""# + id + #"","success":false,"output":{"error":"PRIVATE_REMOTE_TEXT: You have exceeded your ZeroGPU quota (90s requested vs. 61s left)"}}"# + "\n\n").utf8)
        XCTAssertTrue(RIFEClient.isTerminalQueueEvent(event))
        do { _ = try RIFEClient.completedQueueURL(event, eventID: id); XCTFail() }
        catch { XCTAssertEqual(String(describing: error), "quota"); XCTAssertFalse(error.localizedDescription.contains("PRIVATE_REMOTE_TEXT")) }
        XCTAssertThrowsError(try RIFEClient.completedQueueURL(try responses()[3], eventID: String(repeating: "a", count: 32)))
        XCTAssertTrue(RIFEClient.isHelperURL(URL(string: "https://1inkusface-rife.hf.space/gradio_api/queue/data?session_hash=" + id)!))
        for suffix in ["", "?session_hash=bad", "?session_hash=" + id + "&token=secret", "?session_hash=" + id + "&session_hash=" + id] {
            XCTAssertFalse(RIFEClient.isHelperURL(URL(string: "https://1inkusface-rife.hf.space/gradio_api/queue/data" + suffix)!))
        }
        let changed = Data(#"{"api_prefix":"/gradio_api","protocol":"sse_v3","dependencies":[{"id":7,"api_name":"interpolate_video","inputs":[1,2,3],"outputs":[6],"backend_fn":true,"queue":true}]}"#.utf8)
        XCTAssertThrowsError(try RIFEClient.functionIndex(changed))
    }

    /// Explicit opt-in integration gate. Skipped by local regression and Cloud CI; never uploads a personal clip.
    @MainActor func testLiveHelperSavesSynthetic24FPSCopyInAppLibrary() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOCALFRAMES_LIVE_SYNTHETIC_SMOOTHING"] == "1",
                          "Live synthetic GPU upload requires an explicit local test invocation")
        let account = HFAccountClient()
        let name = try await account.connectedName()
        XCTAssertNotNil(name, "Connect an approved free helper account in this Simulator first")
        guard name != nil else { return }
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(root: root, smoothingClient: RIFEClient(credentials: account))
        await app.load(); app.support.enabled = true
        let source = root.appendingPathComponent("source.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: source)
        let original = try await app.library.add(temporaryURL: source, request: GenerationRequest(prompt: "Synthetic moving-shapes connection test", duration: 2, seed: 1), metrics: record().metrics)
        let hash = try SmoothingMedia.fingerprint(app.library.videoURL(original.id)).hash
        XCTAssertEqual(hash, "828ede0ee022eb194f80c4039ef90d96e715d5c23f4717047508cfa0fc5dd78b")
        let deadline = Date().addingTimeInterval(600)
        app.prepareSmoothing(original)
        while app.working && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let preview = try XCTUnwrap(app.smoothingPreview, app.smoothingMessage ?? "Preview missing")
        app.startSmoothing(previewID: preview.id, consent: true)
        while app.working && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        if app.working { app.cancel(); XCTFail("Live helper deadline exceeded"); return }
        let result = try XCTUnwrap(app.smoothingResult, app.smoothingMessage ?? "No saved result")
        let frames = try await SmoothingMedia.inspect(app.library.videoURL(result.id), fps: 24, acceptedCounts: [48])
        XCTAssertEqual(frames, 48); XCTAssertEqual(result.parentVideoID, original.id)
        XCTAssertEqual(try SmoothingMedia.fingerprint(app.library.videoURL(original.id)).hash, hash)
        let saved = try await app.library.list(); XCTAssertEqual(saved.count, 2)
        let movie = XCTAttachment(data: try Data(contentsOf: app.library.videoURL(result.id)), uniformTypeIdentifier: "public.mpeg-4")
        movie.name = "Live native helper synthetic 24 FPS result"; movie.lifetime = .keepAlways; add(movie)
        let report: [String: Any] = ["execution":"iOS Simulator app-hosted integration test", "syntheticOnly":true,
            "sourceSHA256":hash,"decodedFrames":frames,"fps":24,"duration":2,"width":256,"height":256,
            "originalPreserved":true,"savedLibraryItems":saved.count,"elapsedSeconds":result.smoothing!.elapsedSeconds,
            "returnedFrames":result.smoothing!.returnedFrames,"terminalHoldFrames":result.smoothing!.terminalHoldFrames]
        let json = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        json.name = "Live native helper validation"; json.lifetime = .keepAlways; add(json)
    }

    func testMediaRejectsWrongFrameRateAndNormalizesAlready48WithoutAnotherHold() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        do { _ = try await SmoothingMedia.inspect(fixture("source-12fps"), fps: 24, acceptedCounts: [47, 48]); XCTFail() } catch SmoothingError.invalidResponse { }
        let result = try await SmoothingMedia.normalize(fixture("rife-24fps-duration-corrected"), destination: root.appendingPathComponent("normalized.mp4"))
        XCTAssertEqual(result.returned, 48); XCTAssertEqual(result.held, 0)
        let invalid = root.appendingPathComponent("invalid.mp4"); try Data("not a movie".utf8).write(to: invalid)
        do { _ = try await SmoothingMedia.normalize(invalid, destination: root.appendingPathComponent("bad.mp4")); XCTFail() } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bad.mp4").path))
    }

    func testUntrustedResultURLsAndBrokenEventsAreRejected() throws {
        for url in ["http://1inkusface-rife.hf.space/gradio_api/file=/tmp/gradio/a/v.mp4",
                    "https://evil.example/gradio_api/file=/tmp/gradio/a/v.mp4",
                    "https://user:pass@1inkusface-rife.hf.space/gradio_api/file=/tmp/gradio/a/v.mp4",
                    "https://1inkusface-rife.hf.space:443/gradio_api/file=/tmp/gradio/a/v.mp4",
                    "https://1inkusface-rife.hf.space/gradio_api/file=/tmp/gradio/a/v.mp4?download=1",
                    "https://1inkusface-rife.hf.space/gradio_api/file=/etc/passwd",
                    "https://1inkusface-rife.hf.space/gradio_api/file=/tmp/gradio/../private.mp4"] {
            XCTAssertThrowsError(try RIFEClient.resultURL(url), url)
        }
        for event in ["event: error\ndata: null\n\n", "event: complete\ndata: []\n\n", "event: heartbeat\ndata: null\n\n"] {
            XCTAssertThrowsError(try RIFEClient.completedURL(Data(event.utf8)))
        }
        XCTAssertNoThrow(try RIFEClient.completedQueueURL(responses()[3], eventID: "0123456789abcdef0123456789abcdef"))
        let config = RIFEHTTPTransport.configuration()
        XCTAssertFalse(config.allowsCellularAccess); XCTAssertFalse(config.allowsExpensiveNetworkAccess)
        XCTAssertFalse(config.httpShouldSetCookies); XCTAssertNil(config.httpCookieStorage)
        XCTAssertNil(config.urlCredentialStorage); XCTAssertNil(config.urlCache)
        XCTAssertEqual(config.timeoutIntervalForResource, 180)
    }

    func testCancellationCannotSubmitASecondRequestOrSaveResult() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await prepare(root), transport = FakeRIFETransport(try responses(), delay: true)
        let client = RIFEClient(transport: transport)
        let task = Task { try await client.smooth(preview, consentID: preview.id, enabled: true) }
        while await transport.count == 0 { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError { }
        let count = await transport.count; XCTAssertEqual(count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.appendingPathComponent("24fps.mp4").path))
    }

    func testHTTPRejectsQuotaRedirectWrongTypeAndOversizeAndStopsAtCompleteEvent() async throws {
        let config = RIFEHTTPTransport.configuration(); config.protocolClasses = [FixtureRIFEURLProtocol.self]
        let transport = RIFEHTTPTransport(configuration: config)
        let request = URLRequest(url: RIFEClient.origin.appendingPathComponent("gradio_api/upload"))
        for (status, type, data, expected) in [
            (429, "application/json", Data(), SmoothingError.quota),
            (302, "application/json", Data(), SmoothingError.unavailable),
            (200, "text/html", Data("private error".utf8), SmoothingError.invalidResponse),
            (200, "application/json", Data(repeating: 1, count: 9), SmoothingError.tooLarge)
        ] {
            FixtureRIFEURLProtocol.set(status: status, type: type, data: data)
            do { _ = try await transport.request(request, kind: .json, maximumBytes: 8); XCTFail() }
            catch { XCTAssertEqual(String(describing: error), String(describing: expected)) }
        }
        let event = Data("event: heartbeat\r\ndata: null\r\n\r\nevent: complete\r\ndata: []\r\n\r\n".utf8)
        FixtureRIFEURLProtocol.set(status: 200, type: "text/event-stream", data: event, keepOpen: true)
        let result = try await transport.request(request, kind: .events, maximumBytes: 4096)
        XCTAssertEqual(RIFEClient.eventName(result), "complete", "Completion must stop a still-open event stream")
        var authorized = request; authorized.setValue("fake-credential", forHTTPHeaderField: "Authorization")
        do { _ = try await transport.request(authorized, kind: .json, maximumBytes: 4096); XCTFail() } catch SmoothingError.invalidResponse { }
        let redirected = expectation(description: "Redirect refused")
        let session = URLSession(configuration: .ephemeral), task = session.dataTask(with: request)
        transport.urlSession(session, task: task,
                             willPerformHTTPRedirection: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                             newRequest: URLRequest(url: URL(string: "https://example.com/")!)) { next in
            XCTAssertNil(next); redirected.fulfill()
        }
        await fulfillment(of: [redirected], timeout: 1)
        session.invalidateAndCancel()
    }

    @MainActor func testAppTogglingSupportAndPreparingNeverUploadsAndTurningOffClearsConsent() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeRIFETransport([]), app = AppModel(root: root, smoothingClient: RIFEClient(transport: transport))
        await app.load()
        let source = root.appendingPathComponent("fixture.mp4")
        try FileManager.default.copyItem(at: fixture("source-12fps"), to: source)
        let original = try await app.library.add(temporaryURL: source, request: GenerationRequest(prompt: "fixture", duration: 2, seed: 1), metrics: record().metrics)
        app.support.enabled = true; app.prepareSmoothing(original)
        while app.working { try await Task.sleep(for: .milliseconds(10)) }
        let preview = try XCTUnwrap(app.smoothingPreview)
        app.startSmoothing(previewID: preview.id, consent: false)
        var count = await transport.count; XCTAssertEqual(count, 0)
        app.support.enabled = false
        XCTAssertNil(app.smoothingPreview); XCTAssertFalse(FileManager.default.fileExists(atPath: preview.directory.path))
        app.support.enabled = true; app.startSmoothing(previewID: preview.id, consent: true)
        count = await transport.count; XCTAssertEqual(count, 0, "Old consent must not survive toggling or a new preview")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.library.videoURL(original.id).path))
    }
}

private struct EmptyWorkflowCredentialStore: HFCredentialStore {
    func read() throws -> HFCredential? { nil }
    func write(_ value: HFCredential) throws { }
    func remove() throws { }
}

private final class FixtureRIFEURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var response: (Int, String, Data, Bool) = (200, "application/json", Data(), false)
    static func set(status: Int, type: String, data: Data, keepOpen: Bool = false) {
        lock.lock(); defer { lock.unlock() }; response = (status, type, data, keepOpen)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let (status, type, data, keepOpen) = Self.response; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for byte in data { client?.urlProtocol(self, didLoad: Data([byte])) }
        if !keepOpen { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() { }
}

private actor FakeRIFETransport: RIFETransport {
    var responses: [Data]
    var requests: [URLRequest] = []
    let delay: Bool
    var count: Int { requests.count }
    init(_ responses: [Data], delay: Bool = false) { self.responses = responses; self.delay = delay }
    func request(_ request: URLRequest, kind: RIFEResponseKind, maximumBytes: Int) async throws -> Data {
        requests.append(request)
        if delay { try await Task.sleep(for: .seconds(30)) }
        guard !responses.isEmpty else { throw SmoothingError.quota }
        let data = responses.removeFirst()
        guard data.count <= maximumBytes else { throw SmoothingError.tooLarge }
        return data
    }
}

private struct FakeRIFECredentials: RIFECredentials {
    let token: String?
    func authorizedToken() async throws -> String? {
        guard let token else { throw HFAccountError.quota }
        return token
    }
}
