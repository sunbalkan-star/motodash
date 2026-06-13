import SwiftUI

/// 参考モニター風の弧状(アーク)速度ゲージ。
/// 左下から上辺を回って右へ抜けるカーブに沿って、現在速度まで塗りが伸びる。
/// 目盛り(60/80/100/120)付き。
struct SpeedGauge: View {
    let speedKMH: Double
    let maxKMH: Double          // 上限(目盛りの最大値)
    let accent: Color

    /// 弧の角度範囲。-210°(左下)から 30°(右下寄り)へ、約240°スイープ。
    private let startAngle: Double = -210
    private let endAngle: Double = 30

    /// 目盛りを振る速度値
    private let ticks: [Int] = [0, 60, 80, 100, 120]

    private var progress: Double {
        min(max(speedKMH / maxKMH, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = side * 0.40
            let lineWidth = side * 0.07

            ZStack {
                // 背景トラック(暗いグレー)
                ArcShape(startAngle: startAngle, endAngle: endAngle,
                         center: center, radius: radius)
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // 速度に応じた塗り(ライムグリーン)
                ArcShape(startAngle: startAngle, endAngle: endAngle,
                         center: center, radius: radius)
                    .trim(from: 0, to: progress)
                    .stroke(accent,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .animation(.easeOut(duration: 0.3), value: progress)

                // 目盛りラベル
                ForEach(ticks, id: \.self) { tick in
                    let frac = Double(tick) / maxKMH
                    let angle = (startAngle + (endAngle - startAngle) * frac) * .pi / 180
                    let labelRadius = radius - lineWidth - side * 0.05
                    let x = center.x + cos(angle) * labelRadius
                    let y = center.y + sin(angle) * labelRadius
                    Text("\(tick)")
                        .font(.system(size: side * 0.045, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Double(tick) <= speedKMH ? accent : .gray)
                        .position(x: x, y: y)
                }
            }
        }
    }
}

/// 実寸座標でアークを描くShape。trimが正しく機能する。
private struct ArcShape: Shape {
    let startAngle: Double
    let endAngle: Double
    let center: CGPoint
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startAngle),
                endAngle: .degrees(endAngle),
                clockwise: false
            )
        }
    }
}
