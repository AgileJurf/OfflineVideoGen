import AVFoundation
import CoreML
import XCTest
@testable import LocalFrames
@testable import VideoEngine

final class LocalFramesTests: XCTestCase {
    func testBundledTokenizerEncodesPromptWithoutModelDownload() throws {
        let ids = try MOVDEngine.promptTokenIDs("A small sailboat glides across a calm lake.")
        XCTAssertGreaterThan(ids.count, 1)
        XCTAssertLessThanOrEqual(ids.count, 64)
        XCTAssertEqual(ids.last, 1) // T5 end-of-sequence token.
        XCTAssertTrue(ids.dropLast().allSatisfy { $0 > 0 })
    }

    func testRequestRejectsEmptyPromptAndUnsupportedDurations() throws {
        XCTAssertThrowsError(try GenerationRequest(prompt: " \n ", duration: 2))
        XCTAssertThrowsError(try GenerationRequest(prompt: "waves", duration: 1))
        XCTAssertThrowsError(try GenerationRequest(prompt: "waves", duration: 6))
        for seconds in 2...5 {
            let request = try GenerationRequest(prompt: "  Waves roll onto a beach.  ", duration: seconds, seed: 42)
            XCTAssertEqual(request.prompt, "Waves roll onto a beach.")
            XCTAssertEqual(request.frameCount, seconds * 12)
            XCTAssertEqual(request.seed, 42)
        }
    }

    func testMissingModelsNeverEnableGeneration() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = ModelInstaller(root: root)
        let installed = await installer.isInstalled()
        XCTAssertFalse(installed)
        let engine = MOVDEngine()
        do {
            _ = try await engine.generate(GenerationRequest(prompt: "A flag waves.", duration: 2), modelsAt: root,
                                          output: root.appendingPathComponent("must-not-exist.mp4")) { _ in }
            XCTFail("Missing model must fail before generation")
        } catch GenerationError.modelMissing { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("must-not-exist.mp4").path))
    }

    func testBundledManifestCoversAllRequiredPartitions() throws {
        let manifest = try ModelManifest.bundled()
        let names = manifest.archives.flatMap(\.models)
        XCTAssertTrue(Set(MOVDModel.requiredNames).isSubset(of: Set(names)))
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertTrue(manifest.archives.allSatisfy { $0.bytes > 0 && $0.sha256.count == 64 && $0.url.scheme == "https" })
    }

    func testChecksumDetectsChangedFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("integrity.bin")
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try ModelInstaller.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("abd".utf8).write(to: url)
        XCTAssertNotEqual(try ModelInstaller.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testVideoEncodingLibraryReloadAndDeletion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("fixture.mp4")
        // Synthetic pixels exercise only AVFoundation I/O. This is not an AI generation test.
        let encoder = try VideoEncoder(output: url, width: 32, height: 32, fps: 12)
        let frame = MLShapedArray<Float32>(repeating: 0, shape: [1, 3, 4, 32, 32])
        for _ in 0..<6 { try await encoder.append(frame, limit: 24) }
        try await encoder.finish(expectedFrames: 24)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.02)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let fps = try await tracks[0].load(.nominalFrameRate)
        XCTAssertEqual(fps, 12, accuracy: 0.1)
        let request = try GenerationRequest(prompt: "Library I/O fixture", duration: 2, seed: 7)
        let metrics = GenerationMetrics(elapsedSeconds: 0, peakSampledMemoryBytes: 0, thermalStates: [],
                                        environment: "synthetic-io-test-only", modelRevision: MOVDModel.revision)
        let library = VideoLibrary(root: root.appendingPathComponent("Library"))
        let item = try await library.add(temporaryURL: url, request: request, metrics: metrics)
        let reloaded = try await library.list()
        XCTAssertEqual(reloaded.map(\.id), [item.id])
        XCTAssertEqual(reloaded.first?.prompt, request.prompt)
        try await library.delete(item)
        let remaining = try await library.list()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.videoURL(item.id).path))
    }

    func testCancelledEncoderRemovesPartialOutput() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("cancelled.mp4")
        let encoder = try VideoEncoder(output: url, width: 32, height: 32, fps: 12)
        encoder.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LocalFramesTests-" + UUID().uuidString)
    }
}
