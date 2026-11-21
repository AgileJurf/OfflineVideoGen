// macOS CLI harness for the unmodified native client/media implementation. Synthetic fixture ONLY.
// Build with LocalFrames/Services/{RIFEClient,VideoSmoothing}.swift. No iOS model is loaded.
import Foundation

struct VideoRecord {
    let duration = 2, width = 256, height = 256, framesPerSecond = 12
    let isCrop = false
    let smoothing: SmoothingProvenance? = nil
    let mediaKind: String? = "generated"
}

@main struct NativeSmoothingProbe {
    static func main() async throws {
        guard CommandLine.arguments == [CommandLine.arguments[0], "--confirm-synthetic-upload"] else {
            print("Use --confirm-synthetic-upload to send only the repository’s fabricated moving-shapes fixture to 1inkusFace/RIFE.")
            return
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = root.appendingPathComponent("docs/benchmarks/rife-synthetic-2026-11-21/source-12fps.mp4")
        let folder = root.appendingPathComponent("build/NativeSmoothingProbe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let preview = try await SmoothingMedia.prepare(VideoRecord(), source: source, temporaryRoot: folder)
        let started = ProcessInfo.processInfo.systemUptime
        var report: [String: Any] = ["syntheticOnly": true, "authenticated": false, "provider": RIFEClient.provider,
                                   "sourceSHA256": preview.sha256, "date": ISO8601DateFormatter().string(from: Date())]
        do {
            let result = try await RIFEClient().smooth(preview, consentID: preview.id, enabled: true, progress: { print($0) })
            report["outcome"] = "completed"
            report["decodedFrames"] = try await SmoothingMedia.inspect(result.url, fps: 24, acceptedCounts: [48])
            report["outputPath"] = result.url.path.replacingOccurrences(of: root.path + "/", with: "")
            report["returnedFrames"] = result.provenance.returnedFrames
            report["terminalHoldFrames"] = result.provenance.terminalHoldFrames
        } catch {
            report["outcome"] = "no-output"
            report["category"] = String(describing: error is SmoothingError ? error : SmoothingError.unavailable)
            report["networkErrorCode"] = (error as? URLError)?.code.rawValue
        }
        report["wallSeconds"] = ProcessInfo.processInfo.systemUptime - started
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("report.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
