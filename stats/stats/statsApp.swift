import SwiftUI
import UIKit

@main
struct statsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var theme = SiteTheme.shared
    @ObservedObject private var auth = SiteAuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.sessionReady {
                    if let error = auth.sessionRestoreError {
                        VStack(spacing: 16) {
                            Text(error).multilineTextAlignment(.center)
                            Button("Try again") { Task { await auth.refreshMe() } }
                        }
                        .padding()
                    } else {
                        ProgressView("Signing in")
                    }
                } else if (auth.biometricEnabled && !auth.isLoggedIn) || (auth.isLoggedIn && auth.needsLoginEmail) {
                    NavigationStack { LoginView() }
                } else {
                    SiteRootView().id(auth.token)
                }
            }
                .task {
                    if scenePhase == .active { await auth.restoreSessionOnLaunch() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await auth.restoreSessionOnLaunch(); SiteLocalGameStore.shared.startSync() }
                    }
                }
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
