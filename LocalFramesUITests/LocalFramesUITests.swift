import XCTest

final class LocalFramesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Separate sandbox fixtures: no production model, media or inference mock.
        app.launchEnvironment["LOCALFRAMES_UI_TEST_ID"] = UUID().uuidString
        app.launch(); return app
    }
    @MainActor private func reveal(_ item: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        // iOS 26+ may report scroll content under a floating control as hittable.
        // Reveal the entire target above the Generate control and native tab bar.
        func visibleBounds() -> (top: CGFloat, bottom: CGFloat) {
            let navigation = app.navigationBars.firstMatch
            let tabs = app.tabBars.firstMatch
            let generate = app.buttons["generateButton"]
            let top = navigation.exists ? navigation.frame.maxY + 8 : app.frame.minY + 60
            var bottom = tabs.exists ? tabs.frame.minY - 12 : app.frame.maxY - 24
            if generate.exists { bottom = min(bottom, generate.frame.minY - 12) }
            return (top, bottom)
        }
        for _ in 0..<8 {
            // Native Form rows are lazy on newer iOS releases. Querying frame
            // before a row exists fails XCTest instead of returning an empty rect.
            let bounds = visibleBounds(), present = item.exists
            let frame = present ? item.frame : .zero
            if present && item.isHittable && frame.minY >= bounds.top && frame.maxY <= bounds.bottom { break }
            if present && frame.maxY > bounds.bottom { app.swipeUp() }
            else if present && frame.minY < bounds.top { app.swipeDown() }
            else if upward { app.swipeUp() } else { app.swipeDown() }
        }
        guard item.waitForExistence(timeout: 5) else { XCTFail("Control was not revealed: \(item)"); return }
        XCTAssertTrue(item.isHittable)
        let bounds = visibleBounds()
        XCTAssertGreaterThanOrEqual(item.frame.minY, bounds.top)
        XCTAssertLessThanOrEqual(item.frame.maxY, bounds.bottom)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor func testFourTabsAndNoUnsupportedGeneration() throws {
        let app = launch()
        XCTAssertTrue(app.textFields["promptInput"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["generateButton"].isEnabled)
        capture(app, "Studio Create — no model installed")
        for title in ["Library", "Models", "Settings", "Create"] {
            let tab = app.tabBars.buttons[title]; XCTAssertTrue(tab.exists); tab.tap(); XCTAssertTrue(tab.isSelected)
        }
        XCTAssertFalse(app.buttons["Generate Extension"].exists)
        XCTAssertFalse(app.buttons["uploadSmoothingClip"].exists)
        XCTAssertFalse(app.tabBars.buttons["Setup"].exists)
        app.tabBars.buttons["Library"].tap(); capture(app, "Studio Library — empty state")
        XCTAssertFalse(app.buttons["Play"].exists)
        app.tabBars.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Neodragon")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Studio Models — pinned Neodragon")
        XCTAssertFalse(app.buttons["Install MOVD"].exists)
    }

    @MainActor func testKeyboardDismissalAndExpandedEditor() throws {
        let app = launch(), input = app.textFields["promptInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15)); reveal(input, in: app)
        input.tap(); input.typeText("A small sailboat glides across a calm lake.")
        let done = app.buttons["dismissKeyboard"]; XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(app.keyboards.count, 0)
        let expand = app.buttons["expandPrompt"]; reveal(expand, in: app, upward: false); expand.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        capture(app, "Studio expanded prompt composer")
        app.navigationBars.buttons["Done"].tap()
        app.tabBars.buttons["Settings"].tap(); XCTAssertTrue(app.buttons["exportBenchmarkFiles"].waitForExistence(timeout: 5))
    }

    @MainActor func testStyleSearchCustomStyleAndPersistence() throws {
        let app = launch()
        let browse = app.buttons["browseStyles"]; reveal(browse, in: app); browse.tap()
        XCTAssertTrue(app.navigationBars["Visual styles"].waitForExistence(timeout: 5))
        capture(app, "Studio style browser — illustrative prompt styles")
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        search.tap(); search.typeText("Retro Anime")
        let anime = app.buttons["browse-style-retroAnime"]; reveal(anime, in: app); anime.tap()
        XCTAssertTrue(browse.waitForExistence(timeout: 5)); browse.tap()
        app.buttons["newCustomStyle"].tap()
        let name = app.textFields["customStyleName"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Moonlit ink")
        let description = app.textFields["customStyleDescription"]; description.tap(); description.typeText("Silver ink, charcoal shadows, gentle motion")
        app.buttons["saveCustomStyle"].tap()
        app.navigationBars.buttons["Done"].tap()
        app.terminate(); app.launch()
        reveal(app.buttons["browseStyles"], in: app); app.buttons["browseStyles"].tap()
        app.segmentedControls["styleCollection"].buttons["Custom"].tap()
        XCTAssertTrue(app.staticTexts["Moonlit ink"].waitForExistence(timeout: 5))
        capture(app, "Studio saved custom style")
    }

    @MainActor func testExportsFrameLabAndCleanupStatusAreAccessible() throws {
        let app = launch(); app.tabBars.buttons["Settings"].tap()
        let export = app.buttons["exportBenchmarkFiles"]
        XCTAssertTrue(export.waitForExistence(timeout: 10)); XCTAssertTrue(export.isHittable); XCTAssertFalse(export.isEnabled)
        capture(app, "Studio Settings — prominent exports")
        let lab = app.buttons["openFrameLab"]; reveal(lab, in: app); lab.tap()
        XCTAssertTrue(app.navigationBars["Frame Lab"].waitForExistence(timeout: 5))
        let baseline = app.buttons["openBenchmarkTools"]; reveal(baseline, in: app); baseline.tap()
        XCTAssertFalse(app.buttons["runBaselineBenchmark"].isEnabled)
        XCTAssertFalse(app.buttons["Fast"].exists)
        app.tabBars.buttons["Models"].tap(); app.tabBars.buttons["Settings"].tap()
        // Return through preserved navigation to the Settings root.
        for _ in 0..<3 where !app.navigationBars["Settings"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        let storage = app.buttons["openStorage"]; reveal(storage, in: app); storage.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Completed · version 1")).firstMatch.waitForExistence(timeout: 5))
        capture(app, "Studio measured storage cleanup")
    }

    @MainActor func testAppearanceAndReducedEffects() throws {
        let app = launch(); app.tabBars.buttons["Settings"].tap()
        let appearance = app.buttons["appearancePicker"]
        reveal(appearance, in: app); appearance.tap(); app.buttons["Dark"].tap()
        capture(app, "Studio dark appearance")
        appearance.tap(); app.buttons["Light"].tap(); capture(app, "Studio light appearance")
        let reduce = app.switches["reducedEffectsToggle"]; reveal(reduce, in: app)
        reduce.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reduce.value as? String, "1")
        app.tabBars.buttons["Create"].tap(); capture(app, "Studio reduced effects Create")
    }

    @MainActor func testDetailComparisonAndUnavailableMemoryTrial() throws {
        let app = launch()
        let settings = app.buttons["advancedGenerationSettings"]
        reveal(settings, in: app); settings.tap()
        let detail = app.switches["upstreamDetailToggle"]
        reveal(detail, in: app)
        XCTAssertEqual(detail.value as? String, "0")
        detail.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(detail.value as? String, "1")
        XCTAssertFalse(app.switches["attentionTrialToggle"].exists)
        capture(app, "Optional upstream detail conditioning")
        app.navigationBars.buttons["Done"].tap()
        app.terminate(); app.launch()
        reveal(settings, in: app); settings.tap(); reveal(detail, in: app)
        XCTAssertEqual(detail.value as? String, "1")
        app.navigationBars.buttons["Done"].tap(); app.tabBars.buttons["Models"].tap()
        let download = app.buttons["installAttentionTrialButton"]
        reveal(download, in: app)
        XCTAssertFalse(download.isEnabled, "The optional update needs the original installed model")
        capture(app, "Optional five-second attention update")
    }
}
