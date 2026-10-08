import SwiftUI

/// 速度ゲージ(Claude Design 2026-10-08 版)。0〜160 km/h の水平バー + 下に目盛ラベル。
/// バー: トラック #0D0F13・角丸・枠/目盛線なし。フィル色は速度域で変化
/// (~80=ライム / 80~120=アンバー / 120~=レッド, StateColor.gauge)。
/// ラベル: 0 / 40 / 80 / 120 / 160 を両端揃え(space-between)、9pt mono・高さ 12。
/// MAX 表示は呼び出し側(DashboardView.gaugeRow)でバーの右に別ボックスとして置く。
struct GaugeBar: View {
    let speedKMH: Double
    var maxKMH: Double = 160

    var barHeight: CGFloat        // 横30 / 縦28
    var cornerRadius: CGFloat     // 横8 / 縦7

    private let labels = ["0", "40", "80", "120", "160"]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let fillW = CGFloat(min(max(speedKMH / maxKMH, 0), 1)) * geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Palette.track)
                    Rectangle()
                        .fill(StateColor.gauge(speedKMH))
                        .frame(width: fillW)
                        .animation(.linear(duration: 0.12), value: speedKMH)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .frame(height: barHeight)

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, text in
                    if i > 0 { Spacer(minLength: 0) }
                    Text(text)
                        .font(motoLabelFont(9, .semibold))
                        .foregroundColor(Palette.label)
                }
            }
            .frame(height: 12)
        }
    }
}
