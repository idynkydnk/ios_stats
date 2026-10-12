import XCTest

final class RankingLayoutUITests: XCTestCase {
    @MainActor
    func testDefaultAndAccessibleMetrics() throws {
        let sizes = ["large", "xxxLarge", "accessibility1", "accessibility3", "accessibility5"]
        try checkScenarios([320, 375, 390].flatMap { width in sizes.map { (width, $0, false) } })
    }

    @MainActor
    func testLargeRecordMetrics() throws {
        try checkScenarios([320, 375, 390].map { ($0, "large", true) })
    }

    @MainActor
    private func checkScenarios(_ scenarios: [(Int, String, Bool)]) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for (width, size, largeRecords) in scenarios {
                app.launchEnvironment = ["QA_WIDTH": "\(width)", "QA_TEXT_SIZE": size, "QA_RECORDS": largeRecords ? "large" : "daily"]
                app.launch()
                let viewport = app.scrollViews["ranking-viewport"]
                XCTAssertTrue(viewport.waitForExistence(timeout: 15))
                let viewportFrame = viewport.frame
                let initial = XCTAttachment(screenshot: app.screenshot())
                initial.name = "\(width)-\(size)-\(largeRecords ? "large-records" : "daily")-top"
                initial.lifetime = .keepAlways
                add(initial)
                for (name, values) in [
                    ("Alexandra Montgomery", ["81.35", "12", "3", "+137", "80%", "15"]),
                    ("Christopher Longlastname", largeRecords ? ["100.00", "1234", "1000", "-1234", "100%", "2234"] : ["100.00", "4", "7", "-13", "100%", "11"])
                ] {
                    let table = app.scrollViews["ranking-table-scroll"]
                    if size == "large" {
                        XCTAssertTrue(table.exists, "Normal text should use the website-style table")
                        for _ in 0..<3 { table.swipeRight() }
                        // Essential daily stats must be visible before any horizontal scroll.
                        for metric in ["rating", "wins", "losses", "plusminus"] {
                            let element = app.staticTexts.matching(identifier: "ranking-\(name)-\(metric)").firstMatch
                            XCTAssertTrue(element.isHittable, "\(metric) must be visible without scrolling")
                            XCTAssertGreaterThanOrEqual(element.frame.minX, table.frame.minX - 1)
                            XCTAssertLessThanOrEqual(element.frame.maxX, table.frame.maxX + 1, "\(metric) requires scrolling at \(width) points")
                        }
                    }
                    let nameY: CGFloat? = size == "large" ? app.staticTexts.matching(identifier: "ranking-\(name)-name").firstMatch.frame.midY : nil
                    var rowY: CGFloat?
                    for (metric, value) in zip(["rating", "wins", "losses", "plusminus", "winpct", "games"], values) {
                        let element = app.descendants(matching: .any).matching(identifier: "ranking-\(name)-\(metric)").firstMatch
                        var attempts = 0
                        while (!element.isHittable || element.frame.maxX > viewportFrame.maxX + 1) && attempts < 12 {
                            if size == "large" {
                                table.swipeLeft(velocity: .slow)
                            } else {
                                viewport.swipeUp(velocity: .slow)
                            }
                            attempts += 1
                        }
                        if !element.exists { print(app.debugDescription) }
                        XCTAssertTrue(element.exists, "Missing \(name) \(metric), \(width)/\(size)")
                        XCTAssertTrue(element.isHittable, "Cannot reach \(metric) by scrolling, \(width)/\(size)")
                        let frame = element.frame
                        XCTAssertGreaterThanOrEqual(frame.minX, viewportFrame.minX - 1, "Left clipping \(metric)")
                        XCTAssertLessThanOrEqual(frame.maxX, viewportFrame.maxX + 1, "Right clipping \(metric)")
                        let spokenValue = element.label.replacingOccurrences(of: ",", with: "")
                        XCTAssertTrue(spokenValue.contains(value), "Incomplete value: \(element.label), expected \(value)")
                        if size == "large" {
                            if let y = rowY { XCTAssertEqual(frame.midY, y, accuracy: 1, "Normal-text metrics must share one row") }
                            rowY = frame.midY
                            XCTAssertLessThan(frame.height, 24, "Normal-text value wrapped onto multiple lines")
                            XCTAssertEqual(try XCTUnwrap(nameY), frame.midY, accuracy: 1, "Player and stats must share a table row")
                        }
                        if metric == "plusminus" {
                        let attachment = XCTAttachment(screenshot: app.screenshot())
                        attachment.name = "\(width)-\(size)-\(name)-\(metric)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                        }
                    }
                }
                app.terminate()
        }
    }
}
