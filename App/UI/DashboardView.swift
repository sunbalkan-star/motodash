import SwiftUI

/// メインダッシュボード(黒背景・高コントラスト)
/// デバイスの向きに応じて横/縦レイアウトを自動で切り替える。
///   横: 左=速度メーター / 右=タイヤ+統計
///   縦: 上=速度メーター / 下=タイヤ+統計
struct DashboardView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @State private var showSniffer = false

    private let accent = Color(red: 0.65, green: 0.95, blue: 0.15) // ライムグリーン

    var body: some View {
        GeometryReader { geo in
            let isPortrait = geo.size.height >= geo.size.width

            Group {
                if isPortrait {
                    // ===== 縦: 上下分割(時刻は最上部に独立) =====
                    VStack(spacing: 0) {
                        clockView
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                        speedPane
                            .frame(height: geo.size.height * 0.38)
                        Divider().background(Color.white.opacity(0.15))
                        rightStack(showClock: false)
                            .padding(16)
                        Spacer(minLength: 0)
                    }
                } else {
                    // ===== 横: 左右分割(時刻は右上) =====
                    HStack(spacing: 0) {
                        speedPane
                            .frame(width: geo.size.width * 0.45)
                        Divider().background(Color.white.opacity(0.15))
                        rightStack(showClock: true)
                            .padding(16)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .sheet(isPresented: $showSniffer) {
            SnifferView()
                .environmentObject(tpms)
        }
    }

    // MARK: 右側(縦では下側)— タイヤ + 統計(時刻は横画面のみここに表示)

    private func rightStack(showClock: Bool) -> some View {
        VStack(spacing: 12) {
            if showClock { clockView }
            tirePanel(.front)
            tirePanel(.rear)
            statsRow
        }
    }

    // MARK: 時刻表示(24時間)
    // TimelineView(.periodic) で毎秒確実に再描画される(手動タイマー不要)

    private var clockView: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, format: .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }

    // MARK: 速度ペイン

    private var speedPane: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("\(Int(ride.speedKMH))")
                .font(.system(size: 130, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("KM/H")
                .font(.headline)
                .foregroundColor(accent)
            Spacer()
            HStack(spacing: 24) {
                miniStat(icon: batteryIcon, value: "\(ride.phoneBatteryPercent)%")
                miniStat(icon: "mountain.2.fill", value: "\(Int(ride.altitudeM))m")
            }
            Text(ride.gpsStatus)
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 8)
    }

    /// 電池残量に応じてアイコンを切り替え
    private var batteryIcon: String {
        switch ride.phoneBatteryPercent {
        case 90...:  return "battery.100"
        case 65..<90: return "battery.75"
        case 40..<65: return "battery.50"
        case 15..<40: return "battery.25"
        default:      return "battery.0"
        }
    }

    private func miniStat(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(accent)
            Text(value)
                .font(.title3.monospacedDigit())
                .bold()
                .foregroundColor(.white)
        }
    }

    // MARK: タイヤパネル

    private func tirePanel(_ position: WheelPosition) -> some View {
        let reading = tpms.readings[position]
        let assigned = tpms.assignments[position] != nil
        let live = reading.map { !$0.isStale } ?? false

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position == .front ? "FRONT (BAR)" : "REAR (BAR)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(live ? String(format: "%.2f", reading!.pressureBar) : "-.--")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(pressureColor(reading, live: live))
                    Text(live ? "\(Int(reading!.temperatureC))°C" : "--°C")
                        .font(.title3.monospacedDigit())
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: live ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(live ? accent : .gray)
                if !assigned {
                    Text("未割当")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                if let battery = reading?.batteryPercent, live {
                    Text("🔋\(battery)%")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
        .onTapGesture { showSniffer = true }   // タップでセンサー割当画面へ
    }

    private func pressureColor(_ reading: TPMSReading?, live: Bool) -> Color {
        guard live, let reading else { return .gray }
        return reading.pressureBar < tpms.lowPressureThreshold ? .red : accent
    }

    // MARK: 走行統計

    private var statsRow: some View {
        HStack {
            statItem(title: "Total",
                     value: String(format: "%.0fkm", ride.totalMeters / 1000))
            Spacer()
            statItem(title: "Time", value: timeString(ride.ridingSeconds))
            Spacer()
            statItem(title: "Trip",
                     value: String(format: "%.1fkm", ride.tripMeters / 1000))
                .onLongPressGesture { ride.resetTrip() }  // 長押しでTripリセット
        }
        .padding(.horizontal, 6)
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(.white)
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}
