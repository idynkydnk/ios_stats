import SwiftUI

/// Legacy view; main app uses MainTabView with Firestore-only storage.
struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
}
