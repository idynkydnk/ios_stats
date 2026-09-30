import Foundation
import SwiftUI

@main
struct AppearanceTests {
    static func main() {
        let suite = "stats-appearance-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let theme = SiteTheme(defaults: defaults)
        precondition(theme.mode == .dark && theme.palette == .ocean && theme.style == .classic)
        for mode in SiteAppearanceMode.allCases {
            for palette in SitePalette.allCases {
                for style in SiteVisualStyle.allCases {
                    theme.mode = mode
                    theme.palette = palette
                    theme.style = style
                    let reopened = SiteTheme(defaults: defaults)
                    precondition(reopened.mode == mode && reopened.palette == palette && reopened.style == style)
                    precondition(reopened.colorScheme == (mode == .light ? .light : .dark))
                }
            }
        }
        defaults.set("invalid", forKey: "srPalette")
        defaults.set("invalid", forKey: "srStyle")
        defaults.set("invalid", forKey: "srTheme")
        let fallback = SiteTheme(defaults: defaults)
        precondition(fallback.mode == .dark && fallback.palette == .ocean && fallback.style == .classic)
        precondition(SiteVisualStyle.classic.radius(24) == 24)
        precondition(SiteVisualStyle.soft.radius(24) > 24)
        precondition(SiteVisualStyle.sharp.radius(24) == 2)
        print("All 24 appearance combinations persist; invalid values fall back safely; style shapes pass.")
    }
}
