import SwiftUI

/// MotoDash ダッシュボード(デザインハンドオフ hifi 準拠)。
/// 横画面=主画面(ハンドルマウント) / 縦画面=従画面。
/// 表示データは RideManager(GPS/高度/方位/電池) と TPMSManager(空気圧)から。
struct DashboardView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @State private var showSniffer = false

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height >= geo.size.width
            Group {
                if isPortrait { portraitLayout } else { landscapeLayout }
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .sheet(isPresented: $showSniffer) {
            SnifferView().environmentObject(tpms)
        }
    }

    // MARK: - 横レイアウト(主画面)

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            statusBar(time: timeTrailing(isPortrait: false), compassSize: 20, timeSize: 24)
                .padding(EdgeInsets(top: 11, leading: 46, bottom: 6, trailing: 18))

            GaugeBar(speedKMH: ride.speedKMH, maxSpeedKMH: ride.maxSpeedKMH,
                     barHeight: 60, minorTickHeight: 26, labelSize: 15, showMaxPill: true)
                .padding(.top, 2)
                .padding(.leading, 46)
                .padding(.trailing, 18)

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 26) {
                    // ヒーロー速度(右揃え・下揃え)
                    HStack(alignment: .bottom, spacing: 12) {
                        Text("\(Int(ride.speedKMH.rounded()))")
                            .font(motoNumberFont(132, .heavy))
                            .tracking(-4)
                            .foregroundColor(Palette.textHi)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("km/h")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Palette.lime)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    // TPMS(下揃え・固定幅198)
                    HStack(spacing: 12) {
                        tpmsCard("FRONT", bar: frontBar, valueSize: 46).frame(width: 198)
                        tpmsCard("REAR", bar: rearBar, valueSize: 46).frame(width: 198)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)

                // 下辺ストリップ: BATTERY, ALTITUDE, TIME, TRIP, TOTAL
                HStack(spacing: 9) {
                    dataCard("BATTERY", value: "\(ride.phoneBatteryPercent)", unit: "%",
                             valueColor: StateColor.battery(ride.phoneBatteryPercent),
                             valueSize: 26, labelSize: 11, corner: 12)
                    dataCard("ALTITUDE", value: "\(Int(ride.altitudeM))", unit: "m",
                             valueSize: 26, labelSize: 11, corner: 12)
                    dataCard("TIME", value: durationString(ride.ridingSeconds), unit: "",
                             valueSize: 26, labelSize: 11, corner: 12)
                    dataCard("TRIP", value: String(format: "%.1f", ride.tripMeters / 1000), unit: "km",
                             valueSize: 26, labelSize: 11, corner: 12)
                        .onLongPressGesture { ride.resetTrip() }
                    dataCard("TOTAL", value: String(format: "%.0f", ride.totalMeters / 1000), unit: "km",
                             valueSize: 26, labelSize: 11, corner: 12)
                }
                .padding(.top, 12)
                .padding(.bottom, 7)
            }
            .frame(maxHeight: .infinity)
            .padding(.leading, 46)
            .padding(.trailing, 18)
            .padding(.bottom, 14)
        }
    }

    // MARK: - 縦レイアウト(従画面)

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            statusBar(time: timeTrailing(isPortrait: true), compassSize: 17, timeSize: 19)
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 8, trailing: 18))

            GaugeBar(speedKMH: ride.speedKMH, maxSpeedKMH: ride.maxSpeedKMH,
                     barHeight: 56, minorTickHeight: 24, labelSize: 13, showMaxPill: false)
                .padding(.top, 6)
                .padding(.horizontal, 20)

            // ヒーロー速度(中央)
            VStack(spacing: 8) {
                Text("\(Int(ride.speedKMH.rounded()))")
                    .font(motoNumberFont(188, .heavy))
                    .tracking(-7)
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("km/h")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.lime)
            }
            .padding(.top, 18)
            .padding(.bottom, 8)

            // TPMS(等幅横並び)
            HStack(spacing: 11) {
                tpmsCard("FRONT", bar: frontBar, valueSize: 42)
                tpmsCard("REAR", bar: rearBar, valueSize: 42)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // データカード 2列グリッド(TOTALは2列ぶち抜き)
            Grid(horizontalSpacing: 11, verticalSpacing: 11) {
                GridRow {
                    dataCard("TRIP", value: String(format: "%.1f", ride.tripMeters / 1000), unit: "km",
                             valueSize: 32, labelSize: 12, corner: 14)
                        .onLongPressGesture { ride.resetTrip() }
                    dataCard("TIME", value: durationString(ride.ridingSeconds), unit: "",
                             valueSize: 32, labelSize: 12, corner: 14)
                }
                GridRow {
                    dataCard("ALTITUDE", value: "\(Int(ride.altitudeM))", unit: "m",
                             valueSize: 32, labelSize: 12, corner: 14)
                    dataCard("BATTERY", value: "\(ride.phoneBatteryPercent)", unit: "%",
                             valueColor: StateColor.battery(ride.phoneBatteryPercent),
                             valueSize: 32, labelSize: 12, corner: 14)
                }
                GridRow {
                    dataCard("TOTAL", value: String(format: "%.0f", ride.totalMeters / 1000), unit: "km",
                             valueSize: 32, labelSize: 12, corner: 14)
                        .gridCellColumns(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 11)

            Spacer(minLength: 0)
        }
    }

    // MARK: - ステータスバー

    private func statusBar(time: String, compassSize: CGFloat, timeSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            // 戻る(ホームへ)
            Button(action: goHome) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textHi)
                    .frame(width: 46, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Palette.button))
            }
            .buttonStyle(.plain)

            // 現在速度ピル
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(ride.speedKMH.rounded()))")
                    .font(motoNumberFont(18, .bold))
                    .foregroundColor(Palette.textHi)
                Text("Km/h")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textMid)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.borderStrong, lineWidth: 1.5))

            // コンパス(中央)
            HStack(spacing: 9) {
                CompassArrow()
                    .fill(Palette.cyan)
                    .frame(width: compassSize, height: compassSize)
                    .rotationEffect(.degrees(ride.headingDegrees))
                Text(headingText)
                    .font(.system(size: compassSize == 20 ? 20 : 16, weight: .semibold))
                    .tracking(1)
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            // 日時 / 時刻
            Text(time)
                .font(motoNumberFont(timeSize, .bold))
                .foregroundColor(Palette.textHi)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: - TPMSカード

    private func tpmsCard(_ title: String, bar: Double?, valueSize: CGFloat) -> some View {
        let valueText = bar.map { String(format: "%.1f", $0) } ?? "-.--"
        let assigned = (title == "FRONT") ? tpms.assignments[.front] != nil
                                          : tpms.assignments[.rear] != nil
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                TireIcon()
                Text(title)
                    .font(motoLabelFont(13))
                    .tracking(1.5)
                    .foregroundColor(Palette.label)
                if !assigned {
                    Text("未割当")
                        .font(.system(size: 10))
                        .foregroundColor(Palette.amber)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(valueText)
                    .font(motoNumberFont(valueSize, .bold))
                    .foregroundColor(StateColor.pressure(bar))
                Text("bar")
                    .font(.system(size: 14))
                    .foregroundColor(Palette.textMid)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 16, bottom: 13, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.borderStrong, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { showSniffer = true }
    }

    // MARK: - データカード

    private func dataCard(_ label: String, value: String, unit: String,
                          valueColor: Color = Palette.textHi,
                          valueSize: CGFloat, labelSize: CGFloat, corner: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(motoLabelFont(labelSize))
                .tracking(1.5)
                .foregroundColor(Palette.label)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(motoNumberFont(valueSize, .bold))
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: labelSize + 1))
                        .foregroundColor(Palette.textMid)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: corner).stroke(Palette.borderWeak, lineWidth: 1.5))
    }

    // MARK: - データ派生

    private var frontBar: Double? {
        guard let r = tpms.readings[.front], !r.isStale else { return nil }
        return r.pressureBar
    }
    private var rearBar: Double? {
        guard let r = tpms.readings[.rear], !r.isStale else { return nil }
        return r.pressureBar
    }

    private var headingText: String {
        let deg = Int(ride.headingDegrees.rounded())
        return "\(deg)° \(cardinal(ride.headingDegrees))"
    }

    private func cardinal(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((deg / 45).rounded()) % 8
        return dirs[(idx % 8 + 8) % 8]
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)h \(m)m"
    }

    /// 右端の日時(横=YYYY/M/D H:mm) / 時刻(縦=HH:MM)。分単位更新で十分なので呼び出しごとに現在時刻。
    private func timeTrailing(isPortrait: Bool) -> String {
        let now = Date()
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        if isPortrait {
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        } else {
            let mm = String(format: "%02d", c.minute ?? 0)
            return "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0) \(c.hour ?? 0):\(mm)"
        }
    }

    /// ホーム画面へ戻す(サイドロード個人アプリ向け。公開APIではない点に留意)
    private func goHome() {
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            UIApplication.shared.perform(selector)
        }
    }
}

// MARK: - 小物

/// コンパス矢印(ハンドオフ SVG: M12 2 L17 21 L12 16 L7 21 Z を 24×24 から相似変換)
struct CompassArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        var path = Path()
        path.move(to: p(12, 2))
        path.addLine(to: p(17, 21))
        path.addLine(to: p(12, 16))
        path.addLine(to: p(7, 21))
        path.closeSubpath()
        return path
    }
}

/// TPMSタイヤアイコン(二重円, stroke ライム)
struct TireIcon: View {
    var body: some View {
        ZStack {
            Circle().stroke(Palette.lime, lineWidth: 1.6).frame(width: 14, height: 14)
            Circle().fill(Palette.lime).frame(width: 3.6, height: 3.6)
        }
        .frame(width: 18, height: 18)
    }
}
