import Foundation
import UserNotifications

/// ローカル通知の管理。リモートPush(APNs)は有償Developer Programが必要なため、
/// 無料Apple ID運用ではローカル通知のみを使う。
@MainActor
final class NotificationManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var lastResult: String = ""

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            Task { @MainActor in
                self.isAuthorized = granted
                if let error {
                    self.lastResult = "権限エラー: \(error.localizedDescription)"
                } else {
                    self.lastResult = granted ? "通知許可済み ✅" : "通知が拒否されました ❌"
                }
            }
        }
    }

    /// n秒後にローカル通知をスケジュールする
    func schedule(after seconds: TimeInterval = 5) {
        let content = UNMutableNotificationContent()
        content.title = "MyApp テスト通知"
        content.body = "ローカル通知は無料Apple IDでも動きます 🎉"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds), repeats: false
        )
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                if let error {
                    self.lastResult = "通知登録エラー: \(error.localizedDescription)"
                } else {
                    self.lastResult = "\(Int(seconds))秒後に通知します(ホームに戻って待機)"
                }
            }
        }
    }
}
