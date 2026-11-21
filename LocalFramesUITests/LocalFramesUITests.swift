import XCTest

final class LocalFramesUITests: XCTestCase {
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
