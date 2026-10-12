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
                    // The scroll view's accessibility frame extends behind the
                    // keyboard. Leave room for the prediction bar, which XCTest
                    // excludes from the keyboard's reported frame.
                    let startY = app.keyboards.firstMatch.exists
                        ? min(app.keyboards.firstMatch.frame.minY - 110, app.frame.height * 0.45) : app.frame.height * 0.7
                    let origin = app.coordinate(withNormalizedOffset: .zero)
                    origin.withOffset(CGVector(dx: app.frame.width - 25, dy: startY))
                        .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width - 25, dy: 170)))
                }
                XCTAssertTrue(button.isEnabled, "Blank prompt should use defaults")
                let picture = XCTAttachment(screenshot: app.screenshot())
                picture.name = "recap-\(prompt.isEmpty ? "blank" : "custom")-\(mode)"
                picture.lifetime = .keepAlways
                add(picture)
                XCTAssertTrue(button.isHittable, app.debugDescription)
                button.tap()
                XCTAssertTrue(app.staticTexts["recap-queued"].waitForExistence(timeout: 15), app.debugDescription)
                app.terminate()
            }
        }
    }
}
