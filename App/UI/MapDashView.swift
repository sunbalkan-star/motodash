import SwiftUI
import MapKit

/// マップ画面(ダッシュボードと左右スワイプで切替)。Apple 純正 MapKit をモノクロ化して表示する。
/// 自車は画面の 65% 高さに矢印固定、地図側が進行方向に回る(ヘディングアップ)。タップでノースアップ切替。
/// 表示データは GPS(位置・速度・進行方向)/ 磁気(停車中の方位)/ TPMS のみ。
///
/// 横画面(812×375)の縦内訳: 上 8 + ステータスバー 36 + 地図(可変) + 下ボックス 104 + 下 20。
///   自車矢印 y≒244(h36 → 226〜262)。下ボックスは左右の角(速度 46〜214 / TPMS 644〜794)なので矢印(x≒406)と重ならない。
/// 縦画面(375×812)の縦内訳: セーフエリア上 + 4 + ステータスバー 36 + 地図(可変) + 下ボックス 104 + セーフエリア下 + 8。
///   自車矢印 y≒528、下ボックス上端 ≒666 で干渉しない。
struct MapDashView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    /// ノースアップ表示(タップで切替)。次回起動時も維持
    @AppStorage("map.northUp") private var northUp = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 自車位置の画面内高さ(上からの割合)。前方を広く見せるため中央より下に置く
    private let vehicleY: CGFloat = 0.65
    private let boxHeight: CGFloat = 104

    var body: some View {
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let isPortrait = geo.size.height >= geo.size.width
            // 画面全体のサイズ(地図はセーフエリアを無視して全面に敷く)
            let w = geo.size.width + safe.leading + safe.trailing
            let h = geo.size.height + safe.top + safe.bottom
            let notchOnLeading = safe.leading >= safe.trailing
            let insets = isPortrait
                ? EdgeInsets(top: safe.top + 4, leading: 16, bottom: safe.bottom + 8, trailing: 16)
                : EdgeInsets(top: 8, leading: notchOnLeading ? 46 : 18,
                             bottom: 20, trailing: notchOnLeading ? 18 : 46)

            ZStack(alignment: .topLeading) {
                // 地図は高さを (vehicleY×2) 倍にして、カメラ中心 = 自車位置が vehicleY に来るようにする。
                // はみ出した下側は画面外。Apple の法的表記は layoutMargins で下ボックスの上に出す
                MonoMapView(location: ride.location,
                            heading: northUp ? 0 : travelHeading,
                            distance: cameraDistance,
                            legalMargins: UIEdgeInsets(
                                top: 0, left: insets.leading,
                                bottom: h * (vehicleY * 2 - 1) + insets.bottom + boxHeight + 8,
                                right: insets.trailing))
                    .saturation(0)
                    .contrast(1.15)
                    .frame(width: w, height: h * vehicleY * 2)

                VehicleArrow()
                    .rotationEffect(.degrees(northUp ? travelHeading : 0))
                    .position(x: w / 2, y: h * vehicleY)

                hud(isPortrait)
                    .padding(insets)
                    .frame(width: w, height: h)
            }
            .frame(width: w, height: h)
            .clipped()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { northUp.toggle() }
            .persistentSystemOverlays(isPortrait ? .automatic : .hidden)
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - HUD(上: GPS・方位・時刻 / 下: 速度・TPMS)

    private func hud(_ isPortrait: Bool) -> some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                speedBox
                    .frame(maxWidth: isPortrait ? .infinity : 168, alignment: .leading)
                if !isPortrait { Spacer(minLength: 0) }
                tpmsBox
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                gpsPill
                Text(northUp ? "N-UP" : "H-UP")
                    .font(motoLabelFont(10, .semibold))
                    .tracking(1.5)
                    .foregroundColor(Palette.textMid)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(Palette.bg.opacity(0.85)))
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(cardinal(ride.headingDegrees))
                    .font(motoNumberFont(20, .heavy))
                Text(String(format: "%03d°", Int(ride.headingDegrees.rounded()) % 360))
                    .font(motoNumberFont(14, .bold))
            }
            .foregroundColor(Palette.cyan)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Palette.bg.opacity(0.85)))

            Text(Self.clockFormatter.string(from: now))
                .font(motoNumberFont(17, .bold))
                .foregroundColor(Palette.textHi)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Palette.bg.opacity(0.85)))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 36)
    }

    private var gpsPill: some View {
        let color = ride.hasGPSFix ? Palette.lime : Palette.amber
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(ride.hasGPSFix ? "GPS" : "GPS LOST")
                .font(motoLabelFont(9, .semibold))
                .tracking(1.5)
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(Palette.bg.opacity(0.85)))
        .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    /// 速度(h104): 数字 60pt + KM/H
    private var speedBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ride.hasGPSFix ? "\(Int(ride.speedKMH.rounded()))" : "--")
                .font(motoNumberFont(60, .heavy))
                .foregroundColor(ride.hasGPSFix ? Palette.textHi : Palette.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 70)
            label("KM/H", color: Palette.textMid)
                .frame(height: 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: boxHeight)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.bg.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.borderStrong, lineWidth: 1.5))
    }

    /// TPMS(h104・w150): F / R の2行
    private var tpmsBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            tpmsRow("F", .front)
            tpmsRow("R", .rear)
        }
        .padding(.horizontal, 14)
        .frame(width: 150, height: boxHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.bg.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.borderStrong, lineWidth: 1.5))
    }

    private func tpmsRow(_ title: String, _ pos: WheelPosition) -> some View {
        let bar = freshReading(pos)?.pressureBar
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            label(title, color: Palette.label)
                .frame(width: 12, alignment: .leading)
            Text(bar.map { String(format: "%.1f", $0) } ?? "-.--")
                .font(motoNumberFont(28, .heavy))
                .foregroundColor(StateColor.pressure(bar))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            label("BAR", color: Palette.label)
        }
        .frame(height: 36)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(motoLabelFont(10, .semibold))
            .tracking(1.5)
            .foregroundColor(color)
            .lineLimit(1)
    }

    // MARK: - データ派生

    private func freshReading(_ pos: WheelPosition) -> TPMSReading? {
        guard let r = tpms.readings[pos], !r.isStale else { return nil }
        return r
    }

    /// 進行方向: 走行中は GPS コース(安定)、停車・低速中はコンパス
    private var travelHeading: Double {
        if let loc = ride.location, loc.course >= 0, ride.speedKMH >= 8 {
            return loc.course
        }
        return ride.headingDegrees
    }

    /// 速度連動ズーム: 0km/h=500m 〜 120km/h 以上=2400m(カメラ高度)
    private var cameraDistance: Double {
        min(2400, 500 + ride.speedKMH * 16)
    }

    private func cardinal(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((deg / 45).rounded())
        return dirs[(idx % 8 + 8) % 8]
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 自車矢印(ライム・黒縁)

struct VehicleArrow: View {
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 30, weight: .bold))
            .foregroundColor(Palette.lime)
            .shadow(color: .black.opacity(0.9), radius: 3)
            .frame(width: 36, height: 36)
    }
}

