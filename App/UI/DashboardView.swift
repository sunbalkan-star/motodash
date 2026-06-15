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
        let topInset: CGFloat = 52
        let contentH = h - topInset
        let gaugeH = contentH * 0.74
        // SpeedGauge側と同じ式: lineWidth = min(w, gaugeH) * 0.20
        let lineWidth = min(w, gaugeH) * 0.20
        // 大速度の配置: 横=40〜80ラベルの中間(60km/h tick位置), 縦=20km/hラベルと同じ高さ
        let half = lineWidth / 2
        let r = lineWidth * 1.1
        let hStartX = half + r
        let hEndX = w - half
        let vBottomY = gaugeH - half
        let arcStartY = half + r
        let bigSpeedX = hStartX + (hEndX - hStartX) * (60.0 - 40.0) / (160.0 - 40.0)
        let bigSpeedY = vBottomY - (vBottomY - arcStartY) * (20.0 / 40.0)

        return ZStack(alignment: .topLeading) {
            topBar(w: w)

            // ゲージ + 大速度数字(60km/h位置・20km/h高さ)
            SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 160, accent: accent)
                .frame(width: w, height: gaugeH)
                .overlay {
                    bigSpeed(size: 88)
                        .position(x: bigSpeedX, y: bigSpeedY)
                }
                .position(x: w / 2, y: topInset + gaugeH / 2)

            // 左下: 空気圧(2輪)
            VStack(alignment: .leading, spacing: 8) {
                tirePressureRow(.front)
                tirePressureRow(.rear)
            }
            .position(x: w * 0.20, y: h * 0.82)

            // 右側テレメトリ 2行×3列:
            //   上段(右詰め): [空き] [BATTERY] [ALTITUDE]
            //   下段:         [TRIP] [TIME]    [TOTAL]
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    telemetryCell("", "0", unit: "").hidden()   // レイアウト確保用の空セル
                    telemetryCell("BATTERY", "\(ride.phoneBatteryPercent)", unit: "%")
                    telemetryCell("ALTITUDE", "\(Int(ride.altitudeM))", unit: "m")
                }
                HStack(spacing: 12) {
                    telemetryCell("TRIP", String(format: "%.1f", ride.tripMeters / 1000), unit: "km")
                        .onLongPressGesture { ride.resetTrip() }
                    telemetryCell("TIME", timeString(ride.ridingSeconds), unit: "")
                    telemetryCell("TOTAL", String(format: "%.0f", ride.totalMeters / 1000), unit: "km")
                }
            }
            .frame(width: w * 0.56)
            .position(x: w * 0.68, y: topInset + contentH * 0.62)
        }
    }

    // MARK: - 縦レイアウト

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        let w = geo.size.width
        let h = geo.size.height
        let gaugeH = h * 0.30
        let lineWidth = min(w, gaugeH) * 0.20

        return VStack(spacing: 0) {
            topBar(w: w)
            Spacer(minLength: 0)

            // ゲージ + 大速度(左右中央、縦バーの下端と下揃え)
            SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 160, accent: accent)
                .frame(height: gaugeH)
                .overlay(alignment: .bottom) {
                    bigSpeed(size: 64)
                        .padding(.bottom, lineWidth / 2)
                }

            // 空気圧
            VStack(spacing: 10) {
                tirePressureRow(.front)
                tirePressureRow(.rear)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            // テレメトリ 3行×2列:
            //   左列(下詰め): [空き] / BATTERY / ALTITUDE
            //   右列:         TRIP / TIME / TOTAL
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    telemetryCell("", "0", unit: "").hidden()
                    telemetryCell("BATTERY", "\(ride.phoneBatteryPercent)", unit: "%")
                    telemetryCell("ALTITUDE", "\(Int(ride.altitudeM))", unit: "m")
                }
                VStack(spacing: 10) {
                    telemetryCell("TRIP", String(format: "%.1f", ride.tripMeters / 1000), unit: "km")
                        .onLongPressGesture { ride.resetTrip() }
                    telemetryCell("TIME", timeString(ride.ridingSeconds), unit: "")
                    telemetryCell("TOTAL", String(format: "%.0f", ride.totalMeters / 1000), unit: "km")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 36)
    }

    // MARK: - 大速度数字(L字の内側角に貼り付ける用)

    private func bigSpeed(size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -4) {
            Text("\(Int(ride.speedKMH))")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("Km/h")
                .font(.system(size: size * 0.22, weight: .semibold))
                .foregroundColor(accent)
        }
    }

    // MARK: - 上部バー

    private func topBar(w: CGFloat) -> some View {
        HStack(spacing: 10) {
            // 戻る矢印(タップでホーム画面へ)
            Button(action: goHome) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            .fixedSize()

            // 左小窓: 現在速度
            miniSpeedBox(value: Int(ride.speedKMH), unit: "Km/h", emphasized: false)

            Spacer(minLength: 4)

            // コンパス(緑矢印 + 方位)
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .foregroundColor(accent)
                    .rotationEffect(.degrees(ride.headingDegrees))
                Text("\(Int(ride.headingDegrees))° \(cardinal(ride.headingDegrees))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            // 右小窓: 最高速
            miniSpeedBox(value: Int(ride.maxSpeedKMH), unit: "KM/H", emphasized: true)

            clockText.fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    private func miniSpeedBox(value: Int, unit: String, emphasized: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(emphasized ? 0.45 : 0.25), lineWidth: 1)
        )
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
