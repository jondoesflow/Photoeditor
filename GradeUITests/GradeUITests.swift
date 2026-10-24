import XCTest

/// Drives the real app on the simulator with the bundled demo photo. Screenshots are attached
/// to the test results (CI exports them to the `ci-reports` branch).
final class GradeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForCanvas(_ app: XCUIApplication, label: String? = nil) -> XCUIElement {
        let canvas = app.descendants(matching: .any)["canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        if let label {
            let predicate = NSPredicate(format: "label == %@", "Photo with \(label)")
            expectation(for: predicate, evaluatedWith: canvas)
            waitForExpectations(timeout: 5)
            // The label changes as soon as a look is picked; give the preview a moment to render.
            Thread.sleep(forTimeInterval: 0.8)
        }
        return canvas
    }

    /// Drags a horizontal strip until the element is on screen.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        var attempts = 0
        while !element.isHittable && attempts < 8 {
            let strip = app.scrollViews.containing(.button, identifier: element.identifier).firstMatch
            let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance: CGFloat = element.frame.midX > screen.midX ? -220 : 220
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
            attempts += 1
        }
    }

    @MainActor
    func testEmptyState() {
        let app = launch(["-GradeDemo", "-GradeEmpty"])
        XCTAssertTrue(app.buttons["choosePhotoButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveButton"].isEnabled)
        screenshot("01-empty", app)
    }

    @MainActor
    func testApplyPresetCompareAndSave() {
        let app = launch(["-GradeDemo"])
        _ = waitForCanvas(app, label: "Original")
        screenshot("02-original", app)

        let neon = app.buttons["preset-neon-nights"]
        XCTAssertTrue(neon.waitForExistence(timeout: 10))
        neon.tap()
        let canvas = waitForCanvas(app, label: "Neon Nights")
        XCTAssertTrue(app.sliders["intensitySlider"].exists)
        screenshot("03-neon-nights", app)

        app.buttons["compareButton"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
        screenshot("04-before-after", app)
        app.buttons["compareButton"].tap()

        app.buttons["saveButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["savedToast"].waitForExistence(timeout: 20))
        screenshot("05-saved", app)
    }

    @MainActor
    func testCategoriesFilterPresets() {
        let app = launch(["-GradeDemo"])
        _ = waitForCanvas(app)
        app.buttons["category-mono"].tap()
        XCTAssertTrue(app.buttons["preset-noir"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["preset-neon-nights"].exists)
        app.buttons["preset-noir"].tap()
        _ = waitForCanvas(app, label: "Noir")
        screenshot("06-category-mono", app)
        app.buttons["category-all"].tap()
        XCTAssertTrue(app.buttons["preset-neon-nights"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAdjustAndSaveLook() {
        let app = launch(["-GradeDemo", "-GradePreset", "teal-orange"])
        _ = waitForCanvas(app, label: "Teal & Orange")
        app.buttons["Adjust"].tap()

        app.buttons["adjust-grain"].tap()
        let slider = app.sliders["adjustSlider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertTrue(app.buttons["resetAdjustmentsButton"].isEnabled)
        screenshot("07-adjust", app)

        app.buttons["saveLookButton"].tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Holiday")
        app.alerts.buttons["Save"].tap()

        app.buttons["Presets"].tap()
        XCTAssertTrue(app.buttons["category-mine"].waitForExistence(timeout: 5))
        app.buttons["category-mine"].tap()
        XCTAssertTrue(app.buttons["Holiday"].waitForExistence(timeout: 5))
        _ = waitForCanvas(app, label: "Holiday")
        screenshot("08-my-looks", app)
    }

    /// One screenshot per preset on the demo photo, so every look can be reviewed from CI.
    @MainActor
    func testPresetGallery() {
        let app = launch(["-GradeDemo"])
        _ = waitForCanvas(app)
        let presets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preset-'"))
        XCTAssertTrue(presets.firstMatch.waitForExistence(timeout: 10))
        let identifiers = presets.allElementsBoundByIndex.map(\.identifier)
        XCTAssertGreaterThanOrEqual(identifiers.count, 21)

        for (index, identifier) in identifiers.enumerated() {
            let button = app.buttons[identifier]
            scrollIntoView(button, in: app)
            button.tap()
            let name = button.label
            _ = waitForCanvas(app, label: name)
            screenshot(String(format: "gallery-%02d-%@", index, identifier), app)
        }
    }
}
