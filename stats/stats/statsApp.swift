import SwiftUI

@main
struct statsApp: App {
    @ObservedObject private var theme = SiteTheme.shared

    var body: some Scene {
        WindowGroup {
            SiteRootView()
                .preferredColorScheme(theme.colorScheme)
        }
    }
}
