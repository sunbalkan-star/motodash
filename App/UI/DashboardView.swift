import SwiftUI

/// メインダッシュボード(黒背景・参考スマートモニター準拠)
struct DashboardView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @State private var showSniffer = false

    private let accent = Color(red: 0.65, green: 0.95, blue: 0.15) // ライムグリーン

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height >= geo.size.width
            Group {
                if isPortrait { portraitLayout(geo) }
                else { landscapeLayout(geo) }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .sheet(isPresented: $showSniffer) {
            SnifferView().environmentObject(tpms)
        }
    }

    // MARK: - 横レイアウト

    private func landscapeLayout(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let topInset: CGFloat = 52        // 上部バーの高さ分、コンテンツを下げる
        let contentH = h - topInset

        return ZStack(alignment: .topLeading) {
            // 上部バー(最前面・固定)
            topBar(w: w)

            // ゲージ: 上辺全幅 + 左を垂直に(縦部分を伸ばすため高さ拡大)
            SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 160, accent: accent)
                .frame(width: w, height: contentH * 0.74)
                .position(x: w / 2, y: topInset + contentH * 0.37)

            // 大速度表示(ゲージの縦部分寄りに左へ詰める)
            VStack(alignment: .leading, spacing: -6) {
                Text("\(Int(ride.speedKMH))")
                    .font(.system(size: 80, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text("Km/h")
                    .font(.headline)
                    .foregroundColor(accent)
                    .padding(.leading, 4)
            }
            .position(x: w * 0.20, y: topInset + contentH * 0.40)

            // 左下: 空気圧(2輪)— 現状維持
            VStack(alignment: .leading, spacing: 8) {
                tirePressureRow(.front)
                tirePressureRow(.rear)
            }
            .position(x: w * 0.20, y: h * 0.82)

            // 右側テレメトリ: 左列(空き/TIME/BATTERY)+ 右列(TRIP/TOTAL/ALTITUDE)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    Color.clear.frame(maxWidth: .infinity).frame(height: 64)  // 上段を空ける
                    telemetryCell("TIME", timeString(ride.ridingSeconds), unit: "")
                    telemetryCell("BATTERY", "\(ride.phoneBatteryPercent)", unit: "%")
                }
                VStack(spacing: 12) {
                    telemetryCell("TRIP", String(format: "%.1f", ride.tripMeters / 1000), unit: "km")
                        .onLongPressGesture { ride.resetTrip() }
                    telemetryCell("TOTAL", String(format: "%.0f", ride.totalMeters / 1000), unit: "km")
                    telemetryCell("ALTITUDE", "\(Int(ride.altitudeM))", unit: "m")
                }
            }
            .frame(width: w * 0.46)
            .position(x: w * 0.72, y: topInset + contentH * 0.54)
        }
    }

    // MARK: - 縦レイアウト

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        return VStack(spacing: 0) {
            topBar(w: w)

            Spacer(minLength: 0)   // 上の余白(中央寄せ)

            // ゲージ + 速度(速度は左右中央)
            ZStack {
                SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 160, accent: accent)
                    .frame(height: h * 0.30)
                VStack(spacing: -2) {
                    Text("\(Int(ride.speedKMH))")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text("Km/h").font(.subheadline).foregroundColor(accent)
                }
                .frame(maxWidth: .infinity)   // 左右中央
            }
            .frame(height: h * 0.30)

            // 空気圧
            VStack(spacing: 10) {
                tirePressureRow(.front)
                tirePressureRow(.rear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // テレメトリ 2列
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    telemetryCell("ALTITUDE", "\(Int(ride.altitudeM))", unit: "m")
                    telemetryCell("TRIP", String(format: "%.1f", ride.tripMeters / 1000), unit: "km")
                        .onLongPressGesture { ride.resetTrip() }
                }
                HStack(spacing: 10) {
                    telemetryCell("TIME", timeString(ride.ridingSeconds), unit: "")
                    telemetryCell("BATTERY", "\(ride.phoneBatteryPercent)", unit: "%")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer(minLength: 0)   // 下の余白(中央寄せ)
        }
        .padding(.bottom, 36)
    }

    // MARK: - 上部バー

    private func topBar(w: CGFloat) -> some View {
        HStack {
            // 戻る矢印(タップでホーム画面へ)
            Button(action: goHome) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            Spacer()
            // コンパス(緑矢印 + 方位)
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .foregroundColor(accent)
                    .rotationEffect(.degrees(ride.headingDegrees))
                Text("\(Int(ride.headingDegrees))° \(cardinal(ride.headingDegrees))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white)
            }
            Spacer()
            clockText
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    private var clockText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, format: .dateTime
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }

    // MARK: - 空気圧行

    private func tirePressureRow(_ position: WheelPosition) -> some View {
        let reading = tpms.readings[position]
        let assigned = tpms.assignments[position] != nil
        let live = reading.map { !$0.isStale } ?? false

        return HStack(spacing: 10) {
            // タイヤアイコン(前後で塗り分け)
            Image(systemName: "circle.circle")
                .font(.system(size: 18))
                .foregroundColor(live ? accent : .gray.opacity(0.6))
            Text(position == .front ? "F" : "R")
                .font(.caption2.bold())
                .foregroundColor(.gray)
            Text(live ? String(format: "%.2f", reading!.pressureBar) : "-.--")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(pressureColor(reading, live: live))
            Text(live ? "\(Int(reading!.temperatureC))°C" : "--°C")
                .font(.system(size: 15).monospacedDigit())
                .foregroundColor(.white.opacity(0.7))
            if !assigned {
                Text("未割当").font(.system(size: 10)).foregroundColor(.orange)
            }
        }
        .onTapGesture { showSniffer = true }
    }

    private func pressureColor(_ reading: TPMSReading?, live: Bool) -> Color {
        guard live, let reading else { return .gray }
        return reading.pressureBar < tpms.lowPressureThreshold ? .red : .white
    }

    // MARK: - テレメトリセル

    private func telemetryCell(_ title: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    // MARK: - ヘルパー

    /// ホーム画面へ戻す(サイドロード個人アプリ向け。公開APIではない点に留意)
    private func goHome() {
        let selector = NSSelectorFromString("suspend")
        if UIApplication.shared.responds(to: selector) {
            UIApplication.shared.perform(selector)
        }
    }

    private func cardinal(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((deg + 22.5) / 45) % 8
        return dirs[max(0, idx)]
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
