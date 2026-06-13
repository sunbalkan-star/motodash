import SwiftUI
import UserNotifications

@main
struct MyTemplateApp: App {
    @StateObject private var ride = RideManager()
    @StateObject private var tpms = TPMSManager()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(ride)
                .environmentObject(tpms)
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
