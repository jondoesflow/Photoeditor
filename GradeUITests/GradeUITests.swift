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
        // Opening includes analysis, which on the CPU-only CI simulator can take most of a minute.
        XCTAssertTrue(canvas.waitForExistence(timeout: 90))
        // The label changes as soon as a look is picked; the value turns "ready" once its preview has rendered.
        let format = label == nil ? "value == 'ready'" : "label == %@ AND value == 'ready'"
        let predicate = NSPredicate(format: format, argumentArray: label.map { ["Photo with \($0)"] } ?? [])
        expectation(for: predicate, evaluatedWith: canvas)
        // Generous: the CI simulator renders on the CPU, and some enhancements are heavy there.
        waitForExpectations(timeout: 60)
        return canvas
    }

    /// Drags a horizontal strip until the element is fully on screen. (`isHittable` can't be asked of
    /// an element that is off screen, so this goes by its frame.)
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<10 {
            let frame = element.frame
            guard frame.minX < screen.minX + 8 || frame.maxX > screen.maxX - 8 else { return }
            let strip = app.scrollViews.containing(.button, identifier: element.identifier).firstMatch
            let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let distance: CGFloat = frame.midX > screen.midX ? -200 : 200
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: distance, dy: 0)))
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
        // iOS 26 exposes confirmation dialog buttons twice, so take the first match.
        let saveAsNew = app.buttons["Save as New Photo"].firstMatch
        XCTAssertTrue(saveAsNew.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Replace Original"].firstMatch.exists)
        screenshot("05-save-choice", app)
        saveAsNew.tap()
        let toast = app.descendants(matching: .any)["savedToast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20))
        XCTAssertTrue(toast.label.contains("Saved as new photo"), toast.label)
        screenshot("05-saved", app)

        // Wait for the confirmation to go, then replace the original instead.
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: toast)
        waitForExpectations(timeout: 10)
        app.buttons["saveButton"].tap()
        let replace = app.buttons["Replace Original"].firstMatch
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        replace.tap()
        XCTAssertTrue(toast.waitForExistence(timeout: 20))
        XCTAssertTrue(toast.label.contains("Original replaced"), toast.label)
        screenshot("05-replaced", app)
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

        let grain = app.buttons["adjust-grain"]
        scrollIntoView(grain, in: app)
        grain.tap()
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
        let myLooks = app.buttons["category-mine"]
        XCTAssertTrue(myLooks.waitForExistence(timeout: 5))
        scrollIntoView(myLooks, in: app)
        myLooks.tap()
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

    /// Autopilot and each Enhance tool on the demo portrait, one screenshot each.
    @MainActor
    func testEnhanceGallery() {
        let app = launch(["-GradeDemo", "-GradeDemoPhoto", "portrait"])
        _ = waitForCanvas(app)
        // The CI simulator has no Neural Engine, so analysis and thumbnails keep it busy for a while
        // after the photo appears; a tap can be lost in that time, so try again if needed.
        let summary = app.staticTexts["insightsSummary"]
        for _ in 0..<3 where !summary.exists {
            app.buttons["Enhance"].tap()
            _ = summary.waitForExistence(timeout: 20)
        }
        XCTAssertTrue(summary.exists)
        XCTAssertTrue(summary.label.contains("face"), "Analysis summary: \(summary.label)")

        app.buttons["autopilotButton"].tap()
        _ = waitForCanvas(app)
        screenshot("enhance-00-autopilot", app)
        app.buttons["resetEnhanceButton"].tap()
        _ = waitForCanvas(app)

        let sliderTools = ["light", "colour", "denoise", "detail", "faces", "dust"]
        for (index, tool) in sliderTools.enumerated() {
            let button = app.buttons["enhance-\(tool)"]
            scrollIntoView(button, in: app)
            button.tap()
            let slider = app.sliders["enhanceSlider"]
            XCTAssertTrue(slider.waitForExistence(timeout: 5), "\(tool) has no slider")
            slider.adjust(toNormalizedSliderPosition: 1)
            _ = waitForCanvas(app)
            screenshot(String(format: "enhance-%02d-%@", index + 1, tool), app)
            app.buttons["resetEnhanceButton"].tap()
            _ = waitForCanvas(app)
        }

        let background = app.buttons["enhance-background"]
        scrollIntoView(background, in: app)
        background.tap()
        let blur = app.buttons["Blur"]
        if blur.waitForExistence(timeout: 3), blur.isEnabled {
            blur.tap()
            _ = waitForCanvas(app)
            screenshot("enhance-07-background-blur", app)
            app.buttons["Remove"].tap()
            _ = waitForCanvas(app)
            screenshot("enhance-08-background-remove", app)
            app.buttons["Keep"].tap()
            _ = waitForCanvas(app)
        } else {
            screenshot("enhance-07-background-unavailable", app)
        }

        let upscale = app.buttons["enhance-upscale"]
        scrollIntoView(upscale, in: app)
        upscale.tap()
        app.buttons["2×"].tap()
        let size = app.staticTexts["upscaleSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        XCTAssertTrue(size.label.contains("3200 × 4800"), size.label)
        screenshot("enhance-09-upscale", app)
    }
}
