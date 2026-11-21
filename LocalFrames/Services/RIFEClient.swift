import Foundation

enum RIFEResponseKind: Sendable { case json, events, video }
protocol RIFETransport: Sendable {
    func request(_ request: URLRequest, kind: RIFEResponseKind, maximumBytes: Int) async throws -> Data
}

/// Direct, anonymous, free-only access. No Vercel proxy, account token, cookies, credentials or paid fallback.
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
        guard let url = request.url, RIFEClient.isHelperURL(url),
              request.value(forHTTPHeaderField: "Authorization") == nil, request.value(forHTTPHeaderField: "Cookie") == nil else { throw SmoothingError.invalidResponse }
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
                    if name == "complete" || name == "error" { return event }
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
    private var consumedPreviews: Set<UUID> = []
    init(transport: any RIFETransport = RIFEHTTPTransport()) { self.transport = transport }

    static func isHelperURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == origin.host && url.user == nil && url.password == nil && url.port == nil
            && url.query == nil && url.fragment == nil && url.path.hasPrefix("/gradio_api/")
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
        let boundary = "LocalFrames-" + UUID().uuidString
        var upload = URLRequest(url: Self.origin.appendingPathComponent("gradio_api/upload"))
        upload.httpMethod = "POST"; upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = Self.uploadBody(try Data(contentsOf: prepared.clipURL), boundary: boundary)
        progress("Uploading this clip over Wi-Fi")
        let response = try await transport.request(upload, kind: .json, maximumBytes: 4096)
        guard let paths = try? JSONDecoder().decode([String].self, from: response), paths.count == 1, Self.validFilePath(paths[0]) else { throw SmoothingError.invalidResponse }
        try Task.checkCancellation()
        var submit = URLRequest(url: Self.origin.appendingPathComponent("gradio_api/call/interpolate_video"))
        submit.httpMethod = "POST"; submit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submit.httpBody = try JSONSerialization.data(withJSONObject: ["data": [
            ["video": ["path": paths[0], "orig_name": "clip.mp4", "meta": ["_type": "gradio.FileData"]], "subtitles": NSNull()],
            "2", false, "native", "mp4"]])
        progress("Waiting for the free GPU helper · queue time varies")
        struct Job: Decodable { let event_id: String }
        let jobData = try await transport.request(submit, kind: .json, maximumBytes: 4096)
        guard let job = try? JSONDecoder().decode(Job.self, from: jobData), job.event_id.range(of: #"^[a-f0-9]{32}$"#, options: .regularExpression) != nil else { throw SmoothingError.invalidResponse }
        try Task.checkCancellation()
        let result = try await transport.request(URLRequest(url: Self.origin.appendingPathComponent("gradio_api/call/interpolate_video/" + job.event_id)), kind: .events, maximumBytes: 128 * 1024)
        let download = try Self.completedURL(result)
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
