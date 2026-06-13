import SwiftUI

/// 参考モニター風の速度ゲージ。
/// 形状: 下から垂直に立ち上がり(0〜20km/h)→ 右斜め45°(20〜40)→
///       上辺を右端まで水平(40〜120)。現在速度まで塗りが伸びる。
struct SpeedGauge: View {
    let speedKMH: Double
    let maxKMH: Double
    let accent: Color

    /// 区間境界の速度
    private let vertEndSpeed: Double = 20    // 垂直区間の上端
    private let bevelEndSpeed: Double = 40   // 斜め区間の上端=水平の開始

    private let ticks: [Int] = [20, 40, 60, 80, 100, 120]

    private var progress: Double { min(max(speedKMH / maxKMH, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lineWidth = min(w, h) * 0.24   // 太さ(従来比+50%)
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

    // 4頂点: [垂直下端, 垂直上端(斜め下端), 斜め上端(水平左端), 水平右端]
    private func vertices(w: CGFloat, h: CGFloat, lineWidth: CGFloat) -> [CGPoint] {
        let half = lineWidth / 2
        let bevel = min(w, h) * 0.22          // 斜めの振り幅(太さに合わせ拡大)
        let vBottom = CGPoint(x: half, y: h - half)        // 0 垂直下端
        let vTop = CGPoint(x: half, y: half + bevel)       // 1 垂直上端=斜め下端
        let hLeft = CGPoint(x: half + bevel, y: half)      // 2 斜め上端=水平左端
        let hRight = CGPoint(x: w - half, y: half)         // 3 水平右端
        return [vBottom, vTop, hLeft, hRight]
    }

    // 各区間長 [垂直, 斜め, 水平]
    private func segmentLengths(_ p: [CGPoint]) -> [CGFloat] {
        [
            hypot(p[1].x - p[0].x, p[1].y - p[0].y),
            hypot(p[2].x - p[1].x, p[2].y - p[1].y),
            hypot(p[3].x - p[2].x, p[3].y - p[2].y)
        ]
    }

    /// 速度をパス全長比(trim終端)に変換
    private func trimEnd(segs: [CGFloat]) -> CGFloat {
        let total = segs.reduce(0, +)
        guard total > 0 else { return 0 }
        let sVert = segs[0] / total
        let sBevel = segs[1] / total

        if speedKMH <= vertEndSpeed {
            let t = speedKMH / vertEndSpeed
            return CGFloat(t) * sVert
        } else if speedKMH <= bevelEndSpeed {
            let t = (speedKMH - vertEndSpeed) / (bevelEndSpeed - vertEndSpeed)
            return sVert + CGFloat(t) * sBevel
        } else {
            let t = (speedKMH - bevelEndSpeed) / (maxKMH - bevelEndSpeed)
            return sVert + sBevel + CGFloat(min(t, 1)) * (1 - sVert - sBevel)
        }
    }

    private func labelPosition(for tick: Int, pts: [CGPoint], segs: [CGFloat]) -> CGPoint {
        let v = Double(tick)
        if v <= vertEndSpeed {
            let t = v / vertEndSpeed
            return lerp(pts[0], pts[1], CGFloat(t))
        } else if v <= bevelEndSpeed {
            let t = (v - vertEndSpeed) / (bevelEndSpeed - vertEndSpeed)
            return lerp(pts[1], pts[2], CGFloat(t))
        } else {
            // 水平区間。右端(120)はゲージ内に収めるため少し内側に寄せる
            let t = (v - bevelEndSpeed) / (maxKMH - bevelEndSpeed)
            let pos = lerp(pts[2], pts[3], CGFloat(t))
            if tick == Int(maxKMH) {
                return CGPoint(x: pos.x - (segs[2] * 0.04), y: pos.y)
            }
            return pos
        }
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

/// 垂直→斜め→水平の折れ線パス。trimはこの順で進む。
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
