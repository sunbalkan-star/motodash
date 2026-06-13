import SwiftUI

/// 参考モニター風の「逆L字」速度ゲージ。
/// 左辺を下から上へ立ち上がり、左上角で曲がって上辺を右へ水平に走る。
/// trim はパス全長基準で進むため、左辺/上辺の実長比を速度比に一致させ、
/// 塗りと目盛りがズレないようにする。
struct SpeedGauge: View {
    let speedKMH: Double
    let maxKMH: Double
    let accent: Color

    /// 角に対応する速度(画像では左辺=20〜40なので角は40km/h)
    private let cornerSpeed: Double = 40

    private let ticks: [Int] = [20, 40, 60, 80, 100, 120]

    private var progress: Double { min(max(speedKMH / maxKMH, 0), 1) }
    private var cornerFraction: Double { cornerSpeed / maxKMH }  // 全長に占める左辺の割合

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineWidth = min(w, h) * 0.16
            let half = lineWidth / 2

            // 左辺と上辺の幾何長
            let vLen = h - half          // 左辺の長さ(下端→角)
            let hLen = w - half          // 上辺の長さ(角→右端)
            // trim を速度比に合わせるため、描画上の辺長を比率調整する係数
            // (左辺が全速度の cornerFraction を担当するようパスの点を配置)

            ZStack {
                LShape(half: half)
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))

                LShape(half: half)
                    .trim(from: 0, to: trimEnd(vLen: vLen, hLen: hLen))
                    .stroke(accent,
                            style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                    .animation(.easeOut(duration: 0.3), value: progress)

                ForEach(ticks, id: \.self) { tick in
                    let pos = labelPosition(for: tick, w: w, h: h, half: half)
                    Text("\(tick)")
                        .font(.system(size: lineWidth * 0.40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Double(tick) <= speedKMH ? .black.opacity(0.75) : .gray.opacity(0.7))
                        .position(pos)
                }
            }
        }
    }

    /// 速度progressを、左辺/上辺の実長比に変換したtrim終端値に直す。
    /// 左辺は速度0..cornerFraction を担当、その実長比は vLen/(vLen+hLen)。
    private func trimEnd(vLen: CGFloat, hLen: CGFloat) -> CGFloat {
        let total = vLen + hLen
        let vShare = Double(vLen / total)   // 左辺がパス全長に占める比
        if progress <= cornerFraction {
            let t = progress / cornerFraction          // 左辺内 0..1
            return CGFloat(t * vShare)
        } else {
            let t = (progress - cornerFraction) / (1 - cornerFraction)  // 上辺内 0..1
            return CGFloat(vShare + t * (1 - vShare))
        }
    }

    private func labelPosition(for tick: Int, w: CGFloat, h: CGFloat, half: CGFloat) -> CGPoint {
        let frac = Double(tick) / maxKMH
        if frac <= cornerFraction {
            let t = frac / cornerFraction
            let y = h - (h - half) * CGFloat(t)
            return CGPoint(x: half, y: min(max(y, half), h - half))
        } else {
            let t = (frac - cornerFraction) / (1 - cornerFraction)
            let x = half + (w - half) * CGFloat(t)
            return CGPoint(x: min(max(x, half), w - half), y: half)
        }
    }
}

/// 逆L字パス: 下端(左)→上(角)→右端。trimはこの順で進む。
private struct LShape: Shape {
    let half: CGFloat
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: half, y: rect.maxY))
            p.addLine(to: CGPoint(x: half, y: half))
            p.addLine(to: CGPoint(x: rect.maxX, y: half))
        }
    }
}
