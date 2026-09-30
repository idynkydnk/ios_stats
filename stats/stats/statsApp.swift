import SwiftUI

@main
struct statsApp: App {
    @ObservedObject private var theme = SiteTheme.shared

    var body: some Scene {
        WindowGroup {
            SiteRootView()
                .environment(\.siteAppearance, theme.appearance)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.appearance.accent)
                .accentColor(theme.appearance.accent)
                .scrollContentBackground(.hidden)
                .background(theme.appearance.background)
        }
    }
}
