import SwiftUI
import UIKit

@main
struct statsApp: App {
    @ObservedObject private var theme = SiteTheme.shared
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.sessionReady {
                    ProgressView("Signing in")
                } else if auth.isLoggedIn && auth.needsLoginEmail {
                    NavigationStack { LoginView() }
                } else {
                    SiteRootView().id(auth.token)
                }
            }
                .task { await auth.refreshMe() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    for cache in [SiteBrowseCache.shared, .playerDetails, .playerSuggestions, .library, .navigation] {
                        cache.trimMemory()
                    }
                }
                .environment(\.siteAppearance, theme.appearance)
                .preferredColorScheme(theme.colorScheme)
                .tint(theme.appearance.accent)
                .accentColor(theme.appearance.accent)
                .scrollContentBackground(.hidden)
                .background(theme.appearance.background)
        }
    }
}
