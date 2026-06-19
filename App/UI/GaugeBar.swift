import SwiftUI

/// 速度ゲージ(ハンドオフ「上辺水平バー」v2)。0〜160 km/h を画面上辺に水平表示。
/// 全周ボーダー＋角丸の低いトラック面の上に、全高の目盛り2層(minor 10km/h刻み /
/// major 40km/h刻み、色だけ違う)、左端から現在速度割合まで伸びるライムの発光フィル、
/// 下に 40/80/120/160 のラベル、横画面では右端にMAXピル(長押しでリセット)。
struct GaugeBar: View {
    let speedKMH: Double
    let maxSpeedKMH: Double
    var maxKMH: Double = 160

    // 向きで変わる寸法
    var barHeight: CGFloat        // 横30 / 縦28
    var cornerRadius: CGFloat     // 横8 / 縦7
    var labelSize: CGFloat        // 横15 / 縦13
    var showMaxPill: Bool         // 横のみ
    /// MAXピル長押しで最高速をリセット
    var onResetMax: (() -> Void)? = nil

    private let labels: [(text: String, pct: CGFloat)] = [
        ("40", 0.25), ("80", 0.5), ("120", 0.75), ("160", 1.0)
    ]

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                let fillW = CGFloat(min(max(speedKMH / maxKMH, 0), 1)) * w

                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Palette.track)

                        Canvas { ctx, size in
                            let n = 16  // 10km/h刻み = 1/16。minor/majorとも全高、色のみ差
                            for i in 0...n {
                                let x = size.width * CGFloat(i) / CGFloat(n)
                                let isMajor = i % 4 == 0   // 40km/h刻み = 1/4
                                var p = Path()
                                p.move(to: CGPoint(x: x, y: 0))
                                p.addLine(to: CGPoint(x: x, y: size.height))
                                ctx.stroke(p, with: .color(isMajor ? Palette.tickMajor : Palette.tickMinor),
                                           lineWidth: 2)
                            }
                        }

                        Rectangle()
                            .fill(Palette.lime)
                            .frame(width: fillW)
                            .shadow(color: Palette.lime.opacity(0.65), radius: 8)
                            .animation(.linear(duration: 0.12), value: speedKMH)
                    }
                    .frame(height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Palette.borderStrong, lineWidth: 1.5))

                    if showMaxPill {
                        maxPill
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 8)
                    }
                }
                .frame(height: barHeight)
            }
            .frame(height: barHeight)

            labelRow
        }
    }

    private var maxPill: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(Int(maxSpeedKMH.rounded()))")
                .font(motoNumberFont(16, .bold))
                .foregroundColor(Palette.lime)
            Text("MAX")
                .font(.system(size: 11))
                .foregroundColor(Palette.textMid)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.track))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.lime, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onLongPressGesture { onResetMax?() }
    }

    private var labelRow: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(labels, id: \.text) { item in
                let approxWidth = CGFloat(item.text.count) * labelSize * 0.62
                // 160は右端揃え(右にはみ出さない)、それ以外は中央揃え
                let x = item.pct >= 1.0 ? (w - approxWidth / 2) : (w * item.pct)
                Text(item.text)
                    .font(motoLabelFont(labelSize, .semibold))
                    .foregroundColor(Palette.label)
                    .position(x: x, y: labelSize * 0.7)
            }
        }
        .frame(height: labelSize + 4)
    }
}
