import XCTest

final class RankingLayoutUITests: XCTestCase {
    @MainActor
    func testSinglePromptAndBothGenerationModes() throws {
        continueAfterFailure = false
        for prompt in ["", "Keep it funny. For the picture, show a green net."] {
            for mode in ["none", "image"] {
                let app = XCUIApplication()
                app.launchEnvironment = ["QA_PROMPT": prompt, "QA_MODE": mode]
                app.launch()
                XCTAssertTrue(app.staticTexts["Recap and picture prompt (optional)"].waitForExistence(timeout: 15))
                XCTAssertEqual(app.textFields.count + app.textViews.count, 1, "Exactly one prompt field")
                XCTAssertFalse(app.buttons["Standard Recap"].exists)
                XCTAssertFalse(app.staticTexts["Extra illustration details (optional)"].exists)
                if !prompt.isEmpty {
                    let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
                    field.tap()
                    field.typeText(prompt)
                }
                let title = mode == "none" ? "Text only" : "With illustration"
                let button = app.buttons[title]
                for _ in 0..<4 {
                    if button.isHittable { break }
                    app.scrollViews.firstMatch.swipeUp()
                }
                XCTAssertTrue(button.isEnabled, "Blank prompt should use defaults")
                XCTAssertTrue(button.isHittable)
                let picture = XCTAttachment(screenshot: app.screenshot())
                picture.name = "recap-\(prompt.isEmpty ? "blank" : "custom")-\(mode)"
                picture.lifetime = .keepAlways
                add(picture)
                button.tap()
                XCTAssertTrue(app.staticTexts["recap-queued"].waitForExistence(timeout: 15), app.debugDescription)
                app.terminate()
            }
        }
    }
}
