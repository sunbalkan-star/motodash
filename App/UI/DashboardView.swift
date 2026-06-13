import SwiftUI

/// メインダッシュボード(横向き・黒背景・高コントラスト)
struct DashboardView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @State private var showSniffer = false

    private let accent = Color(red: 0.65, green: 0.95, blue: 0.15) // ライムグリーン

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // ===== 左: 速度メーター =====
                speedPane
                    .frame(width: geo.size.width * 0.45)

                Divider().background(Color.white.opacity(0.15))

                // ===== 右: タイヤ + 走行統計 =====
                VStack(spacing: 12) {
                    tirePanel(.front)
                    tirePanel(.rear)
                    statsRow
                }
                .padding(16)
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
                miniStat(icon: "battery.75",
                         value: "\(ride.phoneBatteryPercent)%")
                miniStat(icon: "mountain.2.fill",
                         value: "\(Int(ride.altitudeM))m")
            }
            Text(ride.gpsStatus)
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 8)
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
