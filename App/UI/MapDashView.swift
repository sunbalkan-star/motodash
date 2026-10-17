import SwiftUI
import MapKit

/// マップ画面(ダッシュボードと左右スワイプで切替)。Apple 純正 MapKit をモノクロ化して表示する。
/// 自車は前方を広く見せるため画面下寄り(横 78% / 縦 75%)に矢印固定、地図側が進行方向に回る。
/// タップで 3D(バードビュー)→ H-UP → N-UP を切替。ピンチ / 左下の ＋− で拡大縮小(長押しで標準に戻す)。
/// 表示データは GPS(位置・速度・進行方向)/ 磁気(停車中の方位)/ TPMS のみ。
///
/// 横画面(812×375)の縦内訳: 上 8 + ステータスバー 36 + 中段 207(間 8 + 191 + 間 8) + 下ボックス 104 + 下 20 = 375。
///   中段 左=案内ボックス h76(上詰め)+ ズーム h88(下詰め、y 155〜243)、右=ボタン列 h148(停車中 44×3 + 8×2、y 52〜200)。
///   自車矢印 y≒292(h36 → 274〜310)・x≒406。下ボックスは左右の角(速度 46〜214 / TPMS 644〜794)、
///   ズームは x 46〜90 なので矢印とはどれも重ならない。
/// 縦画面(375×812)の縦内訳: セーフエリア上 + 4 + ステータスバー 36 + 中段(可変、間 8 + … + 間 8) + 下ボックス 104
///   + セーフエリア下 + 8。下ボックス上端 ≒666、ズーム ≒570〜658(x 16〜60)、自車矢印 y≒609(x≒187、591〜627)で
///   速度ボックス(x 16〜201)の上端 666 より上に収まる。
struct MapDashView: View {
    @EnvironmentObject var ride: RideManager
    @EnvironmentObject var tpms: TPMSManager
    @EnvironmentObject var nav: NavManager
    /// 表示モード(タップで 3D → H-UP → N-UP の順に切替)。次回起動時も維持
    @AppStorage("map.viewMode") private var viewMode: MapViewMode = .bird3D
    private var northUp: Bool { viewMode == .northUp }
    /// 停車中のみ入れる地図操作モード(拡大縮小・スクロール・長押しで目的地)。走り出すと自動解除
    @State private var interactive = false
    @State private var showNavSheet = false
    @State private var showPinDialog = false
    @State private var now = Date()
    /// HUD 各要素の画面上の枠(地図のピンをこの下に隠すため)
    @State private var hudRects: [CGRect] = []
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 自車位置の画面内高さ(上からの割合)。前方を広く見せるため下寄りに置く。
    /// 縦画面は自車が速度ボックス(x 16〜201)の真上に来るので、矢印下端がボックス上端 666 に掛からない 0.75 まで
    private func vehicleY(_ isPortrait: Bool) -> CGFloat { isPortrait ? 0.75 : 0.78 }
    /// 拡大縮小の倍率(カメラ距離に掛ける。小さいほど拡大)。次回起動時も維持
    @AppStorage("map.zoomScale") private var zoomScale: Double = 1
    /// ピンチ開始時の倍率
    @State private var pinchBase: Double?
    /// ピンチ中(と終了直後)はスワイプ切替を止める
    @State private var pinchLock = false
    /// 地図の実測縮尺: 1pt あたりの地上距離(m) ÷ カメラ距離(m)。地図側で測って返してもらう(初期値は目安)
    @State private var mapScaleK: Double = 0.0009
    /// 曲がり角・分岐の手前にいるか(拡大し、建物を平面にする)。境目で行き来しないよう出る時は 1.3 倍離れてから
    @State private var nearManeuver = false
    private let zoomRange: ClosedRange<Double> = 0.25...4
    private let zoomStep: Double = 1.5
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
            let vy = vehicleY(isPortrait)
            let insets = isPortrait
                ? EdgeInsets(top: safe.top + 4, leading: 16, bottom: safe.bottom + 8, trailing: 16)
                : EdgeInsets(top: 8, leading: notchOnLeading ? 46 : 18,
                             bottom: 20, trailing: notchOnLeading ? 18 : 46)

