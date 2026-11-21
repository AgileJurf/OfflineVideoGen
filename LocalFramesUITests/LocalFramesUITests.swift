import XCTest

final class LocalFramesUITests: XCTestCase {
    @MainActor
    func testOnlineSupportDefaultsOffAndNeverDownloadsFromItsToggle() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Setup"].tap()
        let link = app.buttons["openOnlineSupport"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        let toggle = app.switches["enableOnlineSupport"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["checkSupportUpdates"].isEnabled)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(app.buttons["checkSupportUpdates"].isEnabled)
        XCTAssertFalse(app.buttons["Cancel support request"].exists, "Enabling support must not initiate network work")
        XCTAssertFalse(app.buttons["Send this report"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Optional online support with manual checks"; screenshot.lifetime = .keepAlways; add(screenshot)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons["checkSupportUpdates"].isEnabled)
    }
    @MainActor
    func testStylesFramingPersistAndUnsupportedModesStayUnavailable() throws {
        let app = XCUIApplication()
        app.launch()
        let style = app.buttons["style-photorealistic"]
        for _ in 0..<5 where !style.isHittable { app.swipeUp() }
        XCTAssertTrue(style.waitForExistence(timeout: 5)); style.tap()
        XCTAssertTrue(style.isSelected)
        let framing = app.segmentedControls["outputFramingPicker"]
        for _ in 0..<5 where !framing.isHittable { app.swipeUp() }
        framing.buttons["Portrait crop"].tap()
        XCTAssertTrue(framing.buttons["Portrait crop"].isSelected)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Center crop · 144 × 256")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Explicit crop framing and prompt styles"
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        for _ in 0..<5 where !app.buttons["style-photorealistic"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["style-photorealistic"].isSelected)
        for _ in 0..<5 where !app.segmentedControls["outputFramingPicker"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.segmentedControls["outputFramingPicker"].buttons["Portrait crop"].isSelected)
        app.tabBars.buttons["Setup"].tap()
        let capabilities = app.buttons["Model capabilities and optional models"]
        for _ in 0..<7 where !capabilities.isHittable { app.swipeUp() }
        capabilities.tap()
        XCTAssertTrue(app.staticTexts["Image to Video · unavailable"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Generate Extension"].exists)
    }
    @MainActor
    func testDeveloperBenchmarksAreLocalAndPresetsStayUnvalidated() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Setup"].tap()
        let link = app.buttons["openBenchmarks"]
        for _ in 0..<4 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        let preset = app.descendants(matching: .any).matching(identifier: "benchmarkBaselinePreset").firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertTrue(preset.label.contains("Baseline"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Benchmark reference configuration"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Fast"].exists)
        XCTAssertFalse(app.buttons["Fast"].exists, "Unvalidated preset must not become selectable")
    }

    @MainActor
    func testLaunchPromptAndModelGate() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.textFields["promptInput"].waitForExistence(timeout: 10))
        let input = app.textFields["promptInput"]
        input.tap()
        input.typeText("A small sailboat glides across a calm lake.")
        for _ in 0..<6 where !app.buttons["generateButton"].isHittable { app.swipeUp() }
        XCTAssertFalse(app.buttons["generateButton"].isEnabled)
        app.buttons["openSetup"].tap()
        XCTAssertTrue(app.buttons["installModelButton"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Model setup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLibraryNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Your first frame awaits"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Create"].tap()
        for _ in 0..<6 where !app.buttons["generateButton"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["generateButton"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Create screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
