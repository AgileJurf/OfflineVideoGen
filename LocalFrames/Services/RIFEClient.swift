import Foundation

enum RIFEResponseKind: Sendable { case json, events, video }
protocol RIFETransport: Sendable {
    func request(_ request: URLRequest, kind: RIFEResponseKind, maximumBytes: Int) async throws -> Data
}

/// Direct free-only access. Optional narrowly scoped OAuth; no cookies, redirects, Vercel media proxy or paid fallback.
final class RIFEHTTPTransport: NSObject, RIFETransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let sessionConfiguration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = RIFEHTTPTransport.configuration()) {
        sessionConfiguration = configuration
        super.init()
    }
    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false; config.allowsExpensiveNetworkAccess = false; config.allowsConstrainedNetworkAccess = false
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCredentialStorage = nil; config.urlCache = nil
        return config
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }

    func request(_ request: URLRequest, kind: RIFEResponseKind, maximumBytes: Int) async throws -> Data {
        guard let url = request.url, RIFEClient.isHelperURL(url), request.value(forHTTPHeaderField: "Cookie") == nil else { throw SmoothingError.invalidResponse }
        if let authorization = request.value(forHTTPHeaderField: "Authorization") {
            guard authorization.hasPrefix("Bearer "), HFAccountClient.validToken(String(authorization.dropFirst(7))),
                  !url.path.hasPrefix("/gradio_api/file="), url.path != "/config" else { throw SmoothingError.invalidResponse }
        }
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw SmoothingError.unavailable }
        if [402, 429].contains(response.statusCode) { throw SmoothingError.quota }
        guard response.statusCode == 200 else { throw SmoothingError.unavailable }
        guard response.expectedContentLength <= maximumBytes else { throw SmoothingError.tooLarge }
        let contentType = response.mimeType?.lowercased() ?? ""
        let accepted = switch kind {
        case .json: contentType == "application/json"
        case .events: contentType == "text/event-stream"
        case .video: contentType == "video/mp4" || contentType == "application/octet-stream"
        }
        guard accepted else { throw SmoothingError.invalidResponse }
        var data = Data(), event = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw SmoothingError.tooLarge }
            data.append(byte)
            if case .events = kind {
                event.append(byte)
                if event.suffix(2) == Data([10, 10]) || event.suffix(4) == Data([13, 10, 13, 10]) {
                    let name = RIFEClient.eventName(event)
                    if name == "complete" || name == "error" || RIFEClient.isTerminalQueueEvent(event) { return event }
                    event.removeAll(keepingCapacity: true)
                }
            }
        }
        return data
    }
}