            ZStack(alignment: .topLeading) {
                // 地図は高さを (vy×2) 倍にして、カメラ中心 = 自車位置が vy に来るようにする。
                // はみ出した下側は画面外(Apple の地図ロゴ・Legal もそちらに出るので画面には映らない)
                MonoMapView(location: ride.location,
                            heading: northUp ? 0 : travelHeading,
                            distance: cameraDistance(w: w, h: h, vy: vy, isPortrait: isPortrait),
                            pitch: viewMode.pitch,
                            // 3D 時は建物も立体。ただし曲がり角の手前はルートが建物に隠れないよう平面にする
                            buildings3D: viewMode == .bird3D && !nearManeuver,
                            interactive: interactive,
                            route: nav.route?.polyline,
                            routeVersion: nav.routeVersion,
                            gpxRoute: nav.gpxRoute,
                            gpxVersion: nav.gpxVersion,
                            waypoints: nav.waypoints,
                            waypointsVersion: nav.waypointsVersion,
                            destination: nav.destination,
                            occludedRects: hudRects,
                            onLongPress: { coord in
                                nav.setDestination(name: "地図で指定", coordinate: coord)
                            },
                            onScale: { k in
                                if abs(k / mapScaleK - 1) > 0.02 { mapScaleK = k }
                            })
                    .saturation(0)
                    // 明るい地図は全体が薄く道路の縁取りが見えにくい。コントラストだけ上げると中間より明るい
                    // 縁取り(薄いグレー)は白へ寄ってしまうので、先に全体を下げてから強める。
                    // 地色(≒0.95)はほぼ白のまま、縁取り(≒0.85)は ≒0.72 まで濃くなる
                    .brightness(Palette.isLight ? -0.26 : 0)
                    .contrast(Palette.isLight ? 2.5 : 1.15)
                    .frame(width: w, height: h * vy * 2)

                // 夜間ディム(地図のみ。HUD は暗くしない)
                Color.black
                    .opacity(nightDimOpacity)
                    .frame(width: w, height: h)
                    .allowsHitTesting(false)

                if !interactive {
                    // 3D 時は地面に寝かせる(地図と同じ角度で奥へ倒す)
                    VehicleArrow()
                        .rotationEffect(.degrees(northUp ? travelHeading : 0))
                        .rotation3DEffect(.degrees(viewMode.pitch), axis: (x: 1, y: 0, z: 0),
                                          perspective: 0.5)
                        .position(x: w / 2, y: h * vy)
                        .allowsHitTesting(false)
                }

                hud(isPortrait)
                    .padding(insets)
                    .frame(width: w, height: h)
            }
            .coordinateSpace(name: HUDFrameKey.space)
            .onPreferenceChange(HUDFrameKey.self) { hudRects = $0 }
            // ZStack は地図(高さ 1.3h)の分だけ画面より縦に大きい。既定の中央揃えだと全体が 0.15h 上にずれ、
            // 上ピル・ボタン・下ボックス・自車が上に押し出されるため、画面の上端に揃える
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { if !interactive { viewMode = viewMode.next } }
            // ピンチで拡大縮小(走行中も可。操作モード中は地図自身のピンチに任せる)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        guard !interactive, scale > 0 else { return }
                        let base = pinchBase ?? zoomScale
                        pinchBase = base
                        pinchLock = true
                        zoomScale = clampZoom(base / Double(scale))
                    }
                    .onEnded { _ in
                        pinchBase = nil
                        // 指を離した直後に画面側のスワイプ判定が走るので、少し遅れて解除する
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pinchLock = false }
                    }
            )
            .persistentSystemOverlays(isPortrait ? .automatic : .hidden)
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(Palette.colorScheme)
        .statusBarHidden(true)
        // 操作モード中・ピンチ中は左右スワイプの画面切替を止める(2本指の移動で誤って切り替わらないように)
        .preference(key: SwipeLockKey.self, value: interactive || pinchLock)
        .onReceive(ticker) {
            now = $0
            updateNearManeuver()
        }
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
            topBar(isPortrait)
            // 中段: 左列 = 案内ボックス(上詰め)+ ズーム(下詰め) / 右列 = ボタン列
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    if nav.destination != nil {
                        navBox
                            .reportHUDFrame()
                    }
                    Spacer(minLength: 0)
                    zoomControl
                        .reportHUDFrame()
                }
                .frame(maxWidth: isPortrait ? .infinity : 250, maxHeight: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                controls
                    .reportHUDFrame()
            }
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 8) {
                speedBox
                    .frame(maxWidth: isPortrait ? .infinity : 168, alignment: .leading)
                    .reportHUDFrame()
                if !isPortrait { Spacer(minLength: 0) }
                tpmsBox
                    .reportHUDFrame()
            }
        }
    }

    /// 上ピル列(h36)。横画面は方位を画面中央に固定(左右は等幅の可変枠)。
    /// 縦画面は左ピル(GPS LOST + MODE で最大 ≒136pt)が中央固定だと方位ピルに重なるため、
    /// 左ピル | 方位 | 時刻 を間に Spacer を挟んで並べる(343pt に対し合計 ≒300pt)
    @ViewBuilder
    private func topBar(_ isPortrait: Bool) -> some View {
        if isPortrait {
            HStack(spacing: 6) {
                leftPills
                Spacer(minLength: 0)
                compassPill
                Spacer(minLength: 0)
                clockPill
            }
            .frame(height: 36)
        } else {
            HStack(spacing: 0) {
                leftPills
                    .frame(maxWidth: .infinity, alignment: .leading)
                compassPill
                clockPill
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 36)
        }
    }

    /// GPS ピル + 表示モードピル("3D"/"H-UP"/"N-UP"、操作中は "MOVE" ライム)
    private var leftPills: some View {
        HStack(spacing: 6) {
            gpsPill
            Text(interactive ? "MOVE" : viewMode.label)
                .font(motoLabelFont(9, .semibold))
                .tracking(1.5)
                .foregroundColor(interactive ? Palette.lime : Palette.textHi)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Palette.bg.opacity(0.85)))
                .overlay(Capsule().stroke(interactive ? Palette.lime : Palette.borderStrong, lineWidth: 1))
        }
        .fixedSize()
        .reportHUDFrame()
    }

    private var compassPill: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(cardinal(ride.headingDegrees))
                .font(motoNumberFont(20, .heavy))
            Text(String(format: "%03d°", Int(ride.headingDegrees.rounded()) % 360))
                .font(motoNumberFont(14, .bold))
        }
        .foregroundColor(Palette.cyan)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Palette.bg.opacity(0.85)))
        .overlay(Capsule().stroke(Palette.borderStrong, lineWidth: 1))
        .reportHUDFrame()
    }

    private var clockPill: some View {
        Text(Self.clockFormatter.string(from: now))
            .font(motoNumberFont(17, .bold))
            .foregroundColor(Palette.textHi)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Palette.bg.opacity(0.85)))
            .overlay(Capsule().stroke(Palette.borderStrong, lineWidth: 1))
            .reportHUDFrame()
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
            NavIcon(screenUpHeading: northUp ? 0 : travelHeading)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(nav.primaryText)
                    .font(motoNumberFont(26, .heavy))
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(height: 30)
                Text(nav.secondaryText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Palette.textHi)
                    .lineLimit(1)
                    .frame(height: 15)
                label(nav.tertiaryText, color: nav.tertiaryIsWarning ? Palette.amber : Palette.label)
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

    // MARK: - ズーム(左下: ＋ / − を縦に連結した 44×88。長押しで標準倍率に戻す)

    private var zoomControl: some View {
        VStack(spacing: 0) {
            zoomButton("plus", label: "拡大") { zoomScale = clampZoom(zoomScale / zoomStep) }
                .disabled(zoomScale <= zoomRange.lowerBound)
            Rectangle()
                .fill(Palette.borderStrong)
                .frame(width: 28, height: 1)
            zoomButton("minus", label: "縮小") { zoomScale = clampZoom(zoomScale * zoomStep) }
                .disabled(zoomScale >= zoomRange.upperBound)
        }
        .frame(width: 44, height: 88)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bg.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.borderStrong, lineWidth: 1.5))
        .onLongPressGesture { zoomScale = 1 }
    }

    private func zoomButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Palette.textHi)
                .frame(width: 44, height: 43.5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func clampZoom(_ v: Double) -> Double {
        min(max(v, zoomRange.lowerBound), zoomRange.upperBound)
    }

    // MARK: - ボタン列(右上: ナビ / 地点保存 / 地図操作 or 現在地へ戻る)

    private var controls: some View {
        VStack(spacing: 8) {
            mapButton("magnifyingglass") { showNavSheet = true }
            mapButton("mappin.and.ellipse") { showPinDialog = true }
                .disabled(ride.location == nil)
            if interactive {
                mapButton("location.fill", tint: Palette.lime, border: Palette.lime) { interactive = false }
            } else if ride.speedKMH < stoppedKMH {
                mapButton("arrow.up.and.down.and.arrow.left.and.right") { interactive = true }
            }
        }
    }

    private func mapButton(_ symbol: String, tint: Color = Palette.textHi,
                           border: Color = Palette.borderStrong,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.bg.opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1.5))
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
            label("KM/H", size: 11, color: Palette.textMid)
                .frame(height: 14)
        }
        .padding(.horizontal, 16)
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
            label(title, size: 11, color: Palette.label)
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

    private func label(_ text: String, size: CGFloat = 10, color: Color) -> some View {
        Text(text)
            .font(motoLabelFont(size, .semibold))
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
    private var travelHeading: Double { ride.travelHeading }

    /// カメラから自車までの距離(= 縮尺)。
    ///   通常: 速度連動。2D: 0km/h=500m 〜 120km/h 以上=2400m / 3D: 斜めで前方が遠くまで見えるため 350m 〜 1550m
    ///   案内中: 残りのルート全体が画面の空きに収まる縮尺。曲がり角・分岐が近づいたら通常の 0.7 倍まで寄る
    ///   これにユーザーの拡大縮小倍率(0.25〜4)を掛け、150m〜300km に収める
    private func cameraDistance(w: CGFloat, h: CGFloat, vy: CGFloat, isPortrait: Bool) -> Double {
        let speedBase = viewMode == .bird3D
            ? min(1550, 350 + ride.speedKMH * 10)
            : min(2400, 500 + ride.speedKMH * 16)
        var base = speedBase
        if let fit = routeFitDistance(w: w, h: h, vy: vy, isPortrait: isPortrait) {
            base = nearManeuver ? speedBase * 0.7 : max(fit, speedBase * 0.7)
        }
        return min(300_000, max(150, base * zoomScale))
    }

    /// 次の曲がり角・分岐(ステップの終端)の手前判定(1 秒ごと)。手前 250m か 15 秒で着く距離の長い方で入り、
    /// その 1.3 倍より離れるか、曲がり終えて次のステップへ進んだら出る
    private func updateNearManeuver() {
        guard nav.route != nil, !nav.arrived, let d = nav.distanceToManeuver else {
            if nearManeuver { nearManeuver = false }
            return
        }
        let enter = max(250, ride.speedKMH / 3.6 * 15)
        let next = nearManeuver ? d < enter * 1.3 : d < enter
        if next != nearManeuver { nearManeuver = next }
    }

    /// 残りのルート(ルートが無ければ目的地)が自車の周りの空きに収まるカメラ距離。案内していなければ nil。
    /// 空き = 上はステータスバー、下は下ボックス、左右は端 40pt を除いた範囲(地図の向きに合わせて回して判定)
    private func routeFitDistance(w: CGFloat, h: CGFloat, vy: CGFloat, isPortrait: Bool) -> Double? {
        guard nav.destination != nil, !nav.arrived, let loc = ride.location else { return nil }
        let points = nav.remainingRoute.isEmpty
            ? (nav.destination.map { [$0.coordinate] } ?? [])
            : nav.remainingRoute
        guard !points.isEmpty else { return nil }
        let up = Double(h * vy) - (isPortrait ? 110 : 60)
        let down = max(40, Double(h * (1 - vy)) - (isPortrait ? 150 : 130))
        let side = Double(w / 2) - 40
        let heading = northUp ? 0 : travelHeading
        var metersPerPoint = 0.0
        for c in points {
            let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            let rel = (Geo.bearing(from: loc.coordinate, to: c) - heading) * .pi / 180
            let forward = d * cos(rel), right = d * sin(rel)
            metersPerPoint = max(metersPerPoint, abs(right) / side,
                                 forward >= 0 ? forward / up : -forward / down)
        }
        return metersPerPoint / mapScaleK
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

// MARK: - HUD の枠の収集(ピンの重なり判定用)

/// HUD 要素の枠をマップ画面の座標系(= MKMapView の座標系。地図は画面左上に原点を合わせて置いている)で集める
struct HUDFrameKey: PreferenceKey {
    static let space = "mapScreen"
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func reportHUDFrame() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: HUDFrameKey.self,
                                   value: [g.frame(in: .named(HUDFrameKey.space))])
        })
    }
}

