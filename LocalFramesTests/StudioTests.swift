import XCTest
import VideoEngine
@testable import LocalFrames

final class StudioTests: XCTestCase {
    private var roots: [URL] = []
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StudioTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root); return root
    }
    override func tearDownWithError() throws { for root in roots { try? FileManager.default.removeItem(at: root) } }
    @discardableResult private func write(_ root: URL, _ path: String, _ data: Data = Data(repeating: 42, count: 64)) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url); return url
    }

    func testMigrationRemovesOnlyInventoryAndIsIdempotent() async throws {
        let root = try temporaryRoot()
        let removed = ["Models/Installed/stdit3_ST_0.mlmodelc/weights.bin", "Models/Extracting/archive-folder/stdit3_ST_1.mlpackage/Data/weights.bin", "Models/T5.zip", "Models/STDiT-TDTM.zip.resume", "OnlineSupport/preferences.json", "Benchmarks/timing-cache.data"]
        let preserved = ["OptionalModels/Neodragon/Installed/t5_block_0.mlmodelc/weights.bin", "Library/clip.mp4", "Library/clip.json", "Documents/Videos/clip.mp4", "preferences.json", "visual-styles-v2.json", "Models/Installed/unknown.mlmodelc/weights.bin", "Temporary/Neodragon-active/frame.bin", "Benchmarks/generation-real.jsonl"]
        for path in removed + preserved { try write(root, path) }
        let migration = LegacyMigration(root: root)
        let first = try await migration.run(removeCredential: false)
        XCTAssertTrue(first.completed); XCTAssertEqual(first.removedBytes, Int64(64 * removed.count))
        for path in removed { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path), path) }
        for path in preserved { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), Data(repeating: 42, count: 64), path) }
        let second = try await migration.run(removeCredential: false)
        XCTAssertEqual(second.entries, first.entries); XCTAssertEqual(second.removedBytes, first.removedBytes)
    }

    func testMigrationRecoversDeletionJournalWithoutDoubleCounting() async throws {
        for sourceStillExists in [true, false] {
            let root = try temporaryRoot()
            let path = "Models/Installed/installation.json"
            if sourceStillExists { try write(root, path, JSONEncoder().encode(LegacyMigration.retiredRevision)) }
            var report = LegacyMigration.Report()
            report.pending = .init(path: path, logicalBytes: 42, allocatedBytes: 4096)
            try write(root, "Migrations/retirement-v1.json", JSONEncoder().encode(report))
            let result = try await LegacyMigration(root: root).run(removeCredential: false)
            XCTAssertTrue(result.completed); XCTAssertEqual(result.removedBytes, 42); XCTAssertNil(result.pending)
            XCTAssertEqual(result.entries.count, 1)
        }
    }

    func testMigrationDoesNotTrustUnknownMarkerOrPendingLibraryPath() async throws {
        let root = try temporaryRoot()
        let marker = try write(root, "Models/Installed/installation.json", JSONEncoder().encode("other-model"))
        let clip = try write(root, "Library/clip.mp4")
        var report = LegacyMigration.Report()
        report.pending = .init(path: "Library/clip.mp4", logicalBytes: 64, allocatedBytes: 4096)
        let journal = try write(root, "Migrations/retirement-v1.json", JSONEncoder().encode(report))
        do { _ = try await LegacyMigration(root: root).run(removeCredential: false); XCTFail("Unrecognized deletion journal must fail closed") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
        try FileManager.default.removeItem(at: journal)
        _ = try await LegacyMigration(root: root).run(removeCredential: false)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(contentsOf: marker)), "other-model")
    }

    func testMigrationRefusesSymlinksAndPreservesUnrelatedTemporaryWork() async throws {
        let root = try temporaryRoot(), outside = try temporaryRoot()
        let file = try write(outside, "keep.bin")
        let parent = root.appendingPathComponent("Models/Installed")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: parent.appendingPathComponent("stdit3_ST_0.mlmodelc"), withDestinationURL: outside)
        try write(root, "Temporary/Smoothing-" + UUID().uuidString + "/scratch.bin")
        let keep = try write(root, "Temporary/Smoothing-user-video.mp4")
        let result = try await LegacyMigration(root: root).run(removeCredential: false)
        XCTAssertTrue(result.skipped.contains("Models/Installed/stdit3_ST_0.mlmodelc"))
        XCTAssertEqual(result.removedBytes, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    func testExportsNeverOverwriteUserEditsAndRespectMovedCopies() async throws {
        let root = try temporaryRoot(), source = try write(root, "Private/clip.mp4")
        let exports = LocalExports(root: root.appendingPathComponent("Documents"), historyURL: root.appendingPathComponent("Private/history.json"))
        let item = LocalExports.Source(url: source, folder: .videos, filename: "clip.mp4")
        let first = try await exports.publish([item]); let initial = try XCTUnwrap(first.first)
        try Data("User edited copy".utf8).write(to: initial)
        let explicit = try await exports.publish([item], explicit: true)
        XCTAssertEqual(explicit.first?.lastPathComponent, "clip (2).mp4")
        XCTAssertEqual(try String(contentsOf: initial, encoding: .utf8), "User edited copy")
        try FileManager.default.removeItem(at: XCTUnwrap(explicit.first))
        let automatic = try await exports.publish([item]); XCTAssertTrue(automatic.isEmpty)
        let restored = try await exports.publish([item], explicit: true); XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(restored.first)), try Data(contentsOf: source))
    }

    func testExportsRejectPathTraversalAndSymlinkFolders() async throws {
        let root = try temporaryRoot(), outside = try temporaryRoot(), source = try write(root, "private.bin")
        let documents = root.appendingPathComponent("Documents")
        let exports = LocalExports(root: documents, historyURL: root.appendingPathComponent("history.json"))
        do { _ = try await exports.publish([.init(url: source, folder: .videos, filename: "../escape.mp4")]); XCTFail("Invalid filename") } catch { }
        try FileManager.default.removeItem(at: documents.appendingPathComponent("Videos"))
        try FileManager.default.createSymbolicLink(at: documents.appendingPathComponent("Videos"), withDestinationURL: outside)
        do { _ = try await exports.publish([.init(url: source, folder: .videos, filename: "clip.mp4")]); XCTFail("Symlink destination") } catch { }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testStylesPreserveOriginalPromptAndRejectOverlongCustomFields() throws {
        XCTAssertEqual(StyleCatalog.all.count, 58)
        XCTAssertEqual(Set(StyleCatalog.all.map(\.id)).count, StyleCatalog.all.count)
        let prompt = "A small sailboat glides across a calm lake at sunrise."
        XCTAssertEqual(StyleCatalog.definition(.default).applying(to: prompt), prompt)
        for style in StyleCatalog.all { try style.validate(); XCTAssertTrue(style.applying(to: prompt).hasPrefix(prompt)) }
        let original = String(repeating: "subject motion ", count: 60)
        XCTAssertTrue(StyleCatalog.definition(.anime).applying(to: original).contains(original.trimmingCharacters(in: .whitespaces)))
        var invalid = StyleConditioning(id: "custom-test", name: "Custom", isCustom: true)
        invalid.aesthetic = String(repeating: "x", count: 501)
        XCTAssertThrowsError(try invalid.validate()); XCTAssertEqual(invalid.aesthetic.count, 501)
    }

    @MainActor func testCustomStylesFavoritesRecentAndMetadataSnapshotsPersist() throws {
        let root = try temporaryRoot(), url = root.appendingPathComponent("styles.json")
        let store = StyleStore(url: url)
        var style = StyleConditioning(id: "custom-one", name: "Moonlit ink", aesthetic: "Ink illustration", palette: "silver and charcoal", lighting: "moonlight", camera: "wide", motion: "gentle", isCustom: true)
        try store.upsert(style); store.select(style); store.toggleFavorite(style); store.recordUse()
        let savedSnapshot = try JSONEncoder().encode(style)
        style.name = "Renamed ink"; try store.upsert(style)
        let reopened = StyleStore(url: url)
        XCTAssertEqual(reopened.selected.name, "Renamed ink"); XCTAssertTrue(reopened.isFavorite(style))
        XCTAssertEqual(reopened.recent.first?.id, style.id)
        reopened.remove(style)
        XCTAssertEqual(reopened.selected.id, "default"); XCTAssertTrue(reopened.custom.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(StyleConditioning.self, from: savedSnapshot).name, "Moonlit ink")
        XCTAssertThrowsError(try reopened.upsert(StyleCatalog.definition(.anime)))
    }

    func testJobLogIsBoundedDeduplicatedAndSafeForConcurrentProducers() {
        let buffer = JobActivityBuffer(limit: 200)
        DispatchQueue.concurrentPerform(iterations: 1000) { i in buffer.append(elapsed: Double(i), message: "Partition \(i)") }
        let events = buffer.snapshot()
        XCTAssertEqual(events.count, 200); XCTAssertEqual(Set(events.map(\.id)).count, 200)
        XCTAssertEqual(events.map(\.id), events.map(\.id).sorted())
        buffer.append(elapsed: -1, message: "Finished"); buffer.append(elapsed: 10, message: "Finished")
        XCTAssertEqual(buffer.snapshot().last?.elapsed, 0)
        XCTAssertEqual(buffer.snapshot().filter { $0.message == "Finished" }.count, 1)
    }

    @MainActor func testJobLogFinishesOnceAndNewJobClearsPreviousActivity() {
        let log = JobActivityLog(); log.start(); log.append("Loading actual partition"); log.finish("Cancelled")
        let finished = log.entries; log.append("Ignored late event"); log.finish("Finished")
        XCTAssertFalse(log.recording); XCTAssertEqual(log.entries, finished)
        log.start(); log.flush(); XCTAssertFalse(log.entries.contains { $0.message == "Cancelled" }); log.finish("Stopped")
    }

    private func attentionMetadata() -> [String: Any] {
        ["schemaVersion": 1, "variantID": NeodragonAttentionVariant.identifier,
         "baseModelID": NeodragonModel.identifier, "sourceRevision": NeodragonModel.sourceRevision,
         "weightsRevision": NeodragonModel.weightsRevision, "attentionHeadGroupSize": 8,
         "maximumSeconds": 9, "modelNames": NeodragonAttentionVariant.modelNames]
    }

    func testAttentionVariantRejectsWrongWeightsPartialSetsAndSymlinkComponents() throws {
        let root = try temporaryRoot(), metadata = attentionMetadata()
        func decode(_ value: [String: Any]) throws -> NeodragonAttentionVariant {
            try JSONDecoder().decode(NeodragonAttentionVariant.self, from: JSONSerialization.data(withJSONObject: value))
        }
        try decode(metadata).validate()
        for (key, value) in [("weightsRevision", "other-checkpoint" as Any), ("attentionHeadGroupSize", 12 as Any),
                             ("modelNames", Array(NeodragonAttentionVariant.modelNames.dropLast()) as Any),
                             ("maximumSeconds", 5 as Any)] {
            var invalid = metadata; invalid[key] = value
            XCTAssertThrowsError(try decode(invalid).validate())
        }
        try write(root, NeodragonAttentionVariant.metadataFilename, JSONSerialization.data(withJSONObject: metadata))
        for name in NeodragonAttentionVariant.modelNames { try write(root, name + ".mlmodelc/fixture.bin") }
        _ = try NeodragonAttentionVariant.validateInstallation(at: root)
        let part = root.appendingPathComponent(NeodragonAttentionVariant.modelNames[0] + ".mlmodelc")
        try FileManager.default.removeItem(at: part)
        XCTAssertThrowsError(try NeodragonAttentionVariant.validateInstallation(at: root))
        let outside = try temporaryRoot(); try write(outside, "fixture.bin")
        try FileManager.default.createSymbolicLink(at: part, withDestinationURL: outside)
        XCTAssertThrowsError(try NeodragonAttentionVariant.validateInstallation(at: root))
    }

    func testAttentionManifestCannotReplaceSharedComponentsOrBaseMetadata() throws {
        var archive: [String: Any] = ["name": "neodragon-01.zip", "bytes": 1000, "expandedBytes": 2000,
            "url": "https://github.com/AgileJurf/OfflineVideoGen/releases/download/neodragon-attention-head8-v1/neodragon-01.zip",
            "sha256": String(repeating: "a", count: 64), "models": NeodragonAttentionVariant.modelNames,
            "supportFiles": [NeodragonAttentionVariant.metadataFilename, "THIRD-PARTY-NOTICES.txt"]]
        var manifest: [String: Any] = ["schemaVersion": 1, "modelID": NeodragonModel.identifier,
            "modelVersion": NeodragonAttentionVariant.identifier, "weightsRevision": NeodragonModel.weightsRevision,
            "sourceRevision": NeodragonModel.sourceRevision, "maximumSeconds": 9,
            "minimumAppVersion": "0.1.0", "minimumFreeBytes": 1000,
            "attentionVariant": attentionMetadata(), "archives": [archive]]
        func validate(_ value: [String: Any]) throws {
            try JSONDecoder().decode(NeodragonManifest.self, from: JSONSerialization.data(withJSONObject: value)).validate()
        }
        try validate(manifest)
        archive["models"] = NeodragonAttentionVariant.modelNames + ["image_encoder"]
        manifest["archives"] = [archive]; XCTAssertThrowsError(try validate(manifest))
        archive["models"] = NeodragonAttentionVariant.modelNames
        archive["supportFiles"] = [NeodragonAttentionVariant.metadataFilename, "THIRD-PARTY-NOTICES.txt", "neodragon-runtime.json"]
        manifest["archives"] = [archive]; XCTAssertThrowsError(try validate(manifest))
    }

    func testRemovingAttentionUpdatePreservesBaseModelAndVideos() async throws {
        let root = try temporaryRoot()
        let original = try write(root, "OptionalModels/Neodragon/Installed/transformer_block_00.mlmodelc/weights.bin")
        let video = try write(root, "Library/clip.mp4")
        let variantRoot = root.appendingPathComponent("OptionalModels/Neodragon/Variants/Head8-v1")
        try write(variantRoot, "Installed/transformer_block_00.mlmodelc/weights.bin")
        try write(variantRoot, "neodragon-01.zip.resume")
        let installer = NeodragonInstaller(root: variantRoot)
        try await installer.remove(); try await installer.remove()
        XCTAssertEqual(try Data(contentsOf: original), Data(repeating: 42, count: 64))
        XCTAssertEqual(try Data(contentsOf: video), Data(repeating: 42, count: 64))
        XCTAssertFalse(FileManager.default.fileExists(atPath: variantRoot.path))
    }

    @MainActor func testReferenceDetailConditioningIsOptionalPersistentAndPreservesScene() throws {
        let root = try temporaryRoot(), model = AppModel(root: root)
        let scene = "A small sailboat glides across a calm lake at sunrise."
        model.prompt = scene
        XCTAssertEqual(model.effectivePrompt, scene); XCTAssertFalse(model.useAttentionTrial)
        model.useUpstreamDetailPrompt = true
        XCTAssertEqual(model.prompt, scene)
        XCTAssertEqual(model.effectivePrompt, scene + NeodragonPromptConditioning.upstreamDetailSuffix)
        XCTAssertTrue(AppModel(root: root).useUpstreamDetailPrompt)
        model.useUpstreamDetailPrompt = false
        XCTAssertEqual(model.effectivePrompt, scene)
        XCTAssertEqual(NeodragonPromptConditioning.upstreamDetail("  "), "")
        XCTAssertEqual(NeodragonPromptConditioning.upstreamDetail(NeodragonPromptConditioning.upstreamDetail(scene)), scene + NeodragonPromptConditioning.upstreamDetailSuffix)
        let request = try NeodragonGenerationRequest(prompt: scene, duration: 5, seed: 42,
            modelPrompt: NeodragonPromptConditioning.upstreamDetail(scene))
        XCTAssertEqual(request.prompt, scene); XCTAssertEqual(request.effectivePrompt, scene + NeodragonPromptConditioning.upstreamDetailSuffix)
    }

    @MainActor func testOldVideoMetadataAndDetailSettingsReuseRemainCompatible() throws {
        let scene = "A sailboat on a lake."
        var metadata: [String: Any] = ["id": UUID().uuidString, "prompt": scene, "duration": 2,
            "width": 512, "height": 320, "framesPerSecond": 24, "seed": 42, "createdAt": 0,
            "modelID": NeodragonModel.identifier,
            "metrics": ["elapsedSeconds": 1, "peakSampledMemoryBytes": 1, "thermalStates": ["nominal"],
                "environment": "test-fixture", "modelRevision": NeodragonModel.weightsRevision]]
        func read() throws -> VideoRecord { try JSONDecoder().decode(VideoRecord.self, from: JSONSerialization.data(withJSONObject: metadata)) }
        let old = try read()
        XCTAssertNil(old.upstreamDetailPrompt); XCTAssertEqual(old.effectivePrompt, scene)
        metadata["upstreamDetailPrompt"] = true
        metadata["effectiveModelPrompt"] = NeodragonPromptConditioning.upstreamDetail(scene)
        let new = try read(), model = AppModel(root: try temporaryRoot())
        model.reuseSettings(new)
        XCTAssertTrue(model.useUpstreamDetailPrompt); XCTAssertEqual(model.prompt, scene)
        XCTAssertEqual(model.effectivePrompt, new.effectivePrompt)
        model.useUpstreamDetailPrompt = false
        XCTAssertEqual(model.effectivePrompt, scene)
        model.reuseSettings(old)
        XCTAssertFalse(model.useUpstreamDetailPrompt); XCTAssertEqual(model.prompt, scene)

        // Earlier builds used different style templates. Comparing only the
        // detail option must not silently replace those saved instructions.
        metadata["upstreamDetailPrompt"] = false
        metadata["visualStyle"] = "anime"
        let earlierModelPrompt = scene + ", earlier hand-drawn anime conditioning"
        metadata["effectiveModelPrompt"] = earlierModelPrompt
        model.reuseSettings(try read())
        XCTAssertEqual(model.effectivePrompt, earlierModelPrompt)
        model.useUpstreamDetailPrompt = true
        XCTAssertEqual(model.effectivePrompt, NeodragonPromptConditioning.upstreamDetail(earlierModelPrompt))
        model.useUpstreamDetailPrompt = false
        XCTAssertEqual(model.effectivePrompt, earlierModelPrompt)

        var custom = StyleConditioning(id: "custom-reuse", name: "Saved style", aesthetic: "silver ink", isCustom: true)
        metadata["styleConditioning"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(custom))
        metadata["effectiveModelPrompt"] = "Exact saved custom conditioning"
        model.reuseSettings(try read())
        XCTAssertEqual(model.effectivePrompt, "Exact saved custom conditioning")
        custom.aesthetic = "charcoal illustration"
        try model.styles.upsert(custom)
        XCTAssertEqual(model.effectivePrompt, custom.applying(to: scene), "Editing the same style ID must invalidate saved conditioning")
    }
}