// MARK: - MKMapView ラッパー(モノクロ・操作無効・カメラ追従・走行軌跡)

struct MonoMapView: UIViewRepresentable {
    var location: CLLocation?
    var heading: Double
    var distance: Double
    var legalMargins: UIEdgeInsets

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        map.preferredConfiguration = config
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        // 地図はカメラ追従専用。タッチは SwiftUI 側(スワイプ切替・タップでノースアップ)へ通す
        map.isUserInteractionEnabled = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        if map.layoutMargins != legalMargins { map.layoutMargins = legalMargins }
        guard let location else { return }
        let c = context.coordinator
        c.appendTrail(location.coordinate, to: map)

        // コンパスは毎秒何度も更新されるため、変化が小さい時はカメラを動かさない
        let moved = c.lastCenter.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) >= 1
        } ?? true
        let turned = abs(angleDiff(heading, c.lastHeading)) >= 2
        let zoomed = abs(distance - c.lastDistance) >= 50
        guard moved || turned || zoomed else { return }

        let first = c.lastCenter == nil
        c.lastCenter = location.coordinate
        c.lastHeading = heading
        c.lastDistance = distance
        let camera = MKMapCamera(lookingAtCenter: location.coordinate,
                                 fromDistance: distance, pitch: 0, heading: heading)
        map.setCamera(camera, animated: !first)
    }

    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? d - 360 : (d < -180 ? d + 360 : d)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastCenter: CLLocationCoordinate2D?
        var lastHeading: Double = 0
        var lastDistance: Double = 0

        /// 走行軌跡(この画面を開いている間のみ・10m 間引き・最大 5000 点)
        private var trail: [CLLocationCoordinate2D] = []
        private var polyline: MKPolyline?

        func appendTrail(_ coord: CLLocationCoordinate2D, to map: MKMapView) {
            if let last = trail.last {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                guard d >= 10 else { return }
            }
            trail.append(coord)
            if trail.count > 5000 { trail.removeFirst(trail.count - 5000) }
            guard trail.count >= 2 else { return }
            if let polyline { map.removeOverlay(polyline) }
            let line = MKPolyline(coordinates: trail, count: trail.count)
            map.addOverlay(line, level: .aboveRoads)
            polyline = line
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = UIColor.white.withAlphaComponent(0.85)
            r.lineWidth = 5
            r.lineCap = .round
            r.lineJoin = .round
            return r
        }
    }
}
