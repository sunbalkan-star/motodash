import SwiftUI

/// 参考スマートモニター準拠の速度ゲージ。
/// 形状: 左を垂直に立ち上がり → 円弧で滑らかに曲がり → 上辺を右端まで水平。
/// 最大160km/h。現在速度まで緑の塗りが伸び、目盛り刻みを重ねる。
struct SpeedGauge: View {
    let speedKMH: Double
    let maxKMH: Double           // 160
    let accent: Color

    /// 垂直区間が担当する速度(角=この速度)。画像では垂直に20,40があるので40。
    private let cornerSpeed: Double = 40

    /// ラベルを振る速度(大刻み)
    private let majorTicks: [Int] = [20, 40, 80, 120, 160]
    /// 小刻み(10km/h刻み、majorと重複しない値)
    private let minorTicks: [Int] = [10, 30, 50, 60, 70, 90, 100, 110, 130, 140, 150]

    private var progress: Double { min(max(speedKMH / maxKMH, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineWidth = min(w, h) * 0.20
            let g = Geo(w: w, h: h, lineWidth: lineWidth, cornerSpeed: cornerSpeed, maxKMH: maxKMH)

            ZStack {
                // 背景トラック
                g.path()
                    .stroke(Color.white.opacity(0.10),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round))

                // 緑の塗り(現在速度まで)
                g.path()
                    .trim(from: 0, to: g.trimEnd(forSpeed: speedKMH))
                    .stroke(accent,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, lineJoin: .round))
                    .animation(.easeOut(duration: 0.3), value: progress)

                // 小刻み(細い・薄い)
                ForEach(minorTicks, id: \.self) { v in
                    tickShape(g: g, speed: Double(v),
                              thickness: 1.5,
                              lengthRatio: 0.72,
                              color: .black.opacity(0.30))
                }
                // 大刻み(太い・濃い)
                ForEach(majorTicks, id: \.self) { v in
                    tickShape(g: g, speed: Double(v),
                              thickness: 3,
                              lengthRatio: 0.92,
                              color: .black.opacity(0.55))
                }

                // ラベル(L字の内側=hollow側に外出し)
                ForEach(majorTicks, id: \.self) { v in
                    let pt = g.labelPlacement(forSpeed: Double(v))
                    Text("\(v)")
                        .font(.system(size: lineWidth * 0.42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Double(v) <= speedKMH ? .white : .gray.opacity(0.85))
                        .position(pt)
                }
            }
        }
    }

    @ViewBuilder
    private func tickShape(g: Geo, speed: Double, thickness: CGFloat,
                           lengthRatio: CGFloat, color: Color) -> some View {
        let (pt, isVertical) = g.tickPlacement(forSpeed: speed)
        let long = g.lineWidth * lengthRatio
        Rectangle()
            .fill(color)
            .frame(width: isVertical ? long : thickness,
                   height: isVertical ? thickness : long)
            .position(pt)
    }
}

/// ゲージの幾何計算をまとめた補助構造。
/// 区間: [垂直: 0..cornerSpeed] → [円弧: 角の視覚的丸み] → [水平: cornerSpeed..max]
private struct Geo {
    let w: CGFloat, h: CGFloat, lineWidth: CGFloat
    let cornerSpeed: Double, maxKMH: Double
    let half: CGFloat
    let radius: CGFloat
    let vBottom: CGPoint    // 垂直下端
    let arcStart: CGPoint   // 垂直上端(円弧開始)
    let arcCenter: CGPoint
    let hStart: CGPoint     // 水平開始(円弧終了)
    let hEnd: CGPoint       // 水平右端
    let vertLen: CGFloat
    let arcLen: CGFloat
    let horizLen: CGFloat

    init(w: CGFloat, h: CGFloat, lineWidth: CGFloat, cornerSpeed: Double, maxKMH: Double) {
        self.w = w; self.h = h; self.lineWidth = lineWidth
        self.cornerSpeed = cornerSpeed; self.maxKMH = maxKMH
        let half = lineWidth / 2
        self.half = half
        let r = lineWidth * 1.1
        self.radius = r
        self.vBottom = CGPoint(x: half, y: h - half)
        self.arcStart = CGPoint(x: half, y: half + r)
        self.arcCenter = CGPoint(x: half + r, y: half + r)
        self.hStart = CGPoint(x: half + r, y: half)
        self.hEnd = CGPoint(x: w - half, y: half)
        self.vertLen = (h - half) - (half + r)
        self.arcLen = .pi / 2 * r
        self.horizLen = (w - half) - (half + r)
    }

    var total: CGFloat { vertLen + arcLen + horizLen }

    func path() -> Path {
        Path { p in
            p.move(to: vBottom)
            p.addLine(to: arcStart)
            // 円弧: 180°→270°(左下から上へ滑らかに)
            p.addArc(center: arcCenter, radius: radius,
                     startAngle: .degrees(180), endAngle: .degrees(270),
                     clockwise: false)
            p.addLine(to: hEnd)
        }
    }

    /// 速度→trim終端(パス全長比)
    func trimEnd(forSpeed s: Double) -> CGFloat {
        guard total > 0 else { return 0 }
        let sVert = vertLen / total
        let sArc = arcLen / total
        if s <= cornerSpeed {
            let t = s / cornerSpeed
            return CGFloat(t) * sVert
        } else {
            // 角を越えたら円弧分を即埋め、残りを水平へ
            let t = (s - cornerSpeed) / (maxKMH - cornerSpeed)
            return sVert + sArc + CGFloat(min(t, 1)) * (horizLen / total)
        }
    }

    /// 刻みの中心座標と、その刻みが垂直区間にあるか(=横棒で描くか)
    func tickPlacement(forSpeed s: Double) -> (CGPoint, Bool) {
        if s <= cornerSpeed {
            let t = s / cornerSpeed
            let y = vBottom.y - (vBottom.y - arcStart.y) * CGFloat(t)
            return (CGPoint(x: half, y: y), true)   // 垂直区間 → 横棒
        } else {
            let t = (s - cornerSpeed) / (maxKMH - cornerSpeed)
            let x = hStart.x + (hEnd.x - hStart.x) * CGFloat(t)
            return (CGPoint(x: x, y: half), false)  // 水平区間 → 縦棒
        }
    }

    /// ラベル座標(L字の内側=hollow側へバーの外に外出し)
    func labelPlacement(forSpeed s: Double) -> CGPoint {
        let gap = lineWidth * 0.55   // バーから離す量(数字がバーに乗らないように)
        if s <= cornerSpeed {
            let t = s / cornerSpeed
            let y = vBottom.y - (vBottom.y - arcStart.y) * CGFloat(t)
            return CGPoint(x: lineWidth + gap, y: y)   // 垂直 → 右側(hollow)
        } else {
            let t = (s - cornerSpeed) / (maxKMH - cornerSpeed)
            let x = hStart.x + (hEnd.x - hStart.x) * CGFloat(t)
            return CGPoint(x: x, y: lineWidth + gap)   // 水平 → 下側(hollow)
        }
    }
}
