import SwiftUI
import UserNotifications

@main
struct MotoDashApp: App {
    @StateObject private var ride = RideManager()
    @StateObject private var tpms = TPMSManager()
    @StateObject private var nav = NavManager()
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ride)
                .environmentObject(tpms)
                .environmentObject(nav)
                .environmentObject(theme)
                // 案内はダッシュボード表示中も進める。配色の日の出・日の入り判定にも現在地を渡す
                .onReceive(ride.$location) {
                    guard let loc = $0 else { return }
                    nav.update(loc)
                    theme.update(location: loc)
                }
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
