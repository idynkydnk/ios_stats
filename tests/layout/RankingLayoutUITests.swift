import XCTest

final class RankingLayoutUITests: XCTestCase {
    @MainActor
    func testAllMetricsAtPhoneWidthsAndTextSizes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let sizes = ["large", "xxxLarge", "accessibility1", "accessibility3", "accessibility5"]
        let scenarios = [320, 375, 390].flatMap { width in sizes.map { (width, $0, false) } }
            + [320, 375, 390].map { ($0, "large", true) }
        for (width, size, largeRecords) in scenarios {
                app.launchEnvironment = ["QA_WIDTH": "\(width)", "QA_TEXT_SIZE": size, "QA_RECORDS": largeRecords ? "large" : "daily"]
                app.launch()
                let viewport = app.scrollViews["ranking-viewport"]
                XCTAssertTrue(viewport.waitForExistence(timeout: 15))
                let initial = XCTAttachment(screenshot: app.screenshot())
                initial.name = "\(width)-\(size)-\(largeRecords ? "large-records" : "daily")-top"
                initial.lifetime = .keepAlways
                add(initial)
                for (name, values) in [
                    ("Alexandra Montgomery", ["81.35", "12", "3", "80%", "+137"]),
                    ("Christopher Longlastname", largeRecords ? ["100.00", "1234", "1000", "100%", "-1234"] : ["100.00", "4", "7", "100%", "-13"])
                ] {
                    for (metric, value) in zip(["rating", "wins", "losses", "winpct", "plusminus"], values) {
                        let element = app.descendants(matching: .any).matching(identifier: "ranking-\(name)-\(metric)").firstMatch
                        var attempts = 0
                        while !element.isHittable && attempts < 12 {
                            viewport.swipeUp(velocity: .slow)
                            attempts += 1
                        }
                        if !element.exists { print(app.debugDescription) }
                        XCTAssertTrue(element.exists, "Missing \(name) \(metric), \(width)/\(size)")
                        XCTAssertTrue(element.isHittable, "Cannot reach \(metric) by vertical scrolling, \(width)/\(size)")
                        XCTAssertGreaterThanOrEqual(element.frame.minX, viewport.frame.minX - 1, "Left clipping \(metric)")
                        XCTAssertLessThanOrEqual(element.frame.maxX, viewport.frame.maxX + 1, "Right clipping \(metric)")
                        XCTAssertTrue(element.label.contains(value), "Incomplete value: \(element.label), expected \(value)")
                        if metric == "rating" || metric == "plusminus" {
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
