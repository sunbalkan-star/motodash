import SwiftUI

/// ダッシュボード ⇄ マップ の切替。左スワイプでマップ、右スワイプでダッシュボードへ。
/// 表示中の画面は次回起動時も維持。非表示側は破棄する(マップ非表示中は地図描画の電力を使わない)。
struct RootView: View {
    @AppStorage("ui.showMap") private var showMap = false

    var body: some View {
        ZStack {
            if showMap {
                MapDashView().transition(.move(edge: .trailing))
            } else {
                DashboardView().transition(.move(edge: .leading))
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        // カードのタップ・長押しと共存させるため simultaneous。誤爆防止に横 80pt 以上かつ横優位のみ
        .simultaneousGesture(
            DragGesture(minimumDistance: 40).onEnded { v in
                let dx = v.translation.width
                guard abs(dx) > 80, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                let toMap = dx < 0
                guard toMap != showMap else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showMap = toMap }
            }
        )
    }
}