actor RIFEClient {
    static let origin = URL(string: "https://1inkusface-rife.hf.space")!
    static let spaceURL = URL(string: "https://huggingface.co/spaces/1inkusFace/RIFE")!
    static let provider = "Hugging Face · 1inkusFace/RIFE"
    private let transport: any RIFETransport
    private let credentials: any RIFECredentials
    private var consumedPreviews: Set<UUID> = []
    init(transport: any RIFETransport = RIFEHTTPTransport(), credentials: any RIFECredentials = AnonymousRIFECredentials()) {
        self.transport = transport; self.credentials = credentials
    }

    static func isHelperURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == origin.host, url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil else { return false }
        if url.path == "/gradio_api/queue/data" {
            guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  query.count == 1, query[0].name == "session_hash", let hash = query[0].value else { return false }
            return hash.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil
        }
        return url.query == nil && (url.path == "/config" || url.path == "/gradio_api/upload"
            || url.path == "/gradio_api/queue/join" || url.path.hasPrefix("/gradio_api/file="))
    }
    static func validFilePath(_ path: String) -> Bool {
        path.count <= 512 && path.hasPrefix("/tmp/gradio/") && path.hasSuffix(".mp4")
            && !path.contains("..") && path.range(of: #"[^A-Za-z0-9_./-]"#, options: .regularExpression) == nil
    }
    static func resultURL(_ string: String) throws -> URL {
        guard let url = URL(string: string), isHelperURL(url),
              url.path.hasPrefix("/gradio_api/file="), validFilePath(String(url.path.dropFirst("/gradio_api/file=".count))) else { throw SmoothingError.invalidResponse }
        return url
    }
    static func eventName(_ data: Data) -> String? {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("event:") }.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
    }
    static func completedURL(_ data: Data) throws -> URL {
        // Handle heartbeats before completion, including CRLF. Error bodies are never shown or logged.
        let blocks = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let name = eventName(Data(block.utf8))
            if name == "error" { throw SmoothingError.unavailable }
            if name == "complete" {
                let payload = block.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                struct File: Decodable { let url: String }
                struct Result: Decodable { let video: File }
                guard let results = try? JSONDecoder().decode([Result].self, from: Data(payload.utf8)), results.count == 1 else { throw SmoothingError.invalidResponse }
                return try resultURL(results[0].video.url)
            }
        }
        throw SmoothingError.unavailable
    }
    struct QueueEvent: Decodable {
        let msg: String
        let event_id: String?
        let success: Bool?
        let output: Output?
        struct Output: Decodable { let data: [Result]?; let error: String? }
        struct Result: Decodable { let video: File }
        struct File: Decodable { let url: String?; let path: String? }
    }
    static func queueEvents(_ data: Data) -> [QueueEvent] {
        String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n").compactMap { block in
                let payload = block.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }
                    .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                return try? JSONDecoder().decode(QueueEvent.self, from: Data(payload.utf8))
            }
    }
    static func isTerminalQueueEvent(_ data: Data) -> Bool {
        queueEvents(data).contains { ["process_completed", "close_stream", "queue_full", "unexpected_error"].contains($0.msg) }
    }
    static func completedQueueURL(_ data: Data, eventID: String) throws -> URL {
        for event in queueEvents(data) where event.msg == "process_completed" && event.event_id == eventID {
            guard event.success == true else {
                // Classify only. Never render, persist or upload a remote error body.
                if event.output?.error?.lowercased().contains("quota") == true { throw SmoothingError.quota }
                throw SmoothingError.unavailable
            }
            guard let results = event.output?.data, results.count == 1 else { throw SmoothingError.invalidResponse }
            if let url = results[0].video.url { return try resultURL(url) }
            guard let path = results[0].video.path, validFilePath(path) else { throw SmoothingError.invalidResponse }
            return try resultURL(origin.absoluteString + "/gradio_api/file=" + path)
        }
        throw SmoothingError.unavailable
    }
    static func functionIndex(_ data: Data) throws -> Int {
        struct Config: Decodable {
            let api_prefix: String; let protocolVersion: String; let dependencies: [Dependency]
            enum CodingKeys: String, CodingKey { case api_prefix, dependencies; case protocolVersion = "protocol" }
        }
        struct Dependency: Decodable {
            let id: Int; let api_name: String?; let inputs: [Int]; let outputs: [Int]; let backend_fn: Bool; let queue: Bool?
            enum CodingKeys: String, CodingKey { case id, api_name, inputs, outputs, backend_fn, queue }
            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                id = try values.decode(Int.self, forKey: .id)
                api_name = try? values.decode(String.self, forKey: .api_name) // false hides non-API dependencies.
                inputs = try values.decode([Int].self, forKey: .inputs); outputs = try values.decode([Int].self, forKey: .outputs)
                backend_fn = try values.decode(Bool.self, forKey: .backend_fn); queue = try values.decodeIfPresent(Bool.self, forKey: .queue)
            }
        }
        guard let config = try? JSONDecoder().decode(Config.self, from: data), config.api_prefix == "/gradio_api", config.protocolVersion == "sse_v3" else { throw SmoothingError.invalidResponse }
        let matches = config.dependencies.filter { $0.api_name == "interpolate_video" }
        guard matches.count == 1, let function = matches.first, function.id >= 0, function.id < 10000,
              function.inputs.count == 5, function.outputs.count == 1, function.backend_fn, function.queue == true else { throw SmoothingError.invalidResponse }
        return function.id
    }
    static func uploadBody(_ clip: Data, boundary: String) -> Data {
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"clip.mp4\"\r\nContent-Type: video/mp4\r\n\r\n".utf8)
        body.append(clip); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); return body
    }

    func smooth(_ prepared: PreparedSmoothing, consentID: UUID?, enabled: Bool,
                progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> SmoothingResult {
        guard enabled else { throw SmoothingError.disabled }
        guard consentID == prepared.id, !consumedPreviews.contains(prepared.id) else { throw SmoothingError.consentRequired }
        consumedPreviews.insert(prepared.id) // Also consumed on failures: another upload requires another review.
        try Task.checkCancellation()
        let hash = try SmoothingMedia.fingerprint(prepared.clipURL)
        guard hash.hash == prepared.sha256, hash.bytes == prepared.bytes else { throw SmoothingError.changedClip }
        guard SmoothingMedia.supports(prepared.original) else { throw SmoothingError.unsupported }
        let started = ProcessInfo.processInfo.systemUptime
        progress("Checking free helper access and quota")
        let token = try await credentials.authorizedToken()
        let config = try await transport.request(URLRequest(url: Self.origin.appendingPathComponent("config")), kind: .json, maximumBytes: 512 * 1024)
        let function = try Self.functionIndex(config)
        try Task.checkCancellation()
        let boundary = "LocalFrames-" + UUID().uuidString
        var upload = URLRequest(url: Self.origin.appendingPathComponent("gradio_api/upload"))
        upload.httpMethod = "POST"; upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = Self.uploadBody(try Data(contentsOf: prepared.clipURL), boundary: boundary)
        if let token { upload.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        progress("Uploading this clip over Wi-Fi")
        let response = try await transport.request(upload, kind: .json, maximumBytes: 4096)
        guard let paths = try? JSONDecoder().decode([String].self, from: response), paths.count == 1, Self.validFilePath(paths[0]) else { throw SmoothingError.invalidResponse }
        try Task.checkCancellation()
        let sessionHash = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var submit = URLRequest(url: Self.origin.appendingPathComponent("gradio_api/queue/join"))
        submit.httpMethod = "POST"; submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { submit.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        submit.httpBody = try JSONSerialization.data(withJSONObject: ["data": [
            ["video": ["path": paths[0], "orig_name": "clip.mp4", "meta": ["_type": "gradio.FileData"]], "subtitles": NSNull()],
            "2", false, "native", "mp4"], "fn_index": function, "session_hash": sessionHash])
        progress("Waiting for the free GPU helper · queue time varies")
        struct Job: Decodable { let event_id: String }
        let jobData = try await transport.request(submit, kind: .json, maximumBytes: 4096)
        guard let job = try? JSONDecoder().decode(Job.self, from: jobData), job.event_id.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil else { throw SmoothingError.invalidResponse }
        try Task.checkCancellation()
        var eventsURL = URLComponents(url: Self.origin.appendingPathComponent("gradio_api/queue/data"), resolvingAgainstBaseURL: false)!
        eventsURL.queryItems = [URLQueryItem(name: "session_hash", value: sessionHash)]
        var eventsRequest = URLRequest(url: eventsURL.url!)
        if let token { eventsRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let result = try await transport.request(eventsRequest, kind: .events, maximumBytes: 128 * 1024)
        let download = try Self.completedQueueURL(result, eventID: job.event_id)
        try Task.checkCancellation()
        progress("Downloading and checking the 24 FPS result")
        let video = try await transport.request(URLRequest(url: download), kind: .video, maximumBytes: SmoothingMedia.maximumBytes)
        try Task.checkCancellation()
        let raw = prepared.directory.appendingPathComponent("helper-result.mp4"), output = prepared.directory.appendingPathComponent("24fps.mp4")
        try video.write(to: raw, options: .atomic)
        defer { try? FileManager.default.removeItem(at: raw) }
        let normalized = try await SmoothingMedia.normalize(raw, destination: output)
        return SmoothingResult(url: output, provenance: SmoothingProvenance(provider: Self.provider,
            method: "RIFE 2x · native resolution · service-managed weights", sourceSHA256: prepared.sha256,
            sourceFrames: 24, returnedFrames: normalized.returned, terminalHoldFrames: normalized.held,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - started))
    }
}
