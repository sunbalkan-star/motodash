import SwiftUI

/// 参考モニター風の速度ゲージ。
/// 形状: 左下から45°斜めで立ち上がり(〜40km/h)→ 縦辺を上へ →
///       左上角 → 上辺を右端まで水平。現在速度まで塗りが伸びる。
struct SpeedGauge: View {
    let speedKMH: Double
    let maxKMH: Double
    let accent: Color

    /// 斜め区間の上端に対応する速度(画像では斜めが20〜40)
    private let bevelEndSpeed: Double = 40

    private let ticks: [Int] = [20, 40, 60, 80, 100, 120]

    private var progress: Double { min(max(speedKMH / maxKMH, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineWidth = min(w, h) * 0.16
            let pts = vertices(w: w, h: h, lineWidth: lineWidth)
            let segs = segmentLengths(pts)

            ZStack {
                GaugePath(points: pts)
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                GaugePath(points: pts)
                    .trim(from: 0, to: trimEnd(segs: segs))
                    .stroke(accent,
                            style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                    .animation(.easeOut(duration: 0.3), value: progress)

                ForEach(ticks, id: \.self) { tick in
                    Text("\(tick)")
                        .font(.system(size: lineWidth * 0.38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(Double(tick) <= speedKMH ? .black.opacity(0.75) : .gray.opacity(0.7))
                        .position(labelPosition(for: tick, pts: pts, segs: segs))
                }
            }
        }
    }

    // 4頂点: [斜め下端, 斜め上端, 左上角, 右端]
    private func vertices(w: CGFloat, h: CGFloat, lineWidth: CGFloat) -> [CGPoint] {
        let half = lineWidth / 2
        let bevel = min(w, h) * 0.16
        return [
            CGPoint(x: half, y: h - half),                 // 0 斜め下端
            CGPoint(x: half + bevel, y: h - half - bevel), // 1 斜め上端
            CGPoint(x: half + bevel, y: half),             // 2 左上角
            CGPoint(x: w - half, y: half)                  // 3 右端
        ]
    }

    // 各区間長 [斜め, 縦, 横]
    private func segmentLengths(_ p: [CGPoint]) -> [CGFloat] {
        [
            hypot(p[1].x - p[0].x, p[1].y - p[0].y),
            hypot(p[2].x - p[1].x, p[2].y - p[1].y),
            hypot(p[3].x - p[2].x, p[3].y - p[2].y)
        ]
    }

    /// 速度を担当区間に割り当て、パス全長比(trim終端)に変換
    private func trimEnd(segs: [CGFloat]) -> CGFloat {
        let total = segs.reduce(0, +)
        guard total > 0 else { return 0 }
        let sBevel = segs[0] / total
        let sVert = segs[1] / total

        // 速度の区間境界: 斜め=0..40、残り(40..120)を縦長:横長で按分
        let vertHorizSplit = Double(segs[1] / (segs[1] + segs[2]))
        let vertEndSpeed = bevelEndSpeed + (maxKMH - bevelEndSpeed) * vertHorizSplit

        if speedKMH <= bevelEndSpeed {
            let t = speedKMH / bevelEndSpeed
            return CGFloat(t) * sBevel
        } else if speedKMH <= vertEndSpeed {
            let t = (speedKMH - bevelEndSpeed) / (vertEndSpeed - bevelEndSpeed)
            return sBevel + CGFloat(t) * sVert
        } else {
            let t = (speedKMH - vertEndSpeed) / (maxKMH - vertEndSpeed)
            return sBevel + sVert + CGFloat(min(t, 1)) * (1 - sBevel - sVert)
        }
    }

    private func labelPosition(for tick: Int, pts: [CGPoint], segs: [CGFloat]) -> CGPoint {
        let v = Double(tick)
        let vertHorizSplit = Double(segs[1] / (segs[1] + segs[2]))
        let vertEndSpeed = bevelEndSpeed + (maxKMH - bevelEndSpeed) * vertHorizSplit

        if v <= bevelEndSpeed {
            let t = v / bevelEndSpeed
            return lerp(pts[0], pts[1], CGFloat(t))
        } else if v <= vertEndSpeed {
            let t = (v - bevelEndSpeed) / (vertEndSpeed - bevelEndSpeed)
            return lerp(pts[1], pts[2], CGFloat(t))
        } else {
            let t = (v - vertEndSpeed) / (maxKMH - vertEndSpeed)
            return lerp(pts[2], pts[3], CGFloat(t))
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

/// 斜め→縦→横の折れ線パス。trimはこの順で進む。
private struct GaugePath: Shape {
    var points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        Path { p in
            guard points.count == 4 else { return }
            p.move(to: points[0])
            p.addLine(to: points[1])
            p.addLine(to: points[2])
            p.addLine(to: points[3])
        }
    }
}
