import AVFoundation
import CoreML
import XCTest
@testable import LocalFrames
@testable import VideoEngine

final class LocalFramesTests: XCTestCase {
    func testNeodragonNativeCLIPPrecisionCandidates() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["LOCALFRAMES_NEODRAGON_CLIP_FIXTURE"],
              let candidatesPath = environment["LOCALFRAMES_NEODRAGON_CLIP_CANDIDATES"] else {
            throw XCTSkip("Opt-in local conversion experiment; no downloads or uploads")
        }
        struct Fixture: Decodable {
            struct Case: Decodable { let shape: [Int]; let embeddingFile: String; let groupFile: String }
            let cases: [Case]
        }
        struct Candidates: Decodable {
            struct Variant: Decodable { let name: String; let packagePath: String; let macPassed: Bool }
            let variants: [Variant]
        }
        let root = URL(fileURLWithPath: fixturePath)
        let candidatesRoot = URL(fileURLWithPath: candidatesPath)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("fixture.json")))
        let candidates = try JSONDecoder().decode(Candidates.self, from: Data(contentsOf: candidatesRoot.appendingPathComponent("report.json")))
        XCTAssertFalse(candidates.variants.isEmpty)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        func read(_ name: String) throws -> [Float32] {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            return data.withUnsafeBytes { bytes in
                stride(from: 0, to: data.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float32.self) }
            }
        }
        var reports: [[String: Any]] = []
        for variant in candidates.variants {
            var report: [String: Any] = ["name": variant.name, "macPassed": variant.macPassed]
            do {
                let compiled = try await MLModel.compileModel(at: URL(fileURLWithPath: variant.packagePath))
                defer { try? FileManager.default.removeItem(at: compiled) }
                let model = try MLModel(contentsOf: compiled, configuration: configuration)
                var cases: [[String: Any]] = []
                for (index, item) in fixture.cases.enumerated() {
                    let input = MLFeatureValue(multiArray: MLMultiArray(MLShapedArray<Float32>(scalars: try read(item.embeddingFile), shape: item.shape)))
                    let output = try await model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["hidden": input]))
                    let array = try XCTUnwrap(output.featureValue(for: "hidden_out")?.multiArrayValue)
                    let values = MLShapedArray<Float32>(converting: array).scalars
                    let expected = try read(item.groupFile)
                    let invalid = values.filter { !$0.isFinite }.count
                    var delta = 0.0, energy = 0.0
                    for (actual, reference) in zip(values, expected) {
                        if actual.isFinite { delta += pow(Double(actual) - Double(reference), 2) }
                        energy += pow(Double(reference), 2)
                    }
                    let relative = sqrt(delta / max(energy, 1e-30))
                    let passed = invalid == 0 && values.count == expected.count && relative <= 0.01
                    print("NEODRAGON_CLIP_CANDIDATE \(variant.name) case \(index): invalid=\(invalid), finiteSubsetRelativeL2=\(relative), passed=\(passed)")
                    cases.append(["index": index, "nonFiniteValues": invalid, "finiteSubsetRelativeL2": relative, "passed": passed])
                }
                report["cases"] = cases
                report["passed"] = variant.macPassed && cases.allSatisfy { $0["passed"] as? Bool == true }
            } catch {
                report["passed"] = false
                report["error"] = String(describing: error)
            }
            reports.append(report)
            let result: [String: Any] = ["scope": "iOS Simulator CPU candidate screening; not iPhone validation", "variants": reports]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: candidatesRoot.appendingPathComponent("native-report.json"), options: .atomic)
        }
        XCTAssertTrue(reports.contains { $0["passed"] as? Bool == true }, "No candidate passed native numerical comparison")
    }

    func testNeodragonNativeCLIPDataTransferAgainstOriginalFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let fixturePath = environment["LOCALFRAMES_NEODRAGON_CLIP_FIXTURE"],
              let runtimePath = environment["LOCALFRAMES_NEODRAGON_ENGINE_FIXTURE"] else {
            throw XCTSkip("Opt-in local model diagnostic; no model download or media upload")
        }
        struct Fixture: Decodable {
            struct Case: Decodable {
                let prompt: String; let inputIDs: [Int32]; let shape: [Int]
                let embeddingFile: String; let groupFile: String
            }
            let weightsRevision: String; let cases: [Case]
        }
        let root = URL(fileURLWithPath: fixturePath)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("fixture.json")))
        XCTAssertEqual(fixture.weightsRevision, NeodragonModel.weightsRevision)
        let directory = URL(fileURLWithPath: runtimePath).appendingPathComponent("Compiled")
        let runner = ModelRunner(directory: directory)
        let tokenizer = try NeodragonCLIPTokenizer(directory: directory.appendingPathComponent("ssd_1b_tokenizer"))
        func read(_ filename: String) throws -> [Float32] {
            let data = try Data(contentsOf: root.appendingPathComponent(filename))
            return data.withUnsafeBytes { bytes in
                stride(from: 0, to: data.count, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float32.self) }
            }
        }
        func compare(_ result: [String: MLFeatureValue], key: String, expected: [Float32], label: String) throws {
            let raw = try XCTUnwrap(result[key]?.multiArrayValue)
            let values = MLShapedArray<Float32>(converting: raw).scalars
            let invalid = values.filter { !$0.isFinite }.count
            var delta = 0.0, denominator = 0.0
            for (actual, reference) in zip(values, expected) {
                if actual.isFinite { delta += pow(Double(actual) - Double(reference), 2) }
                denominator += pow(Double(reference), 2)
            }
            let relative = sqrt(delta / max(denominator, 1e-30))
            print("NEODRAGON_CLIP_NATIVE \(label): shape=\(raw.shape), strides=\(raw.strides), type=\(raw.dataType.rawValue), invalid=\(invalid), relativeL2=\(relative)")
            XCTAssertEqual(values.count, expected.count, label)
            XCTAssertEqual(invalid, 0, label)
            XCTAssertLessThanOrEqual(relative, 0.01, label)
        }
        for (index, item) in fixture.cases.enumerated() {
            XCTAssertEqual(try tokenizer.encode(item.prompt), item.inputIDs)
            let expectedEmbedding = try read(item.embeddingFile)
            let expectedGroup = try read(item.groupFile)
            let ids = MLFeatureValue(multiArray: MLMultiArray(MLShapedArray<Int32>(scalars: item.inputIDs, shape: [1, 77])))
            let embedding = try await runner.predict("ssd_1b_text_encoder_embedding", ["input_ids": ids])
            try compare(embedding, key: "hidden", expected: expectedEmbedding, label: "case \(index) embedding")
            let direct = try await runner.predict("ssd_1b_text_encoder_layers_00_03", ["hidden": try XCTUnwrap(embedding["hidden"])])
            try compare(direct, key: "hidden_out", expected: expectedGroup, label: "case \(index) direct Core ML value")
            let copied = try await runner.predict("ssd_1b_text_encoder_layers_00_03", ["hidden": feature(try tensor(embedding, "hidden"))])
            try compare(copied, key: "hidden_out", expected: expectedGroup, label: "case \(index) shaped-array transfer")
            let reference = try await runner.predict("ssd_1b_text_encoder_layers_00_03", ["hidden": feature(.init(scalars: expectedEmbedding, shape: item.shape))])
            try compare(reference, key: "hidden_out", expected: expectedGroup, label: "case \(index) original reference input")
        }
    }

    @MainActor
    func testBundledOptionalManifestEnablesNineSecondRange() throws {
        let manifest = try NeodragonManifest.bundled()
        XCTAssertEqual(manifest.maximumSeconds, 9)
        XCTAssertEqual(manifest.modelVersion, "neodragon-coreml-9s-v1")
        XCTAssertEqual(manifest.archives.flatMap(\.models).count, 168)
        XCTAssertEqual(manifest.downloadBytes, 7_881_071_452)
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(root: root)
        XCTAssertEqual(Array(model.supportedDurations), Array(2...9))
        XCTAssertFalse(model.installed, "A manifest must not pretend the weights are installed")
    }

    func testOptionalManifestRejectsUntrustedDownloadAndUnsupportedDuration() throws {
        let archive: [String: Any] = [
            "name": "neodragon-01.zip",
            "url": "https://github.com/AgileJurf/OfflineVideoGen/releases/download/neodragon-test/neodragon-01.zip",
            "bytes": 1_000, "expandedBytes": 2_000, "sha256": String(repeating: "a", count: 64),
            "models": (0..<60).map { "model_\($0)" }, "supportFiles": ["neodragon-runtime.json"]
        ]
        let valid: [String: Any] = [
            "schemaVersion": 1, "modelID": NeodragonModel.identifier, "modelVersion": "neodragon-test",
            "sourceRevision": NeodragonModel.sourceRevision, "weightsRevision": NeodragonModel.weightsRevision,
            "maximumSeconds": 9, "minimumAppVersion": "0.1.0", "minimumFreeBytes": 10_000, "archives": [archive]
        ]
        func check(_ value: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: value)
            try JSONDecoder().decode(NeodragonManifest.self, from: data).validate()
        }
        try check(valid)
        var invalid = valid
        invalid["maximumSeconds"] = 10
        XCTAssertThrowsError(try check(invalid))
        invalid = valid
        invalid["weightsRevision"] = "unvalidated-checkpoint"
        XCTAssertThrowsError(try check(invalid))
        for change in [["url": "https://example.com/neodragon-01.zip"],
                       ["sha256": "missing"], ["name": "../neodragon-01.zip"]] {
            var changed = archive
            for (key, value) in change { changed[key] = value }
            invalid = valid; invalid["archives"] = [changed]
            XCTAssertThrowsError(try check(invalid))
        }
    }

    func testOptionalModelJournalKeepsItsOwnRevisionAndPartitionCounts() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("optional.jsonl")
        let log = try BenchmarkLog(url: url, kind: "generation", metadata: ["modelRevision": NeodragonModel.weightsRevision,
            "expectedPartitions": "transformer_block_00,decoder_stage_0", "expectedEvaluations": "85"], sampleInterval: 100)
        let start = log.begin("transformer_block_00", phase: "predict")
        log.end("transformer_block_00", phase: "predict", started: start)
        log.record("diffusion_step_completed", fields: ["completedSteps": "8"])
        try log.finish(status: "cancelled")
        let summary = try BenchmarkSummary.read(url)
        XCTAssertEqual(summary.modelRevision, NeodragonModel.weightsRevision)
        XCTAssertEqual(summary.expectedEvaluations, 85)
        XCTAssertEqual(summary.completedSteps, 8)
        XCTAssertEqual(summary.partitions.map(\.name), ["transformer_block_00"])
    }

    func testNeodragonNativeGenerationFromLocalPackageFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["LOCALFRAMES_NEODRAGON_ENGINE_FIXTURE"] else {
            throw XCTSkip("Opt-in complete local inference; CI does not download model assets or upload media")
        }
        executionTimeAllowance = 28_800
        struct Index: Decodable {
            struct Model: Decodable { let name: String; let packagePath: String; let fingerprint: String }
            let schemaVersion: Int; let maximumSeconds: Int; let models: [Model]
        }
        let fixture = URL(fileURLWithPath: path, isDirectory: true)
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: fixture.appendingPathComponent("package-index.json")))
        XCTAssertEqual(index.schemaVersion, 1)
        let seconds = Int(ProcessInfo.processInfo.environment["LOCALFRAMES_NEODRAGON_ENGINE_SECONDS"] ?? "2") ?? 2
        XCTAssertLessThanOrEqual(seconds, index.maximumSeconds)
        let fm = FileManager.default
        let compiled = fixture.appendingPathComponent("Compiled", isDirectory: true)
        try fm.createDirectory(at: compiled, withIntermediateDirectories: true)
        // Cache only this fixture's compiled models. An incomplete compile has
        // no matching stamp and is recompiled on the next local test invocation.
        for (offset, item) in index.models.enumerated() {
            let destination = compiled.appendingPathComponent(item.name + ".mlmodelc")
            let stamp = compiled.appendingPathComponent(item.name + ".compile-stamp")
            let expected = item.fingerprint + "\n" + ProcessInfo.processInfo.operatingSystemVersionString
            if fm.fileExists(atPath: destination.path), (try? String(contentsOf: stamp, encoding: .utf8)) == expected { continue }
            print("NEODRAGON_COMPILE \(offset + 1)/\(index.models.count) \(item.name)")
            let temporary = try await MLModel.compileModel(at: URL(fileURLWithPath: item.packagePath))
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: temporary, to: destination)
            try expected.write(to: stamp, atomically: true, encoding: .utf8)
        }
        for support in try fm.contentsOfDirectory(at: fixture.appendingPathComponent("support"), includingPropertiesForKeys: nil) {
            let destination = compiled.appendingPathComponent(support.lastPathComponent)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: support, to: destination)
        }
        let installation = try NeodragonEngine.validateInstallation(at: compiled)
        let run = fixture.appendingPathComponent("generation-\(seconds)s-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: run, withIntermediateDirectories: true)
        let output = run.appendingPathComponent("sailboat-seed42.mp4")
        let request = try NeodragonGenerationRequest(prompt: "A small sailboat glides across a calm lake at sunrise.", duration: seconds, seed: 42)
        let geometry = try NeodragonModel.geometry(seconds: seconds)
        let log = try BenchmarkLog(url: run.appendingPathComponent("generation.jsonl"), kind: "generation", metadata: [
            "modelID": NeodragonModel.identifier, "modelRevision": NeodragonModel.weightsRevision,
            "expectedPartitions": installation.modelNames.joined(separator: ","),
            "expectedEvaluations": String(4 + (geometry.latentFrames - 1) * 3),
            "prompt": request.prompt, "seed": "42", "durationSeconds": String(seconds),
            "width": "512", "height": "320", "fps": "24",
            "scope": "Native complete-generation functional check; simulator CPU results are not iPhone performance measurements"])
        print("NEODRAGON_NATIVE_GENERATION_OUTPUT \(run.path)")
        do {
            let metrics = try await NeodragonEngine().generate(request, modelsAt: compiled, output: output, benchmark: log) {
                print("NEODRAGON_PROGRESS \($0.fraction) \($0.message)")
            }
            try JSONEncoder().encode(metrics).write(to: run.appendingPathComponent("metrics.json"), options: .atomic)
            let asset = AVURLAsset(url: output)
            let duration = try await asset.load(.duration)
            XCTAssertEqual(duration.seconds, Double(seconds), accuracy: 1.0 / 24.0)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let size = try await track.load(.naturalSize)
            let fps = try await track.load(.nominalFrameRate)
            XCTAssertEqual(size, CGSize(width: 512, height: 320))
            XCTAssertEqual(fps, 24, accuracy: 0.01)
            let reader = try AVAssetReader(asset: asset)
            let samples = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(samples)
            XCTAssertTrue(reader.startReading())
            var frames = 0
            while let sample = samples.copyNextSampleBuffer() {
                XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
                frames += 1
            }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertEqual(frames, seconds * 24)
            XCTAssertEqual(metrics.modelRevision, NeodragonModel.weightsRevision)
            guard reader.status == .completed, frames == seconds * 24,
                  size == CGSize(width: 512, height: 320), abs(fps - 24) < 0.01,
                  abs(duration.seconds - Double(seconds)) < 1.0 / 24.0 else { throw GenerationError.invalidTensor }
            try log.finish(status: "completed", fields: ["exportedFrames": String(frames), "output": output.lastPathComponent])
            print("NEODRAGON_NATIVE_GENERATION_COMPLETED \(seconds)s \(frames) frames")
        } catch {
            try? log.finish(status: "failed", fields: ["error": String(describing: error)])
            throw error
        }
    }

    func testNeodragonImageActivationBoundIncludesOriginalVAEShape() throws {
        XCTAssertEqual(try NeodragonImageGraph.checkedElementCount([1, 256, 640, 1024]), 167_772_160)
        XCTAssertThrowsError(try NeodragonImageGraph.checkedElementCount([1, 256, 640, 1025]))
        XCTAssertThrowsError(try NeodragonImageGraph.checkedElementCount([16_384, 16_384, 16_384, 16_384, 16_384]))
        XCTAssertThrowsError(try NeodragonImageGraph.checkedElementCount([1, 0, 640, 1024]))
    }

    func testNeodragonImageValidationUsesLogicalStridesWithoutCopyingPadding() throws {
        let pointer = UnsafeMutablePointer<Float32>.allocate(capacity: 8)
        pointer.initialize(repeating: .nan, count: 8)
        for i in [0, 1, 2, 4, 5, 6] { pointer[i] = Float32(i) }
        let array = try MLMultiArray(dataPointer: pointer, shape: [2, 3], dataType: .float32, strides: [4, 1]) { raw in
            raw.assumingMemoryBound(to: Float32.self).deinitialize(count: 8)
            raw.deallocate()
        }
        XCTAssertNoThrow(try NeodragonImageGraph.validate(array, shape: [2, 3]))
        array[[1, 2]] = NSNumber(value: Float32.nan)
        XCTAssertThrowsError(try NeodragonImageGraph.validate(array, shape: [2, 3]))
        XCTAssertThrowsError(try NeodragonImageGraph.validate(array, shape: [3, 2]))
    }

    func testMotionTransferReleasesSourceStorageAndPreservesStridedValues() throws {
        let released = LockedValue(0)
        let copied: MLFeatureValue = try autoreleasepool {
            let pointer = UnsafeMutablePointer<Float32>.allocate(capacity: 8)
            pointer.initialize(repeating: .nan, count: 8)
            for i in [0, 1, 2, 4, 5, 6] { pointer[i] = Float32(i) }
            let source = try MLMultiArray(dataPointer: pointer, shape: [2, 3], dataType: .float32, strides: [4, 1]) { raw in
                raw.assumingMemoryBound(to: Float32.self).deinitialize(count: 8)
                raw.deallocate(); released.modify { $0 += 1 }
            }
            let copy = try independentMotionFeature(["hidden_out": MLFeatureValue(multiArray: source)], "hidden_out", shape: [2, 3])
            XCTAssertNotEqual(copy.multiArrayValue?.dataPointer, source.dataPointer)
            source[[0, 0]] = 99
            return copy
        }
        // Keeping the next input alive must not keep prediction-owned storage.
        XCTAssertEqual(released.read(), 1)
        let array = try XCTUnwrap(copied.multiArrayValue)
        XCTAssertEqual(array.dataType, .float32)
        XCTAssertEqual(MLShapedArray<Float32>(converting: array).scalars, [0, 1, 2, 4, 5, 6])
    }

    func testMotionTransferConvertsHalfPrecisionWithoutChangingRepresentableValues() throws {
        let source = try MLMultiArray(shape: [1, 4], dataType: .float16)
        let values: [Float32] = [-1, 0.125, 1.5, 65504]
        for (i, value) in values.enumerated() { source[i] = NSNumber(value: value) }
        let result = try independentMotionFeature(["context_out": MLFeatureValue(multiArray: source)], "context_out", shape: [1, 4])
        let copied = try XCTUnwrap(result.multiArrayValue)
        XCTAssertEqual(copied.dataType, .float32)
        XCTAssertEqual(MLShapedArray<Float32>(converting: copied).scalars, values)
    }

    func testMotionTransferRejectsMissingInvalidShapeAndNonfiniteOutput() throws {
        let source = try MLMultiArray(shape: [1, 2], dataType: .float32)
        source[0] = 1; source[1] = 2
        let outputs = ["hidden_out": MLFeatureValue(multiArray: source)]
        XCTAssertThrowsError(try independentMotionFeature(outputs, "missing", shape: [1, 2]))
        XCTAssertThrowsError(try independentMotionFeature(outputs, "hidden_out", shape: [2, 1]))
        source[1] = NSNumber(value: Float32.nan)
        XCTAssertThrowsError(try independentMotionFeature(outputs, "hidden_out", shape: [1, 2]))
        source[1] = NSNumber(value: Float32.infinity)
        XCTAssertThrowsError(try independentMotionFeature(outputs, "hidden_out", shape: [1, 2]))
    }

    func testNeodragonImageSchedulerMatchesOriginalLCMSteps() throws {
        let scheduler = NeodragonImageScheduler()
        let sample: [Float32] = [0.5, -0.5, 2, -1], prediction: [Float32] = [0.25, -0.75, 3, 0.1]
        let noise: [[Float32]] = [[0.3366903663, 0.1288094074, 0.2344623655, 0.2303330302],
            [-1.1228563786, -0.1863282919, 2.2082014084, -0.6379970312],
            [0.4616572261, 0.2673508823, 0.5349046588, 0.8093572259], [0, 0, 0, 0]]
        let reference: [[Float32]] = [[1.2004987001, 0.9904574156, -3.2336642742, -3.6098351479],
            [-0.3848013878, 0.3475456834, -0.1468735933, -2.9717681408],
            [0.7114479542, 0.3666472137, -0.5526006222, -1.2311053276],
            [0.4350846410, -0.0884818509, 0.3539274037, -1.2860924006]]
        XCTAssertEqual(scheduler.steps.map(\.timestep), [999, 749, 499, 249])
        for step in 0..<4 {
            let actual = try scheduler.advance(index: step, sample: sample, prediction: prediction, noise: noise[step])
            for (a, b) in zip(actual, reference[step]) { XCTAssertEqual(a, b, accuracy: 1e-6) }
        }
        XCTAssertThrowsError(try scheduler.advance(index: 4, sample: sample, prediction: prediction, noise: noise[0]))
        XCTAssertThrowsError(try scheduler.advance(index: 0, sample: [.nan], prediction: [0], noise: [0]))
    }

    func testNeodragonT5TokenizerMatchesOriginalFullVocabulary() throws {
        guard let root = ProcessInfo.processInfo.environment["LOCALFRAMES_NEODRAGON_TOKENIZER_ROOT"],
              let fixturePath = ProcessInfo.processInfo.environment["LOCALFRAMES_NEODRAGON_T5_TOKENIZER_FIXTURE"] else {
            throw XCTSkip("Opt-in local vocabulary parity; CI does not download model assets")
        }
        struct Fixture: Decodable {
            struct Case: Decodable { let text: String; let ids: [Int32]; let count: Int }
            let cases: [Case]
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: fixturePath)))
        let encoder = NeodragonTextEncoder(runner: ModelRunner(directory: URL(fileURLWithPath: root)))
        for item in fixture.cases {
            let actual = try encoder.t5Tokens(item.text)
            XCTAssertEqual(actual.ids, item.ids, "T5 conditioning differs for \(item.text.debugDescription)")
            XCTAssertEqual(actual.count, item.count)
        }
        XCTAssertThrowsError(try encoder.t5Tokens(Array(repeating: "sailboat", count: 200).joined(separator: " ")))
    }

    func testNeodragonNativeDecoderAgainstLocalRealModelFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["LOCALFRAMES_NEODRAGON_DECODER_FIXTURE"] else {
            throw XCTSkip("Opt-in local model parity test; no model download occurs in CI")
        }
        let fixture = URL(fileURLWithPath: path, isDirectory: true)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("fixture.json"))) as? [String: Any])
        let latentFrames = metadata["latentFrames"] as? Int ?? 7
        let expectedFrames = try XCTUnwrap(metadata["frames"] as? Int)
        XCTAssertEqual(expectedFrames, latentFrames * 8 - 7)
        let modelSource = (metadata["modelsDirectory"] as? String).map { URL(fileURLWithPath: $0) }
            ?? fixture.deletingLastPathComponent().appendingPathComponent("decoder-fp16-v2")
        let compiled = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: compiled) }
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        for name in NeodragonModel.decoderNames {
            let temporary = try await MLModel.compileModel(at: modelSource.appendingPathComponent(name + ".mlpackage"))
            try FileManager.default.moveItem(at: temporary, to: compiled.appendingPathComponent(name + ".mlmodelc"))
        }
        func readFloats(_ name: String, count: Int) throws -> [Float32] {
            let data = try Data(contentsOf: fixture.appendingPathComponent(name))
            guard data.count == count * MemoryLayout<Float32>.size else { throw GenerationError.invalidTensor }
            var result = [Float32](repeating: 0, count: count)
            _ = result.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            return result
        }
        let values = try readFloats("normalized-latents.bin", count: 16 * latentFrames * 40 * 64)
        // the original load-one-partition policy through the default argument.
        let runner = ModelRunner(directory: compiled, retainingSmallModels: Set(NeodragonModel.decoderNames))
        let decoder = NeodragonDecoder(runner: runner)
        var frameCount = 0
        var maximumRelativeError = 0.0
        try await decoder.frames(.init(scalars: values, shape: [1, 16, latentFrames, 40, 64]), progress: { _ in }) { frame in
            XCTAssertEqual(frame.shape, [1, 3, 1, 320, 512])
            let reference = try readFloats("frame-\(frameCount).bin", count: 3 * 320 * 512)
            let actual = frame.scalars
            XCTAssertTrue(actual.allSatisfy(\.isFinite))
            var error = 0.0, energy = 0.0
            for (a, b) in zip(actual, reference) {
                let difference = Double(a) - Double(b)
                error += difference * difference
                energy += Double(b) * Double(b)
            }
            let relativeError = sqrt(error / max(energy, 1e-30))
            maximumRelativeError = max(maximumRelativeError, relativeError)
            XCTAssertLessThanOrEqual(relativeError, 0.01, "Decoded frame \(frameCount) differs from the independent reference")
            frameCount += 1
        }
        XCTAssertEqual(frameCount, expectedFrames)
        print("NEODRAGON_NATIVE_DECODER_PARITY frames=\(frameCount) maxRelativeL2=\(maximumRelativeError)")
    }

    func testNeodragonSchedulerMatchesPinnedReferenceAndGeometry() throws {
        let scheduler = NeodragonScheduler()
        // Generated from the unmodified pinned Qualcomm scheduler, not this port.
        XCTAssertEqual(scheduler.stages.map(\.timestep), [1000, 744, 386])
        XCTAssertEqual(scheduler.stages[1].correctedStartSigma, 0.8002399489209289, accuracy: 1e-12)
        XCTAssertEqual(scheduler.stages[2].correctedStartSigma, 0.5007496155411024, accuracy: 1e-12)
        XCTAssertEqual(try scheduler.step(sample: [0.5, -0.5, 2], predictedFlow: [0.25, -0.75, 3]), [0.25, 0.25, -1])
        XCTAssertThrowsError(try scheduler.step(sample: [1], predictedFlow: []))
        XCTAssertThrowsError(try scheduler.step(sample: [.nan], predictedFlow: [0]))
        XCTAssertEqual(NeodragonModel.frameCount, (NeodragonModel.latentFrames - 1) * 8 + 1)
        let extended = try NeodragonModel.geometry(seconds: 9)
        XCTAssertEqual(extended.latentFrames, 28)
        XCTAssertEqual(extended.nativeFrames, 217)
        XCTAssertEqual(extended.exportFrames, 216)
        XCTAssertThrowsError(try NeodragonModel.geometry(seconds: 10))
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
            let digest = try FileIntegrity.sha256(url)
            let after = try XCTUnwrap(BenchmarkLog.snapshot().footprintBytes)
            XCTAssertEqual(digest, "3b6a07d0d404fab4e23b6d34bc6696a6a312dd92821332385e5af7c01c421351")
            XCTAssertLessThan(Int64(after) - Int64(before), 32 * 1024 * 1024,
                              "Hashing must not retain the entire archive in autoreleased buffers")
        }
    }

    func testInstallationStagesRetainBoundedVerificationSafety() {
        XCTAssertFalse(ModelInstallationStage.downloading.shouldPauseForMemoryWarning)
        XCTAssertFalse(ModelInstallationStage.verifying.shouldPauseForMemoryWarning)
        XCTAssertTrue(ModelInstallationStage.compiling.shouldPauseForMemoryWarning)
        XCTAssertTrue(ModelInstallationStage.extracting.shouldPauseForMemoryWarning)
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

    func testChecksumDetectsChangedFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("integrity.bin")
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try FileIntegrity.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try Data("abd".utf8).write(to: url)
        XCTAssertNotEqual(try FileIntegrity.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
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
