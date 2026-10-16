import SwiftUI
import MapKit

/// マップ画面(ダッシュボードと左右スワイプで切替)。Apple 純正 MapKit をモノクロ化して表示する。
/// 自車は画面の 65% 高さに矢印固定、地図側が進行方向に回る(ヘディングアップ)。タップでノースアップ切替。
/// 表示データは GPS(位置・速度・進行方向)/ 磁気(停車中の方位)/ TPMS のみ。
///
/// 横画面(812×375)の縦内訳: 上 8 + ステータスバー 36 + 間 8 + 案内ボックス h76 / ボタン列 h148(44×3 + 8×2)
///   + 地図(可変) + 下ボックス 104 + 下 20。ボタン列下端 200 < 下ボックス上端 251。
///   自車矢印 y≒244(h36 → 226〜262)。案内ボックスは左上(46〜296)、ボタン列は右上、下ボックスは左右の角なので
///   矢印(x≒406)とどれも重ならない。
/// 縦画面(375×812)の縦内訳: セーフエリア上 + 4 + ステータスバー 36 + 間 8 + 案内ボックス 76 / ボタン列 148
///   + 地図(可変) + 下ボックス 104 + セーフエリア下 + 8。自車矢印 y≒528、ボタン列下端 ≒247、下ボックス上端 ≒666。
struct MapDashView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @EnvironmentObject var nav: NavManager
    /// ノースアップ表示(タップで切替)。次回起動時も維持
    @AppStorage("map.northUp") private var northUp = false
    /// 停車中のみ入れる地図操作モード(拡大縮小・スクロール・長押しで目的地)。走り出すと自動解除
    @State private var interactive = false
    @State private var showNavSheet = false
    @State private var showPinDialog = false
    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 自車位置の画面内高さ(上からの割合)。前方を広く見せるため中央より下に置く
    private let vehicleY: CGFloat = 0.65
    private let boxHeight: CGFloat = 104
    /// これ未満を停車とみなす(km/h)。操作モードはこれ以上で自動解除
    private let stoppedKMH: Double = 3
    private let exitInteractiveKMH: Double = 5

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
                                right: insets.trailing),
                            interactive: interactive,
                            route: nav.route?.polyline,
                            routeVersion: nav.routeVersion,
                            gpxRoute: nav.gpxRoute,
                            gpxVersion: nav.gpxVersion,
                            waypoints: nav.waypoints,
                            waypointsVersion: nav.waypointsVersion,
                            destination: nav.destination,
                            onLongPress: { coord in
                                nav.setDestination(name: "地図で指定", coordinate: coord)
                            })
                    .saturation(0)
                    .contrast(1.15)
                    .frame(width: w, height: h * vehicleY * 2)

                // 夜間ディム(地図のみ。HUD は暗くしない)
                Color.black
                    .opacity(nightDimOpacity)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)

                if !interactive {
                    VehicleArrow()
                        .rotationEffect(.degrees(northUp ? travelHeading : 0))
                        .position(x: w / 2, y: h * vehicleY)
                        .allowsHitTesting(false)
                }

                hud(isPortrait)
                    .padding(insets)
                    .frame(width: w, height: h)
            }
            .frame(width: w, height: h)
            .clipped()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { if !interactive { northUp.toggle() } }
            .persistentSystemOverlays(isPortrait ? .automatic : .hidden)
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .preference(key: SwipeLockKey.self, value: interactive)
        .onReceive(ticker) { now = $0 }
        .onChange(of: ride.speedKMH) { kmh in
            if interactive, kmh >= exitInteractiveKMH { interactive = false }
        }
        .sheet(isPresented: $showNavSheet) {
            NavSheet()
                .environmentObject(nav)
                .environmentObject(ride)
        }
        .confirmationDialog("現在地を保存", isPresented: $showPinDialog, titleVisibility: .visible) {
            ForEach(Waypoint.Kind.allCases, id: \.self) { kind in
                Button(kind.label) {
                    if let c = ride.location?.coordinate { nav.addWaypoint(kind, at: c) }
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // MARK: - HUD(上: GPS・方位・時刻 / 案内・ボタン列 / 下: 速度・TPMS)

    private func hud(_ isPortrait: Bool) -> some View {
        VStack(spacing: 0) {
            topBar
            HStack(alignment: .top, spacing: 8) {
                if nav.destination != nil {
                    navBox
                        .frame(maxWidth: isPortrait ? .infinity : 250, alignment: .leading)
                }
                Spacer(minLength: 0)
                controls
            }
            .padding(.top, 8)
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
                Text(interactive ? "MOVE" : (northUp ? "N-UP" : "H-UP"))
                    .font(motoLabelFont(10, .semibold))
                    .tracking(1.5)
                    .foregroundColor(interactive ? Palette.lime : Palette.textMid)
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

    // MARK: - 案内ボックス(h76: アイコン 36 + 距離 26pt / 案内文 / 残り)

    private var navBox: some View {
        HStack(spacing: 12) {
            navIcon
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(navPrimaryText)
                    .font(motoNumberFont(26, .heavy))
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: 30)
                Text(navSecondaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
                    .frame(height: 15)
                label(navTertiaryText, color: nav.routeError != nil ? Palette.amber : Palette.label)
                    .frame(height: 13)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.bg.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.borderStrong, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { showNavSheet = true }
    }

    /// ルートあり=次の操作アイコン / ルートなし=目的地方向の矢印(直線コンパス) / 到着=旗
    @ViewBuilder
    private var navIcon: some View {
        if nav.arrived {
            Image(systemName: "flag.checkered")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Palette.lime)
        } else if nav.route != nil {
            Image(systemName: nav.nextManeuverSymbol)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(Palette.lime)
        } else {
            Image(systemName: "location.north.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(Palette.lime)
                .rotationEffect(.degrees(nav.bearingToDestination - (northUp ? 0 : travelHeading)))
        }
    }

    private var navPrimaryText: String {
        if nav.arrived { return "到着" }
        if nav.route != nil, let d = nav.distanceToManeuver { return distanceText(d) }
        return nav.distanceToDestination.map(distanceText) ?? "--"
    }

    private var navSecondaryText: String {
        let name = nav.destination?.name ?? ""
        if nav.arrived || nav.route == nil { return name }
        return nav.nextInstruction ?? name
    }

    private var navTertiaryText: String {
        if nav.arrived { return "TAP TO END" }
        if nav.isRouting { return "ROUTING…" }
        if let err = nav.routeError { return err }
        if let r = nav.remainingRouteMeters { return "残り \(distanceText(r))" }
        return "直線距離"
    }

    // MARK: - ボタン列(右上: ナビ / 地点保存 / 地図操作 or 現在地へ戻る)

    private var controls: some View {
        VStack(spacing: 8) {
            mapButton("magnifyingglass") { showNavSheet = true }
            mapButton("mappin.and.ellipse") { showPinDialog = true }
                .disabled(ride.location == nil)
            if interactive {
                mapButton("location.fill", tint: Palette.lime) { interactive = false }
            } else if ride.speedKMH < stoppedKMH {
                mapButton("arrow.up.and.down.and.arrow.left.and.right") { interactive = true }
            }
        }
    }

    private func mapButton(_ symbol: String, tint: Color = Palette.textHi,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bg.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.borderStrong, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 下ボックス

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

    /// 太陽高度で地図を暗くする: 昼 0 / 薄明(0〜-6°)0.25 / 夜(-6°未満)0.45。位置が無ければ 18〜6時を夜とみなす
    private var nightDimOpacity: Double {
        guard let c = ride.location?.coordinate else {
            let hour = Calendar.current.component(.hour, from: now)
            return (hour >= 18 || hour < 6) ? 0.45 : 0
        }
        let alt = SolarPosition.altitude(at: now, latitude: c.latitude, longitude: c.longitude)
        if alt < -6 { return 0.45 }
        if alt < 0 { return 0.25 }
        return 0
    }

    private func distanceText(_ m: Double) -> String {
        m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
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

// MARK: - 太陽高度(簡易計算・誤差 1° 程度。夜間ディム用)

enum SolarPosition {
    static func altitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0   // J2000 からの日数
        let meanLon = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360) * rad
        let eclLon = (meanLon + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad
        let dec = asin(sin(obliquity) * sin(eclLon))
        let ra = atan2(cos(obliquity) * sin(eclLon), cos(eclLon))
        let gmst = (280.46061837 + 360.98564736629 * n).truncatingRemainder(dividingBy: 360)
        let hourAngle = (gmst + longitude) * rad - ra
        let lat = latitude * rad
        return asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)) / rad
    }
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

// MARK: - MKMapView ラッパー(モノクロ・カメラ追従・走行軌跡・案内ルート・GPX・地点)

struct MonoMapView: UIViewRepresentable {
    var location: CLLocation?
    var heading: Double
    var distance: Double
    var legalMargins: UIEdgeInsets
    /// true=停車中の操作モード(追従を止め、拡大縮小・スクロール・長押しを許可)
    var interactive: Bool
    var route: MKPolyline?
    var routeVersion: Int
    var gpxRoute: [CLLocationCoordinate2D]
    var gpxVersion: Int
    var waypoints: [Waypoint]
    var waypointsVersion: Int
    var destination: Destination?
    var onLongPress: (CLLocationCoordinate2D) -> Void

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
        map.isPitchEnabled = false
        map.delegate = context.coordinator
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onLongPress = onLongPress
        // 走行中はタッチを SwiftUI 側(スワイプ切替・タップでノースアップ)へ通す
        map.isUserInteractionEnabled = interactive
        map.showsUserLocation = interactive   // 操作モード中は自車矢印の代わりに青点(グレー)で現在地を示す
        if map.layoutMargins != legalMargins { map.layoutMargins = legalMargins }

        c.syncRoute(route, version: routeVersion, on: map)
        c.syncGPX(gpxRoute, version: gpxVersion, on: map)
        c.syncPins(waypoints, version: waypointsVersion, destination: destination, on: map)

        guard let location else { return }
        c.appendTrail(location.coordinate, to: map)
        guard !interactive else {
            c.lastCenter = nil   // 操作モード解除時に現在地へ戻す
            return
        }

        // コンパスは毎秒何度も更新されるため、変化が小さい時はカメラを動かさない
        let moved = c.lastCenter.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) >= 1
        } ?? true
        let turned = abs(angleDiff(heading, c.lastHeading)) >= 2
        let zoomed = abs(distance - c.lastDistance) >= 50
        guard moved || turned || zoomed else { return }

        let first = !c.hasCamera
        c.hasCamera = true
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

    /// 地点・目的地のピン
    final class PinAnnotation: MKPointAnnotation {
        var symbol = "mappin"
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var lastCenter: CLLocationCoordinate2D?
        var lastHeading: Double = 0
        var lastDistance: Double = 0
        var hasCamera = false
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?

        /// 走行軌跡(この画面を開いている間のみ・10m 間引き・最大 5000 点)
        private var trail: [CLLocationCoordinate2D] = []
        private var trailLine: MKPolyline?
        private var routeLine: MKPolyline?
        private var routeVersion = -1
        private var gpxLine: MKPolyline?
        private var gpxVersion = -1
        private var pins: [PinAnnotation] = []
        private var pinsVersion = -1
        private var pinnedDestination: Destination?

        func appendTrail(_ coord: CLLocationCoordinate2D, to map: MKMapView) {
            if let last = trail.last {
                let d = CLLocation(latitude: last.latitude, longitude: last.longitude)
                    .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                guard d >= 10 else { return }
            }
            trail.append(coord)
            if trail.count > 5000 { trail.removeFirst(trail.count - 5000) }
            guard trail.count >= 2 else { return }
            let line = MKPolyline(coordinates: trail, count: trail.count)
            if let trailLine { map.removeOverlay(trailLine) }
            trailLine = line
            map.addOverlay(line, level: .aboveRoads)
        }

        func syncRoute(_ route: MKPolyline?, version: Int, on map: MKMapView) {
            guard version != routeVersion else { return }
            routeVersion = version
            if let routeLine { map.removeOverlay(routeLine) }
            routeLine = route
            if let route { map.addOverlay(route, level: .aboveRoads) }
        }

        func syncGPX(_ coords: [CLLocationCoordinate2D], version: Int, on map: MKMapView) {
            guard version != gpxVersion else { return }
            gpxVersion = version
            if let gpxLine { map.removeOverlay(gpxLine) }
            gpxLine = nil
            guard coords.count >= 2 else { return }
            let line = MKPolyline(coordinates: coords, count: coords.count)
            gpxLine = line
            map.addOverlay(line, level: .aboveRoads)
        }

        func syncPins(_ waypoints: [Waypoint], version: Int, destination: Destination?, on map: MKMapView) {
            guard version != pinsVersion || destination != pinnedDestination else { return }
            pinsVersion = version
            pinnedDestination = destination
            map.removeAnnotations(pins)
            pins = waypoints.map { wp in
                let p = PinAnnotation()
                p.coordinate = wp.coordinate
                p.symbol = wp.kind.symbol
                return p
            }
            if let destination {
                let p = PinAnnotation()
                p.coordinate = destination.coordinate
                p.symbol = "flag.checkered"
                pins.append(p)
            }
            map.addAnnotations(pins)
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            onLongPress?(coord)
        }

        /// 線種(地図はモノクロ化されるため明度と線幅・破線で区別)
        ///   案内ルート = 白 7pt / GPX = 白 60% 破線 4pt / 走行軌跡 = グレー 4pt
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.lineCap = .round
            r.lineJoin = .round
            if line === routeLine {
                r.strokeColor = .white
                r.lineWidth = 7
            } else if line === gpxLine {
                r.strokeColor = UIColor.white.withAlphaComponent(0.6)
                r.lineWidth = 4
                r.lineDashPattern = [2, 8]
            } else {
                r.strokeColor = UIColor(white: 0.55, alpha: 0.8)
                r.lineWidth = 4
            }
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "pin")
            view.annotation = pin
            view.markerTintColor = .white
            view.glyphTintColor = .black
            view.glyphImage = UIImage(systemName: pin.symbol)
            view.displayPriority = .required
            view.canShowCallout = false
            return view
        }
    }
}