// MARK: - 表示モード

enum MapViewMode: String, CaseIterable {
    /// バードビュー: 進行方向が上・斜め見下ろし・建物/地形の立体表示(曲がり角の手前だけ平面)
    case bird3D
    case headingUp
    case northUp

    var label: String {
        switch self {
        case .bird3D: return "3D"
        case .headingUp: return "H-UP"
        case .northUp: return "N-UP"
        }
    }

    /// カメラの傾き(度)。0 = 真上から
    var pitch: Double { self == .bird3D ? 55 : 0 }

    var next: MapViewMode {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

// MARK: - 自車矢印(ライム・黒縁 2pt、36×36)

struct VehicleArrow: View {
    var body: some View {
        ZStack {
            ArrowShape().fill(Palette.lime)
            ArrowShape().stroke(Palette.bg, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(width: 36, height: 36)
    }
}

/// 矢じり形(36×36 基準: 先端 18,3 / 右下 31,31 / 内側 18,24 / 左下 5,31)
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 36, sy = rect.height / 36
        var p = Path()
        p.move(to: CGPoint(x: 18 * sx, y: 3 * sy))
        p.addLine(to: CGPoint(x: 31 * sx, y: 31 * sy))
        p.addLine(to: CGPoint(x: 18 * sx, y: 24 * sy))
        p.addLine(to: CGPoint(x: 5 * sx, y: 31 * sy))
        p.closeSubpath()
        return p
    }
}

// MARK: - MKMapView ラッパー(モノクロ・カメラ追従・走行軌跡・案内ルート・GPX・地点)

struct MonoMapView: UIViewRepresentable {
    var location: CLLocation?
    var heading: Double
    var distance: Double
    /// カメラの傾き(度)
    var pitch: Double
    /// 建物・地形を立体で描くか(false は平面。ルートが建物の陰に隠れない)
    var buildings3D: Bool
    /// true=停車中の操作モード(追従を止め、拡大縮小・スクロール・長押しを許可)
    var interactive: Bool
    var route: MKPolyline?
    var routeVersion: Int
    var gpxRoute: [CLLocationCoordinate2D]
    var gpxVersion: Int
    var waypoints: [Waypoint]
    var waypointsVersion: Int
    var destination: Destination?
    /// HUD に覆われる画面上の枠。ここに掛かるピンは隠す
    var occludedRects: [CGRect]
    var onLongPress: (CLLocationCoordinate2D) -> Void
    /// 実測の縮尺(1pt あたりの地上距離 ÷ カメラ距離)を返す。案内中の縮尺合わせに使う
    var onScale: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        // 建物は 1 棟ずつは変えられない(色も不可)ため、地図全体で立体 / 平面を切り替える
        map.preferredConfiguration = Self.configuration(buildings3D: buildings3D)
        map.showsBuildings = buildings3D
        context.coordinator.buildings3D = buildings3D
        // 明るい配色(SUNLIGHT)では地図も明るいスタイル。配色が変わると画面ごと作り直されるので作成時だけでよい
        map.overrideUserInterfaceStyle = Palette.isLight ? .light : .dark
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        // false だとカメラの pitch 自体が無視される(常に真上から)ため有効にしておく
        map.isPitchEnabled = true
        // MapKit はレイアウト余白・セーフエリアを「隠れた領域」とみなし、カメラ中心をその内側の中央に置く。
        // 余白があると自車(フレーム中央)と地図上の現在地がずれるため、余白は常にゼロにする
        map.insetsLayoutMarginsFromSafeArea = false
        map.layoutMargins = .zero
        map.delegate = context.coordinator
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleLongPress(_:)))
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onLongPress = onLongPress
        c.onScale = onScale
        // 走行中はタッチを SwiftUI 側(スワイプ切替・タップでノースアップ)へ通す
        map.isUserInteractionEnabled = interactive
        map.showsUserLocation = interactive   // 操作モード中は自車矢印の代わりに青点(グレー)で現在地を示す
        if c.buildings3D != buildings3D {
            c.buildings3D = buildings3D
            map.preferredConfiguration = Self.configuration(buildings3D: buildings3D)
            map.showsBuildings = buildings3D
        }

