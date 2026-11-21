import AVFoundation
import CoreML
import XCTest
@testable import LocalFrames
@testable import VideoEngine

final class LocalFramesTests: XCTestCase {
    func testStyledJournalCountsCompletedStepsWithoutBaselineCheckpoints() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("style.jsonl")
        let log = try BenchmarkLog(url: url, kind: "generation", metadata: ["prompt": "A flag waves.",
            "effectiveModelPrompt": "A flag waves. Visual style: cinematic.", "visualStyle": "cinematic"], sampleInterval: 100)
        log.record("diffusion_step_completed", fields: ["completedSteps": "11"])
        try log.finish(status: "cancelled")
        let summary = try BenchmarkSummary.read(url)
        XCTAssertEqual(summary.completedSteps, 11)
        XCTAssertEqual(summary.restoredSteps, 0)
        XCTAssertEqual(summary.status, "cancelled")
        XCTAssertEqual(summary.style, "Cinematic")
        XCTAssertNotEqual(summary.prompt, summary.effectivePrompt)
    }

    func testStyleConditioningPreservesTheSceneAndRejectsOverflowWithoutTruncation() throws {
        let scene = "A red flag waves gently in the wind."
        for style in VisualStyle.allCases {
            let request = try GenerationRequest(prompt: scene, duration: 2, seed: 42, style: style)
            XCTAssertEqual(request.prompt, scene)
            XCTAssertEqual(request.effectivePrompt, style.applying(to: scene))
            XCTAssertLessThanOrEqual(try MOVDEngine.promptTokenCount(request.effectivePrompt), 63)
            let restored = try JSONDecoder().decode(GenerationRequest.self, from: JSONEncoder().encode(request))
            XCTAssertEqual(restored, request)
        }
        let boundary = Array(repeating: "cat", count: 63).joined(separator: " ")
        XCTAssertEqual(try MOVDEngine.promptTokenCount(boundary), 63)
        XCTAssertNoThrow(try GenerationRequest(prompt: boundary, duration: 2, seed: 42))
        XCTAssertThrowsError(try GenerationRequest(prompt: boundary, duration: 2, seed: 42, style: .cinematic)) { error in
            guard case GenerationError.conditioningTooLong(let count) = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertGreaterThan(count, 63)
        }
    }

    func testEarlierBaselineRequestRemainsExactlyCompatible() throws {
        let json = #"{"prompt":"A flag waves.","duration":2,"seed":42,"width":256,"height":256,"framesPerSecond":12}"#
        let old = try JSONDecoder().decode(GenerationRequest.self, from: Data(json.utf8))
        let current = try GenerationRequest(prompt: "A flag waves.", duration: 2, seed: 42)
        XCTAssertEqual(old, current, "Existing checkpoint request equality must survive the style fields")
        XCTAssertEqual(old.effectivePrompt, old.prompt)
        XCTAssertEqual(old.style, .default)
        XCTAssertNil(old.visualStyle)
        XCTAssertNil(old.modelPrompt)
    }

    @MainActor
    func testCreationSettingsPersistLocallyWithoutChangingTheBaseline() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = AppModel(root: root)
        first.visualStyle = .watercolor; first.outputFraming = .portrait
        first.useFixedSeed = true; first.generationSeed = "2026"
        first.recordCreationDiagnostics = true
        let relaunched = AppModel(root: root)
        XCTAssertEqual(relaunched.visualStyle, .watercolor)
        XCTAssertEqual(relaunched.outputFraming, .portrait)
        XCTAssertTrue(relaunched.useFixedSeed)
        XCTAssertEqual(relaunched.generationSeed, "2026")
        XCTAssertTrue(relaunched.recordCreationDiagnostics)
        let baseline = try GenerationRequest(prompt: AppModel.benchmarkPrompts[0], duration: 2, seed: 42)
        XCTAssertEqual(baseline.style, .default)
        XCTAssertEqual(baseline.width, 256)
    }

    func testCropCopiesArePlayableAndPreserveTheOriginalAndMetadata() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = root.appendingPathComponent("original.mp4")
        let encoder = try VideoEncoder(output: fixture, width: 256, height: 256, fps: 12)
        var pixels = [Float32](repeating: -1, count: 3 * 4 * 256 * 256)
        // Three vertical bands distinguish cropping from scaling the full square.
        for t in 0..<4 { for y in 0..<256 { for x in 0..<256 {
            let channel = x < 56 ? 0 : (x < 200 ? 1 : 2)
            pixels[((channel * 4 + t) * 256 + y) * 256 + x] = 1
        } } }
        let tensor = MLShapedArray<Float32>(scalars: pixels, shape: [1, 3, 4, 256, 256])
        for _ in 0..<6 { try await encoder.append(tensor, limit: 24) }
        try await encoder.finish(expectedFrames: 24)
        let library = VideoLibrary(root: root.appendingPathComponent("Library"))
        let request = try GenerationRequest(prompt: "Synthetic crop I/O fixture", duration: 2, seed: 123, style: .anime)
        let metrics = GenerationMetrics(elapsedSeconds: 0, peakSampledMemoryBytes: 0, thermalStates: [], environment: "synthetic-io-test-only", modelRevision: MOVDModel.revision)
        let original = try await library.add(temporaryURL: fixture, request: request, metrics: metrics)
        let originalURL = library.videoURL(original.id)
        let hash = try ModelInstaller.sha256(originalURL)
        for framing in [OutputFraming.portrait, .landscape] {
            let destination = root.appendingPathComponent(framing.rawValue + ".mp4")
            try await VideoCropExporter.export(source: originalURL, destination: destination, framing: framing)
            let asset = AVURLAsset(url: destination)
            let seconds = try await asset.load(.duration).seconds
            XCTAssertEqual(seconds, 2, accuracy: 0.02)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            XCTAssertEqual(size, CGSize(width: framing.width, height: framing.height))
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output); XCTAssertTrue(reader.startReading())
            var frames = 0
            while let sample = output.copyNextSampleBuffer() {
                if frames == 0, let buffer = CMSampleBufferGetImageBuffer(sample) {
                    CVPixelBufferLockBaseAddress(buffer, .readOnly)
                    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                    let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
                    let stride = CVPixelBufferGetBytesPerRow(buffer)
                    let middle = (framing.height / 2) * stride + (framing.width / 2) * 4
                    XCTAssertGreaterThan(Int(base[middle + 1]) - Int(base[middle + 2]), 100, "The center green band must remain centered")
                    let edge = (framing.height / 2) * stride + 8 * 4
                    let dominant = framing == .portrait ? 1 : 2
                    let other = framing == .portrait ? 2 : 1
                    XCTAssertGreaterThan(Int(base[edge + dominant]) - Int(base[edge + other]), 100,
                                         "Check band identity despite lossy H.264 color conversion: portrait removes the red edge; landscape preserves it")
                }
                frames += 1
            }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertEqual(frames, 24)
            let crop = try await library.addCrop(temporaryURL: destination, original: original, framing: framing, elapsedSeconds: 1)
            XCTAssertEqual(crop.parentVideoID, original.id)
            XCTAssertEqual(crop.style, .anime)
            XCTAssertEqual(crop.seed, 123)
            XCTAssertEqual(crop.effectivePrompt, request.effectivePrompt)
            XCTAssertTrue(crop.isCrop)
            XCTAssertTrue(crop.canReuseSettings)
        }
        XCTAssertEqual(try ModelInstaller.sha256(originalURL), hash)
        let cancelledURL = root.appendingPathComponent("cancelled-crop.mp4")
        let cancelled = Task { try await VideoCropExporter.export(source: originalURL, destination: cancelledURL, framing: .portrait) }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("A cancelled crop must not be saved") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledURL.path))
        XCTAssertEqual(try ModelInstaller.sha256(originalURL), hash)
        try await library.delete(original)
        let retained = try await library.list()
        XCTAssertEqual(retained.count, 2, "Deleting a parent must not remove its independently saved copies")
        XCTAssertTrue(retained.allSatisfy { $0.parentVideoID == original.id && $0.style == .anime })
    }

    func testFallbackPixelBuffersProducePlayableVideoWhenAdaptorPoolIsMissing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("fallback.mp4")
        let encoder = try VideoEncoder(output: url, width: 32, height: 32, fps: 12, poolProvider: { _ in nil })
        let elementCount: Int = 3 * 24 * 32 * 32
        let values: [Float32] = (0..<elementCount).map { index -> Float32 in
            Float32(index % 256) / Float32(127.5) - Float32(1)
        }
        try await encoder.append(MLShapedArray(scalars: values, shape: [1, 3, 24, 32, 32]), limit: 24)
        try await encoder.finish(expectedFrames: 24)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.01)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var frames = 0
        while output.copyNextSampleBuffer() != nil { frames += 1 }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(frames, 24, "Decode actual frames instead of relying on MP4 metadata alone")
    }

    func testBenchmarkReaderSeparatesResumeTimeAndPreservesFailures() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("synthetic.jsonl")
        let log = try BenchmarkLog(url: url, kind: "generation", metadata: ["appBuild": "18", "configuration": "synthetic"], sampleInterval: 100)
        log.record("checkpoint_restored", fields: ["completedSteps": "21"])
        log.record("begin", partition: "vae_spatial_part3_1", phase: "load")
        log.record("end", partition: "vae_spatial_part3_1", phase: "load", duration: 2)
        log.record("begin", partition: "vae_spatial_part3_1", phase: "predict")
        log.record("failure", partition: "vae_spatial_part3_1", phase: "predict", duration: 3, fields: ["error": "synthetic fixture failure"])
        try log.finish(status: "failed", fields: ["error": "synthetic fixture failure"])
        let summary = try BenchmarkSummary.read(url)
        XCTAssertEqual(summary.status, "failed")
        XCTAssertEqual(summary.sessionLabel, "Resumed session")
        XCTAssertEqual(summary.restoredSteps, 21)
        XCTAssertEqual(summary.totalLoadSeconds, 2)
        XCTAssertEqual(summary.totalPredictionSeconds, 3)
        XCTAssertEqual(summary.partitions.first?.failures, 1)
        XCTAssertNotNil(summary.failure)
        XCTAssertFalse(summary.hasIncompleteLines)
        XCTAssertGreaterThanOrEqual(log.peakSampledMemoryBytes, 1)
    }

    func testInterruptedJournalDoesNotBecomeSuccess() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("synthetic.jsonl")
        do {
            let log = try BenchmarkLog(url: url, kind: "generation", sampleInterval: 100)
            log.record("begin", partition: "vae_spatial_part4", phase: "predict")
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("{\"partial\":".utf8)); try handle.close()
        let summary = try BenchmarkSummary.read(url)
        XCTAssertEqual(summary.status, "interrupted")
        XCTAssertEqual(summary.lastOperation, "vae_spatial_part4 / predict")
        XCTAssertTrue(summary.hasIncompleteLines)
    }

    func testEarlierVideoMetricsRemainReadableAfterBenchmarkFieldsAreAdded() throws {
        let json = """
        {"elapsedSeconds":12.5,"peakSampledMemoryBytes":1048576,"thermalStates":["nominal"],"environment":"synthetic-fixture","modelRevision":"original","resumedFromStep":21}
        """
        let metrics = try JSONDecoder().decode(GenerationMetrics.self, from: Data(json.utf8))
        XCTAssertEqual(metrics.elapsedSeconds, 12.5)
        XCTAssertEqual(metrics.resumedFromStep, 21)
        XCTAssertNil(metrics.profileID)
        XCTAssertNil(metrics.modelLoadSeconds)
    }

    func testDecoderStatisticsIgnoreStridedPaddingAndPreserveValues() throws {
        let values: [Float32] = [0, .nan, -2, 3, .nan, 4]
        let bytes = values.withUnsafeBytes { Data($0) }
        let array = MLShapedArray<Float32>(data: bytes, shape: [2, 2], strides: [3, 2])
        let statistics = try DecoderTensorStatistics(array)
        XCTAssertEqual(statistics.scalarCount, 4)
        XCTAssertEqual(statistics.nonFiniteCount, 0, "Padding is not model output")
        XCTAssertEqual(statistics.zeroCount, 1)
        XCTAssertEqual(statistics.minimum, -2)
        XCTAssertEqual(statistics.maximum, 4)
        XCTAssertNoThrow(try statistics.requireFinite())
        XCTAssertEqual(array.scalars, [0, -2, 3, 4])
    }

    func testDecoderRejectsNonfiniteValuesBeforeAnotherPrediction() throws {
        let array = MLShapedArray<Float32>(scalars: [.nan, .infinity, -.infinity, 0, 1], shape: [5])
        let statistics = try DecoderTensorStatistics(array)
        XCTAssertEqual(statistics.nonFiniteCount, 3)
        XCTAssertEqual(statistics.zeroCount, 1)
        XCTAssertEqual(statistics.minimum, 0)
        XCTAssertEqual(statistics.maximum, 1)
        XCTAssertThrowsError(try statistics.requireFinite())
        let allInvalid = try DecoderTensorStatistics(MLShapedArray<Float32>(scalars: [.nan], shape: [1]))
        XCTAssertEqual(allInvalid.fields["minimum"], "none")
        XCTAssertEqual(allInvalid.fields["maximum"], "none")
        XCTAssertThrowsError(try allInvalid.requireFinite())
    }

    func testETADoesNotInventUnknownDecoderTime() throws {
        let request = try GenerationRequest(prompt: "A sailboat moves.", duration: 2, seed: 42)
        let estimator = GenerationTimeEstimator(request: request, restoredSteps: nil, historyURL: nil)
        XCTAssertNil(estimator.estimate)
        let plan = GenerationTimeEstimator.operations(request: request, restoredSteps: nil)
        XCTAssertEqual(plan.count, 746)
        // Synthetic timing fixture only: all prompt operations and one complete motion step.
        for operation in plan.prefix(56) { estimator.record(operation.name, seconds: 2) }
        let phase = try XCTUnwrap(estimator.estimate)
        XCTAssertFalse(phase.isFullJob)
        XCTAssertEqual(phase.scope, "Current motion phase")
        XCTAssertEqual(phase.seconds, 9 * 30 * 2, accuracy: 0.001)
        XCTAssertTrue(phase.displayText.contains("Total finish time is still being estimated"))
    }

    func testETALearnsFullJobCostsAndCountsOnlyRemainingStepsOnResume() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try GenerationRequest(prompt: "A flag waves.", duration: 2, seed: 42)
        let url = root.appendingPathComponent("timing.data")
        let first = GenerationTimeEstimator(request: request, restoredSteps: nil, historyURL: url)
        for operation in GenerationTimeEstimator.operations(request: request, restoredSteps: nil) { first.record(operation.name, seconds: 2) }
        first.persist()
        XCTAssertNil(first.estimate)
        let resumed = GenerationTimeEstimator(request: request, restoredSteps: 11, historyURL: url)
        let remaining = GenerationTimeEstimator.operations(request: request, restoredSteps: 11)
        XCTAssertEqual(remaining.count, 390)
        let estimate = try XCTUnwrap(resumed.estimate)
        XCTAssertTrue(estimate.isFullJob)
        XCTAssertEqual(estimate.seconds, 780, accuracy: 0.001)
        resumed.record(remaining[0].name, seconds: 10)
        XCTAssertGreaterThan(try XCTUnwrap(resumed.estimate).seconds, 778, "Recent slower work must raise the estimate for repeated operations")
        resumed.record("unexpected-operation", seconds: 1)
        XCTAssertNil(resumed.estimate, "A schedule mismatch must stop displaying an invalid estimate")
    }

    @MainActor
    func testETAPausesForCoolingInsteadOfCountingDown() {
        let model = AppModel(root: temporaryDirectory())
        model.progress = GenerationProgress(0.4, "Generating motion", estimate: .init(seconds: 120, scope: "Estimated time remaining", isFullJob: true))
        XCTAssertTrue(model.estimatedTimeMessage.contains("about 2 min"))
        model.pauseReason = .cooling
        XCTAssertTrue(model.estimatedTimeMessage.contains("estimate paused"))
        model.pauseReason = nil
        XCTAssertTrue(model.estimatedTimeMessage.contains("about 2 min"))
    }

    func testETARejectsPreviousDecoderPolicyHistoryAndRelearns() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let request = try GenerationRequest(prompt: "A flag waves.", duration: 2, seed: 42)
        let url = root.appendingPathComponent("timing.data")
        // Build 14's cache predates the CPU-only spatial-attention policy.
        let oldSignature = MOVDModel.revision + "fp32-stdit-vae-t5-int8-rflow30-leap20-cfg7-tdtm10-latent20-v1" + ProcessInfo.processInfo.operatingSystemVersionString
        let history: [String: Any] = ["signature": oldSignature,
            "samples": Dictionary(uniqueKeysWithValues: MOVDModel.requiredNames.map { ($0, [2.0]) })]
        try JSONSerialization.data(withJSONObject: history).write(to: url)
        let fresh = GenerationTimeEstimator(request: request, restoredSteps: 21, historyURL: url)
        XCTAssertNil(fresh.estimate, "Old compute-policy timings must not become a new decoder estimate")
        for operation in GenerationTimeEstimator.operations(request: request, restoredSteps: 21) {
            fresh.record(operation.name, seconds: 3)
        }
        fresh.persist()
        let learned = GenerationTimeEstimator(request: request, restoredSteps: 21, historyURL: url)
        let estimate = try XCTUnwrap(learned.estimate)
        XCTAssertTrue(estimate.isFullJob)
        XCTAssertEqual(estimate.seconds, 270, accuracy: 0.001)
    }

    func testThermalPauseWaitsThroughFairAndResumesAtNominal() async throws {
        let index = LockedValue(0)
        let pauses = LockedValue<[GenerationControl.PauseReason?]>([])
        let temperatures: [ProcessInfo.ThermalState] = [.serious, .fair, .nominal]
        let control = GenerationControl(thermalState: { temperatures[min(index.read(), 2)] }, wait: {
            index.modify { $0 += 1 }
        }, onPause: { value in pauses.modify { $0.append(value) } })
        try await control.checkpoint()
        XCTAssertEqual(index.read(), 2, "Fair must not immediately restart a thermally paused workload")
        XCTAssertEqual(pauses.read(), [.cooling, nil])
    }

    func testBackgroundWaitResumesOnlyAfterPermissionOrForeground() async throws {
        let entered = expectation(description: "Waiting for foreground")
        let control = GenerationControl(thermalState: { .nominal }, wait: {
            try await Task.sleep(nanoseconds: 1_000_000)
        }, onPause: { if $0 == .foregroundRequired { entered.fulfill() } })
        control.setForeground(false)
        let resumed = LockedValue(false)
        let worker = Task { try await control.checkpoint(); resumed.modify { $0 = true } }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertFalse(resumed.read())
        control.allowBackgroundExecution(true)
        try await worker.value
        XCTAssertTrue(resumed.read())
        control.allowBackgroundExecution(false)
        control.setForeground(true)
        try await control.checkpoint()
    }

    func testCoolingWaitRemainsCancellableAndJournalRecordsPause() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = try BenchmarkLog(url: root.appendingPathComponent("cooling.jsonl"), kind: "unit-test")
        let entered = expectation(description: "Cooling pause")
        let control = GenerationControl(thermalState: { .critical }, wait: {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }, onPause: { if $0 == .cooling { entered.fulfill() } })
        let worker = Task { try await control.checkpoint(benchmark: log) }
        await fulfillment(of: [entered], timeout: 2)
        worker.cancel()
        do { try await worker.value; XCTFail("Cancellation must leave the cooling wait") }
        catch is CancellationError { }
        try log.finish(status: "cancelled")
        let entries = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(entries.filter { $0["event"] as? String == "pause_begin" }.count, 1)
        XCTAssertEqual(entries.filter { $0["event"] as? String == "pause_end" }.count, 1)
        XCTAssertEqual((entries.first { $0["event"] as? String == "pause_end" }?["fields"] as? [String: String])?["resumed"], "false")
    }

    func testCheckpointPreservesFloatBitsStepAndRequestAcrossReload() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("state.checkpoint")
        let request = try GenerationRequest(prompt: "A sailboat moves.", duration: 2, seed: 42)
        let scalars: [Float32] = [0, -0.0, 1.0 / 3, -17, .leastNonzeroMagnitude]
        let tensor = GenerationCheckpoint.Tensor(MLShapedArray(scalars: scalars, shape: [5]))
        let state = GenerationCheckpoint.State(version: 1, modelRevision: MOVDModel.revision,
            configuration: GenerationCheckpoint.configuration, request: request, completedSteps: 11,
            latent: tensor, hidden: tensor, unconditional: tensor, mask: tensor, tokenCount: 15)
        try GenerationCheckpoint.write(state, to: url)
        let restored = try GenerationCheckpoint.read(at: url)
        XCTAssertEqual(restored.completedSteps, 11)
        XCTAssertEqual(restored.request, request)
        XCTAssertEqual(try restored.latent.array(expectedShape: [5]).scalars.map(\.bitPattern), scalars.map(\.bitPattern))
        XCTAssertThrowsError(try restored.latent.array(expectedShape: [1, 5]))
        XCTAssertEqual(try GenerationCheckpoint.summary(at: url).completedSteps, 11)
        // A changed payload must not silently become different diffusion inputs.
        var envelope = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        var payload = try XCTUnwrap(envelope["payload"] as? Data)
        payload[payload.count / 2] ^= 1
        envelope["payload"] = payload
        try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0).write(to: url)
        XCTAssertThrowsError(try GenerationCheckpoint.read(at: url))
    }

    func testCheckpointRejectsIncompatibleScheduleAndNonfiniteTensors() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tensor = GenerationCheckpoint.Tensor(MLShapedArray<Float32>(scalars: [.nan], shape: [1]))
        XCTAssertThrowsError(try tensor.array(expectedShape: [1]))
        let state = GenerationCheckpoint.State(version: 1, modelRevision: MOVDModel.revision,
            configuration: "different-sampler", request: try GenerationRequest(prompt: "A flag waves.", duration: 2, seed: 42),
            completedSteps: 11, latent: tensor, hidden: tensor, unconditional: tensor, mask: tensor, tokenCount: 5)
        let url = root.appendingPathComponent("state.checkpoint")
        try GenerationCheckpoint.write(state, to: url)
        XCTAssertThrowsError(try GenerationCheckpoint.read(at: url))
    }

    func testBuild14CompletedCheckpointRemainsBitExactAndPlansOnlyDecoding() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try GenerationRequest(prompt: "A sailboat moves.", duration: 2, seed: 42)
        let shape = [1, 4, 20, 32, 32]
        let values = (0..<shape.reduce(1, *)).map { Float32($0 % 127 - 63) / 17 }
        let hidden = GenerationCheckpoint.Tensor(MLShapedArray<Float32>(repeating: 0.25, shape: [1, 1, 300, 4096]))
        let state = GenerationCheckpoint.State(version: 1,
            modelRevision: "cc1839814d0e1b0cb01953831a55a557ff6682bf",
            configuration: "fp32-stdit-vae-t5-int8-rflow30-leap20-cfg7-tdtm10-latent20-v1",
            request: request, completedSteps: 21,
            latent: .init(MLShapedArray(scalars: values, shape: shape)), hidden: hidden, unconditional: hidden,
            mask: .init(MLShapedArray<Float32>(scalars: [1] + Array(repeating: 0, count: 299), shape: [1, 300])), tokenCount: 1)
        let url = root.appendingPathComponent("build14.checkpoint")
        try GenerationCheckpoint.write(state, to: url)
        let restored = try GenerationCheckpoint.read(at: url)
        XCTAssertEqual(restored.request, request)
        XCTAssertEqual(restored.completedSteps, 21)
        XCTAssertEqual(try restored.latent.array(expectedShape: shape).scalars.map(\.bitPattern), values.map(\.bitPattern))
        XCTAssertEqual(try restored.hidden.array(expectedShape: [1, 1, 300, 4096]).shape, hidden.shape)
        XCTAssertEqual(try restored.unconditional.array(expectedShape: [1, 1, 300, 4096]).shape, hidden.shape)
        XCTAssertEqual(try restored.mask.array(expectedShape: [1, 300]).scalars.first, 1)
        let remaining = GenerationTimeEstimator.operations(request: restored.request, restoredSteps: restored.completedSteps)
        XCTAssertEqual(remaining.count, 90)
        XCTAssertEqual(remaining.filter { $0.stage == .temporalDecode }.count, 36)
        XCTAssertEqual(remaining.filter { $0.stage == .spatialDecode }.count, 54)
        XCTAssertTrue(remaining.allSatisfy { $0.name.hasPrefix("vae_") })
    }

    @MainActor
    func testAppRestoresSavedBaselineAfterRelaunchWithoutDeletingCheckpoint() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(root: root)
        let id = UUID()
        try FileManager.default.createDirectory(at: model.resumeDirectory, withIntermediateDirectories: true)
        let request = try GenerationRequest(prompt: "A flag waves.", duration: 2, seed: 42)
        let requestObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
        let job: [String: Any] = ["id": id.uuidString, "request": requestObject, "previousJournal": "first-session.jsonl"]
        try JSONSerialization.data(withJSONObject: job).write(to: model.resumeDirectory.appendingPathComponent("pending.json"))
        let tensor = GenerationCheckpoint.Tensor(MLShapedArray<Float32>(scalars: [1], shape: [1]))
        let state = GenerationCheckpoint.State(version: 1, modelRevision: MOVDModel.revision,
            configuration: GenerationCheckpoint.configuration, request: request, completedSteps: 11,
            latent: tensor, hidden: tensor, unconditional: tensor, mask: tensor, tokenCount: 5)
        let checkpoint = model.resumeDirectory.appendingPathComponent(id.uuidString + ".checkpoint")
        try GenerationCheckpoint.write(state, to: checkpoint)
        await model.load()
        XCTAssertTrue(model.savedBaselineDescription?.contains("11 of 21") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.path))
        model.discardSavedBaseline()
        XCTAssertNil(model.savedBaselineDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path))
    }

    func testLargeChecksumKeepsFoundationReadBuffersBounded() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("64MiB-zero-fixture.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 64 * 1024 * 1024)
        try file.close()
        try autoreleasepool {
            let before = try XCTUnwrap(BenchmarkLog.snapshot().footprintBytes)
            let digest = try ModelInstaller.sha256(url)
            let after = try XCTUnwrap(BenchmarkLog.snapshot().footprintBytes)
            XCTAssertEqual(digest, "3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351")
            XCTAssertLessThan(Int64(after) - Int64(before), 32 * 1024 * 1024,
                              "Hashing must not retain the entire archive in autoreleased buffers")
        }
    }

    @MainActor
    func testMemoryWarningDoesNotCancelBoundedInstallationStages() {
        let model = AppModel(root: temporaryDirectory())
        model.working = true
        model.installing = true
        model.installationStage = .verifying
        model.handleMemoryWarning()
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.notice?.contains("continuing") == true)
        XCTAssertFalse(ModelInstallationStage.downloading.shouldPauseForMemoryWarning)
        XCTAssertTrue(ModelInstallationStage.compiling.shouldPauseForMemoryWarning)
        XCTAssertTrue(ModelInstallationStage.extracting.shouldPauseForMemoryWarning)
        model.working = false
        model.notice = nil
        model.handleMemoryWarning()
        XCTAssertNil(model.notice)
    }

    func testBenchmarkJournalPreservesFailureWithoutSuccess() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("failed.jsonl")
        let log = try BenchmarkLog(url: url, kind: "unit-test")
        XCTAssertThrowsError(try log.measure("missing-partition", phase: "load") {
            try MLModel(contentsOf: root.appendingPathComponent("missing.mlmodelc"))
        })
        try log.finish(status: "failed")
        let events = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(events.compactMap { $0["event"] as? String }.filter { $0 != "sample" }, ["started", "begin", "failure", "finished"])
        XCTAssertEqual((events.last?["fields"] as? [String: String])?["status"], "failed")
        let failure = try XCTUnwrap(events.first { $0["event"] as? String == "failure" })
        XCTAssertEqual(failure["partition"] as? String, "missing-partition")
        XCTAssertGreaterThanOrEqual(failure["durationSeconds"] as? Double ?? -1, 0)
        XCTAssertNotNil((failure["snapshot"] as? [String: Any])?["footprintBytes"])
    }

    func testInterruptedBenchmarkJournalHasNoCompletionEvent() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("interrupted.jsonl")
        var log: BenchmarkLog? = try BenchmarkLog(url: url, kind: "unit-test")
        _ = log?.begin("some-partition", phase: "predict")
        log = nil
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("some-partition"))
        XCTAssertFalse(contents.contains("finished"))
        XCTAssertFalse(contents.contains("succeeded"))
    }

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
        let legacyFields: Set<String> = ["id", "prompt", "duration", "width", "height", "framesPerSecond", "seed", "createdAt", "metrics"]
        let currentJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        let legacyJSON = currentJSON.filter { legacyFields.contains($0.key) }
        let legacy = try JSONDecoder().decode(VideoRecord.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        XCTAssertEqual(legacy.style, .default)
        XCTAssertEqual(legacy.effectivePrompt, request.prompt)
        XCTAssertTrue(legacy.canReuseSettings)
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

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func read() -> Value { lock.withLock { value } }
    func modify(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}
