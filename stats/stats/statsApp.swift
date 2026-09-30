import SwiftUI

@main
struct statsApp: App {
    @ObservedObject private var theme = SiteTheme.shared
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.sessionReady {
                    ProgressView("Signing in")
                } else {
                    SiteRootView().id(auth.token)
                }
            }
                .task { await auth.refreshMe() }
                .environment(\.siteAppearance, theme.appearance)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.appearance.accent)
                .accentColor(theme.appearance.accent)
                .scrollContentBackground(.hidden)
                .background(theme.appearance.background)
        }
    }
}