        c.syncRoute(route, version: routeVersion, on: map)
        c.syncGPX(gpxRoute, version: gpxVersion, on: map)
        c.syncPins(waypoints, version: waypointsVersion, destination: destination, on: map)
        if c.occludedRects != occludedRects {
            c.occludedRects = occludedRects
            c.updatePinVisibility(on: map)
        }

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
        let zoomed = c.lastDistance <= 0 || abs(distance / c.lastDistance - 1) >= 0.03
        let tilted = pitch != c.lastPitch
        guard moved || turned || zoomed || tilted else { return }

        let first = !c.hasCamera
        c.hasCamera = true
        c.lastCenter = location.coordinate
        c.lastHeading = heading
        c.lastDistance = distance
        c.lastPitch = pitch
        let camera = MKMapCamera(lookingAtCenter: location.coordinate,
                                 fromDistance: distance, pitch: pitch, heading: heading)
        map.setCamera(camera, animated: !first)
    }

    /// モノクロ用の地図設定。buildings3D=建物・地形の立体表示(対応地域のみ。非対応地域は平面のまま)。
    /// 明るい配色では muted だと道路が背景に溶けるので標準の強調にする
    private static func configuration(buildings3D: Bool) -> MKStandardMapConfiguration {
        let config = MKStandardMapConfiguration(elevationStyle: buildings3D ? .realistic : .flat,
                                                emphasisStyle: Palette.isLight ? .default : .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        return config
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
        var lastPitch: Double = -1
        var hasCamera = false
        var buildings3D = false
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var onScale: ((Double) -> Void)?
        var occludedRects: [CGRect] = []

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
        ///   案内ルート = 文字色(暗い地図では白・明るい地図では黒)7pt / GPX = 同 60% 破線 4pt / 走行軌跡 = グレー 4pt
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKPolylineRenderer(polyline: line)
            r.lineCap = .round
            r.lineJoin = .round
            let ink = UIColor(Palette.textHi)
            if line === routeLine {
                r.strokeColor = ink
                r.lineWidth = 7
            } else if line === gpxLine {
                r.strokeColor = ink.withAlphaComponent(0.6)
                r.lineWidth = 4
                r.lineDashPattern = [2, 8]
            } else {
                r.strokeColor = UIColor(white: 0.55, alpha: 0.8)
                r.lineWidth = 4
            }
            return r
        }

        /// HUD(ボタン・案内・速度・TPMS・上部ピル)に掛かるピンを隠す。少しでも重なれば隠し、外れたら戻す
        func updatePinVisibility(on map: MKMapView) {
            for pin in pins {
                guard let view = map.view(for: pin) else { continue }
                // 注釈ビューは内部のコンテナに載るため、地図の座標系へ変換してから比べる
                let frame = view.convert(view.bounds, to: map)
                let hidden = occludedRects.contains { $0.insetBy(dx: -4, dy: -4).intersects(frame) }
                let alpha: CGFloat = hidden ? 0 : 1
                if view.alpha != alpha {
                    UIView.animate(withDuration: 0.15) { view.alpha = alpha }
                }
            }
        }

        /// カメラ追従のアニメーション中も呼ばれるため、ピンが HUD の下へ流れ込んだ時点で隠せる
        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updatePinVisibility(on: mapView)
        }

        /// 動き終わるたびに縮尺を実測する: 画面中央(= 自車)の左右 100pt の地上距離 ÷ カメラ距離
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let distance = mapView.camera.centerCoordinateDistance
            guard distance > 0, mapView.bounds.width > 200 else { return }
            let mid = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY)
            let a = mapView.convert(CGPoint(x: mid.x - 50, y: mid.y), toCoordinateFrom: mapView)
            let b = mapView.convert(CGPoint(x: mid.x + 50, y: mid.y), toCoordinateFrom: mapView)
            let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let k = meters / 100 / distance
            guard k.isFinite, k > 0 else { return }
            // SwiftUI の更新中に状態を書き換えないよう次の周回で返す
            DispatchQueue.main.async { [weak self] in self?.onScale?(k) }
        }

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            updatePinVisibility(on: mapView)
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
