import XCTest

final class LocalFramesUITests: XCTestCase {
    @MainActor
    func testKeyboardDismissesForPromptAndNumericSeedsWithoutLosingText() throws {
        let app = XCUIApplication(); app.launch()
        let prompt = app.textFields["promptInput"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10)); prompt.tap()
        prompt.typeText("A sailboat on a quiet lake.")
        let done = app.buttons["dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                                   object: app.keyboards.firstMatch)], timeout: 5), .completed)
        XCTAssertTrue((prompt.value as? String)?.contains("quiet lake") == true)
        let fixed = app.switches["fixedSeedToggle"]
        for _ in 0..<8 where !fixed.isHittable { app.swipeUp() }
        XCTAssertTrue(fixed.isHittable)
        if fixed.value as? String == "0" { fixed.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        let seed = app.textFields["generationSeed"]
        for _ in 0..<4 where !seed.isHittable { app.swipeUp() }
        seed.tap(); seed.typeText("7")
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                                   object: app.keyboards.firstMatch)], timeout: 5), .completed)
        app.tabBars.buttons["Setup"].tap()
        let tools = app.buttons["openBenchmarkTools"]
        for _ in 0..<6 where !tools.isHittable { app.swipeUp() }
        tools.tap()
        let benchmarkSeed = app.textFields["benchmarkSeed"]
        for _ in 0..<5 where !benchmarkSeed.isHittable { app.swipeUp() }
        benchmarkSeed.tap(); benchmarkSeed.typeText("8")
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                                   object: app.keyboards.firstMatch)], timeout: 5), .completed)
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["emptyLibrary"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Keyboard dismissed and tabs reachable"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func test24FPSJobExplainsReviewAndRequiresSupportedSettings() throws {
        let app = XCUIApplication(); app.launch()
        let rate = app.segmentedControls["finalFrameRate"]
        for _ in 0..<9 where !rate.isHittable { app.swipeUp() }
        XCTAssertTrue(rate.isHittable); rate.buttons["24 FPS · online finish"].tap()
        XCTAssertTrue(app.staticTexts["One job, four stages"].waitForExistence(timeout: 5))
        let issue = app.descendants(matching: .any).matching(identifier: "smoothingSelectionIssue").firstMatch
        for _ in 0..<4 where !issue.isHittable { app.swipeUp() }
        XCTAssertTrue(issue.exists)
        let generate = app.buttons["generateButton"]
        for _ in 0..<5 where !generate.isHittable { app.swipeUp() }
        XCTAssertFalse(generate.isEnabled)
        XCTAssertFalse(app.buttons["uploadSmoothingClip"].exists, "Choosing 24 FPS cannot approve a future upload")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "One job with explicit upload review"
        screenshot.lifetime = .keepAlways; add(screenshot)
        for _ in 0..<5 where !rate.isHittable { app.swipeDown() }
        rate.buttons["12 FPS · offline"].tap()
    }

    @MainActor
    func testOnlineSupportDefaultsOffAndNeverDownloadsFromItsToggle() throws {
        let app = XCUIApplication(); app.launch()
        app.tabBars.buttons["Setup"].tap()
        let link = app.buttons["openOnlineSupport"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        let toggle = app.switches["enableOnlineSupport"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        // Newer iOS Form snapshots omit off-screen rows. Reveal a control before querying it.
        func reveal(_ element: XCUIElement) {
            for _ in 0..<8 where !toggle.isHittable { app.swipeDown() }
            for _ in 0..<8 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.waitForExistence(timeout: 5))
        }
        let updates = app.buttons["checkSupportUpdates"]
        let smoothing = app.buttons["chooseSmoothingClip"]
        let account = app.buttons["helperAccountSettings"]
        XCTAssertEqual(toggle.value as? String, "0")
        reveal(account); XCTAssertFalse(account.isEnabled)
        reveal(smoothing); XCTAssertFalse(smoothing.isEnabled)
        reveal(updates); XCTAssertFalse(updates.isEnabled)
        reveal(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        reveal(account); XCTAssertTrue(account.isEnabled); account.tap()
        XCTAssertTrue(app.navigationBars["Helper account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finishHelperConnection"].exists, "Opening account settings must not start sign-in")
        XCTAssertFalse(app.staticTexts["Checking helper connection"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(smoothing); XCTAssertTrue(smoothing.isEnabled)
        reveal(updates); XCTAssertTrue(updates.isEnabled)
        XCTAssertFalse(app.buttons["Cancel support request"].exists, "Enabling support must not initiate network work")
        XCTAssertFalse(app.buttons["Send this report"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Optional online support with manual checks"; screenshot.lifetime = .keepAlways; add(screenshot)
        reveal(smoothing); smoothing.tap()
        XCTAssertTrue(app.staticTexts["noSmoothingClips"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["uploadSmoothingClip"].exists, "An empty library must not offer an upload")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(toggle)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        reveal(smoothing); XCTAssertFalse(smoothing.isEnabled)
        reveal(updates); XCTAssertFalse(updates.isEnabled)
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
        app.buttons["dismissKeyboard"].tap()
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
