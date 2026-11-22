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
        model.generationModel = .neodragon
        XCTAssertEqual(Array(model.supportedDurations), Array(2...9))
        XCTAssertFalse(model.selectedModelInstalled, "A manifest must not pretend the weights are installed")
        model.generationModel = .movd
        XCTAssertEqual(model.supportedDurations, 2...5)
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

    @MainActor
    func testOptionalModelSettingsPreserveNineSecondsAndProtectMOVDLimit() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(root: root)
        let metrics = GenerationMetrics(elapsedSeconds: 0, peakSampledMemoryBytes: 0, thermalStates: [],
                                        environment: "metadata-test-only", modelRevision: NeodragonModel.weightsRevision)
        let video = VideoRecord(id: UUID(), prompt: "A sailboat moves.", duration: 9, width: 512, height: 320,
                                framesPerSecond: 24, seed: 42, createdAt: Date(), metrics: metrics,
                                modelID: NeodragonModel.identifier)
        let restored = try JSONDecoder().decode(VideoRecord.self, from: JSONEncoder().encode(video))
        XCTAssertEqual(restored.framingName, "Native 16:10")
        XCTAssertTrue(restored.canReuseSettings)
        model.reuseSettings(restored)
        XCTAssertEqual(model.generationModel, .neodragon)
        XCTAssertEqual(model.duration, 9)
        XCTAssertFalse(model.smoothAfterGeneration)
        XCTAssertEqual(AppModel(root: root).generationModel, .neodragon)
        model.generationModel = .movd
        XCTAssertEqual(model.duration, 5)
        XCTAssertThrowsError(try GenerationRequest(prompt: "A sailboat moves.", duration: 9))
        XCTAssertNoThrow(try NeodragonGenerationRequest(prompt: "A sailboat moves.", duration: 9, seed: 42))
    }

    func testRemovingOptionalModelPreservesMOVDAndLibraryFiles() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let optional = root.appendingPathComponent("OptionalModels/Neodragon")
        let paths = [root.appendingPathComponent("Models/Installed/working.bin"), root.appendingPathComponent("Library/video.bin"),
                     optional.appendingPathComponent("Installed/optional.bin")]
        for path in paths {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: path)
        }
        try await NeodragonInstaller(root: optional).remove()
        for path in paths.prefix(2) { XCTAssertEqual(try Data(contentsOf: path), Data([1, 2, 3])) }
        XCTAssertFalse(fm.fileExists(atPath: optional.path))
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
            let samples = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(samples)
            XCTAssertTrue(reader.startReading())
            var frames = 0
            while samples.copyNextSampleBuffer() != nil { frames += 1 }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertEqual(frames, seconds * 24)
            XCTAssertEqual(metrics.modelRevision, NeodragonModel.weightsRevision)
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
        // Only the four tiny optional decoder stages are retained. MOVD keeps
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

    func testNeodragonSchedulerMatchesPinnedReferenceWithoutChangingMOVD() throws {
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
        XCTAssertEqual(GenerationProfile.evaluationCount, 21)
        XCTAssertEqual(try GenerationRequest(prompt: "A sailboat moves.", duration: 2, seed: 42).framesPerSecond, 12)
    }

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
        log.record("failure", partition: "vae_spatial_part3_1", phase: "predict", duration: 3, fields: ["error": "synthetic fixture failure", "errorCategory": "inference", "errorDomain": "CoreML", "errorCode": "1"])
        try log.finish(status: "failed", fields: ["error": "synthetic fixture failure", "errorCategory": "other", "errorDomain": "other", "errorCode": "0"])
        let summary = try BenchmarkSummary.read(url)
        XCTAssertEqual(summary.status, "failed")
        XCTAssertEqual(summary.sessionLabel, "Resumed session")
        XCTAssertEqual(summary.restoredSteps, 21)
        XCTAssertEqual(summary.totalLoadSeconds, 2)
        XCTAssertEqual(summary.totalPredictionSeconds, 3)
        XCTAssertEqual(summary.partitions.first?.failures, 1)
        XCTAssertNotNil(summary.failure)
        XCTAssertEqual(summary.errorCategory, "inference")
        XCTAssertEqual(summary.errorDomain, "CoreML")
        XCTAssertEqual(summary.errorCode, 1)
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
