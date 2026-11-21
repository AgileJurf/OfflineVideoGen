import XCTest

final class LocalFramesUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["generateButton"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Create screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
