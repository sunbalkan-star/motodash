import SwiftUI

/// ダッシュボード ⇄ マップ の切替。左スワイプでマップ、右スワイプでダッシュボードへ。
/// 表示中の画面は次回起動時も維持。非表示側は破棄する(マップ非表示中は地図描画の電力を使わない)。
struct RootView: View {
    @EnvironmentObject var theme: ThemeManager
    @AppStorage("ui.showMap") private var showMap = false
    /// マップの操作モード中は地図のスクロールと競合するためスワイプ切替を止める
    @State private var swipeLocked = false
    /// 設定シートはここで出す(配色が変わって下の画面を作り直しても閉じないように)
    @State private var showSettings = false

    var body: some View {
        ZStack {
            if showMap {
                MapDashView().transition(.move(edge: .trailing))
            } else {
                DashboardView(openSettings: { showSettings = true }).transition(.move(edge: .leading))
            }
        }
        // 配色(Palette)は静的な値なので、切り替わったら画面ごと作り直して全色を反映する
        .id(theme.current)
        .background(Palette.bg.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(theme)
        }
        .onPreferenceChange(SwipeLockKey.self) { swipeLocked = $0 }
        // カードのタップ・長押しと共存させるため simultaneous。誤爆防止に横 80pt 以上かつ横優位のみ
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { v in
                guard !swipeLocked else { return }
                let dx = v.translation.width
                guard abs(dx) > 80, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                let toMap = dx < 0
                guard toMap != showMap else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showMap = toMap }
            }
        )
    }
}

/// 子画面からスワイプ切替を止めるためのフラグ
struct SwipeLockKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
