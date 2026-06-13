import SwiftUI

/// メインダッシュボード(黒背景・高コントラスト・参考モニター準拠)
/// 横: 逆L字ゲージを左〜上に敷き、中央に速度、右に空気圧/統計。
/// 縦: 上に速度+ゲージ、下に空気圧/統計。
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

    // MARK: - 横レイアウト(メイン)

    private func landscapeLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .topLeading) {
                // ゲージを全幅に敷く
                SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 120, accent: accent)
                    .padding(.bottom, 44)   // 下端をバッテリー表示の上で止める

                // 速度数字 + KM/H(KM/Hは数字の上)
                VStack(alignment: .leading, spacing: 0) {
                    Text("KM/H")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.leading, 6)
                    Text("\(Int(ride.speedKMH))")
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                }
                .position(x: geo.size.width * 0.30, y: geo.size.height * 0.42)

                // 右側: 空気圧(右下)+ 統計(最下部)
                VStack(spacing: 8) {
                    Spacer()
                    tirePanelCompact(.front)
                    tirePanelCompact(.rear)
                    statsRow
                }
                .frame(width: geo.size.width * 0.34)
                .position(x: geo.size.width * 0.80, y: geo.size.height * 0.5)

                // 左下: 電圧/高度
                HStack(spacing: 28) {
                    miniStat(icon: batteryIcon, value: "\(ride.phoneBatteryPercent)%")
                    miniStat(icon: "mountain.2.fill", value: "\(Int(ride.altitudeM))m")
                }
                .position(x: geo.size.width * 0.16, y: geo.size.height - 20)
            }
        }
    }

    // MARK: - 縦レイアウト

    private func portraitLayout(_ geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .center) {
                SpeedGauge(speedKMH: ride.speedKMH, maxKMH: 120, accent: accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(ride.speedKMH))")
                        .font(.system(size: 90, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text("KM/H").font(.subheadline).foregroundColor(.white)
                }
                .offset(x: 14, y: 14)
            }
            .frame(height: geo.size.height * 0.40)

            HStack(spacing: 24) {
                miniStat(icon: batteryIcon, value: "\(ride.phoneBatteryPercent)%")
                miniStat(icon: "mountain.2.fill", value: "\(Int(ride.altitudeM))m")
            }
            .padding(.vertical, 8)

            VStack(spacing: 10) {
                tirePanelCompact(.front)
                tirePanelCompact(.rear)
                statsRow.padding(.top, 4)
            }
            .padding(16)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 上部バー(戻る/ステータス/時刻)

    private var topBar: some View {
        HStack {
            Image(systemName: "chevron.left")
                .foregroundColor(.gray)
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "wifi")
                Text("GPS").font(.caption.bold())
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .foregroundColor(.gray)
            Spacer()
            clockText
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
    }

    // 24時間表示・右寄せ・毎秒更新
    private var clockText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, format: .dateTime
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
        }
    }

    // MARK: - 部品

    private var batteryIcon: String {
        switch ride.phoneBatteryPercent {
        case 90...:   return "battery.100"
        case 65..<90: return "battery.75"
        case 40..<65: return "battery.50"
        case 15..<40: return "battery.25"
        default:      return "battery.0"
        }
    }

    private func miniStat(icon: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(accent)
            Text(value).font(.title3.monospacedDigit()).bold().foregroundColor(.white)
        }
    }

    /// 小型の空気圧パネル(重要度を下げて省スペース化)
    private func tirePanelCompact(_ position: WheelPosition) -> some View {
        let reading = tpms.readings[position]
        let assigned = tpms.assignments[position] != nil
        let live = reading.map { !$0.isStale } ?? false

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(position == .front ? "FRONT (BAR)" : "REAR (BAR)")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(live ? String(format: "%.2f", reading!.pressureBar) : "-.--")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(pressureColor(reading, live: live))
                    Text(live ? "\(Int(reading!.temperatureC))°C" : "--°C")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundColor(.white.opacity(0.75))
                }
            }
            Spacer()
            Image(systemName: live ? "bicycle" : "bicycle")
                .font(.system(size: 18))
                .foregroundColor(live ? accent : .gray.opacity(0.5))
            if !assigned {
                Text("未割当").font(.system(size: 9)).foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .onTapGesture { showSniffer = true }
    }

    private func pressureColor(_ reading: TPMSReading?, live: Bool) -> Color {
        guard live, let reading else { return .gray }
        return reading.pressureBar < tpms.lowPressureThreshold ? .red : .white
    }

    private var statsRow: some View {
        HStack {
            statItem("Total", String(format: "%.0fkm", ride.totalMeters / 1000))
            Spacer()
            statItem("Time", timeString(ride.ridingSeconds))
            Spacer()
            statItem("Trip", String(format: "%.1fkm", ride.tripMeters / 1000))
                .onLongPressGesture { ride.resetTrip() }
        }
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.gray)
            Text(value).font(.subheadline.monospacedDigit()).foregroundColor(.white)
        }
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }
}
