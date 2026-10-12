import SwiftUI

@main
struct KursklarApp: App {
    #if os(iOS)
    @StateObject private var sessionStore = SupabaseSessionStore()
    #endif

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            AuthGateView(store: sessionStore)
        }
        #else
        #if os(macOS)
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 760)
        #else
        WindowGroup {
            ContentView()
        }
        #endif
        #endif
    }
}