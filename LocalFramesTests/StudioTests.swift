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
}
