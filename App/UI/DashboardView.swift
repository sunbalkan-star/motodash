import SwiftUI

/// MotoDash ダッシュボード(Claude Design 2026-10-08 版 MotoDash.dc.html 準拠)。
/// 横画面=主画面(ハンドルマウント) / 縦画面=従画面。
/// 表示データは RideManager(GPS/高度/方位/電池) と TPMSManager(空気圧・温度)から。
struct DashboardView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @State private var showSniffer = false
    @State private var showRideLog = false
    /// TRIP カードの表示切替(タップで A/B)。次回起動時も維持
    @AppStorage("dashboard.showTripB") private var showTripB = false
    /// 時計・TPMS 期限切れ表示を GPS 更新に依存せず進める
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height >= geo.size.width
            Group {
                if isPortrait {
                    portraitLayout
                } else {
                    // 横画面はセーフエリアを無視し、余白を画面端から測る(ノッチ側 46pt / 反対側 18pt)。
                    // ノッチが左右どちらにあるかは端末の向きで変わるため、インセットの大きい側をノッチ側とみなす
                    let notchOnLeading = geo.safeAreaInsets.leading >= geo.safeAreaInsets.trailing
                    landscapeLayout(leading: notchOnLeading ? 46 : 18,
                                    trailing: notchOnLeading ? 18 : 46)
                        .ignoresSafeArea()
                        .persistentSystemOverlays(.hidden)   // ホームインジケータを自動で隠す
                }
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .sheet(isPresented: $showSniffer) {
            SnifferView()
                .environmentObject(tpms)
                .environmentObject(tpms.sniffer)
        }
        .sheet(isPresented: $showRideLog) {
            RideLogView().environmentObject(ride)
        }
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - 横レイアウト(主画面)

    /// 縦方向の内訳(812×375 キャンバス):
    ///   上 8 + ステータスバー 36 + 間 8 + ゲージ行 46(バー30 + 4 + 目盛12)
    ///   + 中段 165(TPMS 80 + 5 + 80。速度 110pt 行高≒131 は下詰め、残り 34 は上に空く)
    ///   + ストリップ 112(上22 + 80 + 下10) = 375pt。
    /// 横方向: ノッチ側 46 + コンテンツ 748 + 反対側 18。中段 = 速度エリア(可変 ≒534) + 16 + TPMS 198。
    /// セーフエリアは無視する(画面全体 = キャンバス)。
    private func landscapeLayout(leading: CGFloat, trailing: CGFloat) -> some View {
        VStack(spacing: 0) {
            statusBar(.landscape)
            Spacer().frame(height: 8)

            gaugeRow(.landscape)

            // 中段: ヒーロー速度(右揃え・下詰め) + TPMS 縦2枚
            HStack(alignment: .bottom, spacing: 16) {
                HStack(alignment: .bottom, spacing: 10) {
                    Text(speedText)
                        .font(motoNumberFont(110, .heavy))
                        .foregroundColor(speedColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    unitLabel("KM/H", size: 12, color: Palette.textMid)
                        .padding(.bottom, 26)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                VStack(spacing: 5) {
                    tpmsCard("FRONT", bar: frontBar, temp: frontTemp,
                             assigned: tpms.assignments[.front] != nil, metrics: .landscape)
                    tpmsCard("REAR", bar: rearBar, temp: rearTemp,
                             assigned: tpms.assignments[.rear] != nil, metrics: .landscape)
                }
                .frame(width: 198)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)

            // 下辺ストリップ(h80・5枚均等 ≒143pt): BATTERY, ALTITUDE, TIME, TRIP, TOTAL
            HStack(spacing: 8) {
                dataCards(.landscape)
            }
            .frame(height: 80)
            .padding(.top, 22)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .padding(.leading, leading)
        .padding(.trailing, trailing)
    }

    // MARK: - 縦レイアウト(従画面)

    /// 縦方向の内訳(セーフエリア内。iPhone X で有効 734pt):
    ///   上 4 + ステータスバー 36 + 間 8 + ゲージ行 44(バー28 + 4 + 目盛12)
    ///   + 速度 188pt 行高≒224 + KM/H 16 + カードエリア 307(TPMS 70 + 9 + 右列 70×3 + 9×2)
    ///   = 639pt。残り ≒95pt を速度の上下 Spacer が等分する。左列 149 は右列 228 に下端揃え。
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            statusBar(.portrait)
            Spacer().frame(height: 8)

            gaugeRow(.portrait)

            Spacer(minLength: 0)
            Text(speedText)
                .font(motoNumberFont(188, .heavy))
                .tracking(-7)   // 3桁で幅 335pt に収めるため(SF Pro は Saira より字幅が広い)
                .foregroundColor(speedColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
            unitLabel("KM/H", size: 12, color: Palette.textMid)
                .frame(height: 16)
            Spacer(minLength: 0)

            // カードエリア: FRONT|REAR 横並び + 下2列(左=BATTERY/ALTITUDE, 右=TIME/TRIP/TOTAL 下揃え)
            VStack(spacing: 9) {
                HStack(spacing: 9) {
                    tpmsCard("FRONT", bar: frontBar, temp: frontTemp,
                             assigned: tpms.assignments[.front] != nil, metrics: .portrait)
                    tpmsCard("REAR", bar: rearBar, temp: rearTemp,
                             assigned: tpms.assignments[.rear] != nil, metrics: .portrait)
                }
                HStack(alignment: .bottom, spacing: 9) {
                    VStack(spacing: 9) {
                        batteryCard(.portrait)
                        altitudeCard(.portrait)
                    }
                    VStack(spacing: 9) {
                        timeCard(.portrait)
                        tripCard(.portrait)
                        totalCard(.portrait)
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 20)
    }

    // MARK: - 向き別の寸法

    private enum Metrics {
        case landscape, portrait

        var isLandscape: Bool { self == .landscape }
        // ステータスバー
        var leftGap: CGFloat { isLandscape ? 8 : 6 }
        var pillHeight: CGFloat { isLandscape ? 26 : 24 }
        var pillPadding: CGFloat { isLandscape ? 10 : 8 }
        var pillText: CGFloat { isLandscape ? 10 : 9 }
        var pillGap: CGFloat { isLandscape ? 6 : 5 }
        var dirSize: CGFloat { isLandscape ? 22 : 20 }
        var degSize: CGFloat { isLandscape ? 16 : 14 }
        var compassGap: CGFloat { isLandscape ? 6 : 4 }
        var timeSize: CGFloat { isLandscape ? 18 : 17 }
        // ゲージ
        var barHeight: CGFloat { isLandscape ? 30 : 28 }
        var barCorner: CGFloat { isLandscape ? 8 : 7 }
        var gaugeGap: CGFloat { isLandscape ? 10 : 8 }
        var maxPadding: CGFloat { isLandscape ? 10 : 8 }
        var maxValueSize: CGFloat { isLandscape ? 16 : 15 }
        var maxGap: CGFloat { isLandscape ? 6 : 5 }
        // TPMS カード
        var tpmsHeight: CGFloat { isLandscape ? 80 : 70 }
        var tpmsPadding: CGFloat { isLandscape ? 14 : 12 }
        var tireSize: CGFloat { isLandscape ? 14 : 13 }
        var tireDot: CGFloat { isLandscape ? 4 : 3 }
        var tpmsHeadGap: CGFloat { isLandscape ? 7 : 6 }
        var pressureSize: CGFloat { isLandscape ? 38 : 32 }
        var pressureLine: CGFloat { isLandscape ? 45 : 38 }
        var barUnitSize: CGFloat { isLandscape ? 11 : 10 }
        var tempSize: CGFloat { isLandscape ? 18 : 16 }
        var valueGap: CGFloat { isLandscape ? 6 : 5 }
        // データカード
        var cardHeight: CGFloat { isLandscape ? 80 : 70 }
    }

    // MARK: - ステータスバー(h36: 左=戻る+GPS / 中央=方位 / 右=日時)

    private func statusBar(_ m: Metrics) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: m.leftGap) {
                // 戻る(ホームへ)
                Button(action: goHome) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Palette.textHi)
                        .frame(width: 44, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.button))
                }
                .buttonStyle(.plain)

                gpsPill(m)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 方位(中央): "NE 042°" シアン
            HStack(alignment: .firstTextBaseline, spacing: m.compassGap) {
                Text(cardinal(ride.headingDegrees))
                    .font(motoNumberFont(m.dirSize, .heavy))
                Text(String(format: "%03d°", Int(ride.headingDegrees.rounded()) % 360))
                    .font(motoNumberFont(m.degSize, .bold))
            }
            .foregroundColor(Palette.cyan)
            .lineLimit(1)
            .fixedSize()

            // 日時(右): 横 = "10/08 THU" + "HH:MM" / 縦 = "HH:MM"
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if m.isLandscape {
                    Text(Self.dateFormatter.string(from: now).uppercased())
                        .font(motoLabelFont(11, .semibold))
                        .tracking(1.5)
                        .foregroundColor(Palette.label)
                }
                Text(Self.clockFormatter.string(from: now))
                    .font(motoNumberFont(m.timeSize, .bold))
                    .foregroundColor(Palette.textHi)
            }
            .lineLimit(1)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 36)
    }

    /// GPS 状態ピル(受信中=ライム "GPS" / ロスト=アンバー "GPS LOST")
    private func gpsPill(_ m: Metrics) -> some View {
        let color = ride.hasGPSFix ? Palette.lime : Palette.amber
        return HStack(spacing: m.pillGap) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(ride.hasGPSFix ? "GPS" : "GPS LOST")
                .font(motoLabelFont(m.pillText, .semibold))
                .tracking(1.5)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, m.pillPadding)
        .frame(height: m.pillHeight)
        .overlay(Capsule().stroke(color, lineWidth: 1))
        .fixedSize()
    }

    // MARK: - ゲージ行(バー + 目盛 | MAX ボックス)

    private func gaugeRow(_ m: Metrics) -> some View {
        HStack(alignment: .top, spacing: m.gaugeGap) {
            GaugeBar(speedKMH: ride.hasGPSFix ? ride.speedKMH : 0,
                     barHeight: m.barHeight, cornerRadius: m.barCorner)

            // MAX(長押しでリセット)
            HStack(spacing: m.maxGap) {
                unitLabel("MAX", size: 9, color: Palette.label)
                Text("\(Int(ride.maxSpeedKMH.rounded()))")
                    .font(motoNumberFont(m.maxValueSize, .bold))
                    .foregroundColor(Palette.textHi)
            }
            .padding(.horizontal, m.maxPadding)
            .frame(height: m.barHeight)
            .overlay(RoundedRectangle(cornerRadius: m.barCorner).stroke(Palette.borderStrong, lineWidth: 1))
            .fixedSize()
            .contentShape(Rectangle())
            .onLongPressGesture { ride.resetMaxSpeed() }
        }
        .frame(height: m.barHeight + 4 + 12)
    }

    // MARK: - TPMS カード(左揃え・上下中央: 見出し行 + 値行)

    private func tpmsCard(_ title: String, bar: Double?, temp: Double?, assigned: Bool,
                          metrics m: Metrics) -> some View {
        let valueText = bar.map { String(format: "%.1f", $0) } ?? "-.--"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: m.tpmsHeadGap) {
                TireIcon(size: m.tireSize, dot: m.tireDot)
                unitLabel(title, size: 10, color: Palette.label)
                if !assigned {
                    Text("未割当")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Palette.amber)
                }
            }
            .frame(height: m.tireSize)

            HStack(alignment: .firstTextBaseline, spacing: m.valueGap) {
                Text(valueText)
                    .font(motoNumberFont(m.pressureSize, .heavy))
                    .foregroundColor(StateColor.pressure(bar))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                unitLabel("BAR", size: m.barUnitSize, color: Palette.label)
                Text(tempText(temp))
                    .font(motoNumberFont(m.tempSize, .bold))
                    .foregroundColor(Palette.textMid)
                    .lineLimit(1)
            }
            .frame(height: m.pressureLine)
        }
        .padding(.horizontal, m.tpmsPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: m.tpmsHeight)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.borderStrong, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { showSniffer = true }
    }

    // MARK: - データカード(左揃え・上下中央: ラベル 10pt + 値 30pt + 単位 11pt)

    @ViewBuilder
    private func dataCards(_ m: Metrics) -> some View {
        batteryCard(m)
        altitudeCard(m)
        timeCard(m)
        tripCard(m)
        totalCard(m)
    }

    private func batteryCard(_ m: Metrics) -> some View {
        dataCard("BATTERY", value: "\(ride.phoneBatteryPercent)", unit: "%",
                 valueColor: StateColor.battery(ride.phoneBatteryPercent), metrics: m)
    }

    private func altitudeCard(_ m: Metrics) -> some View {
        dataCard("ALTITUDE", value: "\(Int(ride.altitudeM))", unit: "m", metrics: m)
    }

    /// TIME: 表示中 Trip の走行時間 "h:mm"。タップで走行記録シート
    private func timeCard(_ m: Metrics) -> some View {
        dataCard("TIME", value: durationString(showTripB ? ride.tripBSeconds : ride.ridingSeconds),
                 unit: "", metrics: m)
            .contentShape(Rectangle())
            .onTapGesture { showRideLog = true }
    }

    /// TRIP: ラベルはライム。タップで A/B 切替、長押しで表示中の側をリセット
    private func tripCard(_ m: Metrics) -> some View {
        dataCard(tripLabel, value: tripValue, unit: "km", labelColor: Palette.lime, metrics: m)
            .contentShape(Rectangle())
            .onTapGesture { showTripB.toggle() }
            .onLongPressGesture { resetDisplayedTrip() }
    }

    private func totalCard(_ m: Metrics) -> some View {
        dataCard("TOTAL", value: String(format: "%.0f", ride.totalMeters / 1000), unit: "km", metrics: m)
    }

    private func dataCard(_ label: String, value: String, unit: String,
                          valueColor: Color = Palette.textHi, labelColor: Color = Palette.label,
                          metrics m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            unitLabel(label, size: 10, color: labelColor)
                .frame(height: 13)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(motoNumberFont(30, .bold))
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(motoLabelFont(11, .semibold))
                        .foregroundColor(Palette.label)
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: m.cardHeight)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.borderWeak, lineWidth: 1))
    }

    /// 大文字ラベル・単位(IBM Plex Mono 600 相当・字間 1.5)
    private func unitLabel(_ text: String, size: CGFloat, color: Color) -> some View {
        Text(text)
            .font(motoLabelFont(size, .semibold))
            .tracking(1.5)
            .foregroundColor(color)
            .lineLimit(1)
    }

    // MARK: - データ派生

    /// GPSロスト中は "--"(最後の速度で固まった表示を出さない)
    private var speedText: String {
        ride.hasGPSFix ? "\(Int(ride.speedKMH.rounded()))" : "--"
    }

    /// GPSロスト中は速度を dim 表示
    private var speedColor: Color {
        ride.hasGPSFix ? Palette.textHi : Palette.dim
    }

    /// TRIP カード: タップで A/B 切替、長押しで表示中の側をリセット
    private var tripLabel: String { showTripB ? "TRIP B" : "TRIP A" }
    private var tripValue: String {
        String(format: "%.1f", (showTripB ? ride.tripBMeters : ride.tripMeters) / 1000)
    }
    private func resetDisplayedTrip() {
        if showTripB { ride.resetTripB() } else { ride.resetTrip() }
    }

    private var frontBar: Double? {
        guard let r = tpms.readings[.front], !r.isStale else { return nil }
        return r.pressureBar
    }
    private var rearBar: Double? {
        guard let r = tpms.readings[.rear], !r.isStale else { return nil }
        return r.pressureBar
    }
    private var frontTemp: Double? {
        guard let r = tpms.readings[.front], !r.isStale else { return nil }
        return r.temperatureC
    }
    private var rearTemp: Double? {
        guard let r = tpms.readings[.rear], !r.isStale else { return nil }
        return r.temperatureC
    }

    /// TPMS温度の表示文字列(整数℃)。未接続は "--℃"。
    private func tempText(_ c: Double?) -> String {
        c.map { "\(Int($0.rounded()))℃" } ?? "--℃"
    }

    private func cardinal(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((deg / 45).rounded())
        return dirs[(idx % 8 + 8) % 8]
    }

    /// 走行時間 "h:mm"
    private func durationString(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    /// 横画面の日付 "10/08 THU"(曜日は英語固定)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd EEE"
        return f
    }()

    /// 時刻 "HH:mm"
    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// ホーム画面へ戻す(サイドロード個人アプリ向け。公開APIではない点に留意)
    private func goHome() {
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            UIApplication.shared.perform(selector)
        }
    }
}

// MARK: - 小物

/// TPMSタイヤアイコン(外輪 stroke 2 + 中心の小リング stroke 1.5、ライム)
struct TireIcon: View {
    var size: CGFloat = 14
    var dot: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().strokeBorder(Palette.lime, lineWidth: 2).frame(width: size, height: size)
            Circle().strokeBorder(Palette.lime, lineWidth: 1.5).frame(width: dot, height: dot)
        }
    }
}
