import SwiftUI

#if os(iOS)
import UIKit

extension Notification.Name {
    static let wertweitRemotePushToken = Notification.Name("wertweitRemotePushToken")
}

final class WertweitAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        NotificationCenter.default.post(name: .wertweitRemotePushToken, object: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("Wertweit could not register for remote notifications: %@", error.localizedDescription)
    }
}
#endif

@main
struct KursklarApp: App {
    #if os(iOS)
    @StateObject private var sessionStore = SupabaseSessionStore()
    @UIApplicationDelegateAdaptor(WertweitAppDelegate.self) private var appDelegate
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