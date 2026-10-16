import SwiftUI
import UserNotifications

@main
struct MotoDashApp: App {
    @StateObject private var ride = RideManager()
    @StateObject private var tpms = TPMSManager()
    @StateObject private var nav = NavManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ride)
                .environmentObject(tpms)
                .environmentObject(nav)
                // 案内はダッシュボード表示中も進める
                .onReceive(ride.$location) { if let loc = $0 { nav.update(loc) } }
                .onAppear {
                    ride.start()
                    // 低圧アラート用の通知権限(初回のみダイアログ表示)
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .sound]
                    ) { _, _ in }
                }
        }
    }
}
