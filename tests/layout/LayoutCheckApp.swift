import SwiftUI

// Cloud-only test entry point. The production app entry point is excluded from
// the generated test project; every standings view below is production code.
@main
struct LayoutCheckApp: App {
    private let env = ProcessInfo.processInfo.environment
    private var size: DynamicTypeSize {
        switch env["QA_TEXT_SIZE"] {
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility3": return .accessibility3
        case "accessibility5": return .accessibility5
        default: return .large
        }
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    RankingTable(title: "Today's Stats", rows: [
                        RankingRow(name: "Alexandra Montgomery", wins: 12, losses: 3, winPct: 0.8, rating: 81.35, plusMinus: 137),
                        RankingRow(name: "Christopher Longlastname", wins: env["QA_RECORDS"] == "large" ? 1234 : 4, losses: env["QA_RECORDS"] == "large" ? 1000 : 7, winPct: 1, rating: 100, plusMinus: env["QA_RECORDS"] == "large" ? -1234 : -13)
                    ], showRating: true, showPlusMinus: true, year: "2026", section: .doubles)
                }
                .frame(width: CGFloat(Double(env["QA_WIDTH"] ?? "375") ?? 375))
                .accessibilityIdentifier("ranking-viewport")
                .background(SiteAppearance().background)
            }
            .dynamicTypeSize(size)
            .environment(\.siteAppearance, SiteAppearance())
            .preferredColorScheme(.dark)
        }
    }
}
