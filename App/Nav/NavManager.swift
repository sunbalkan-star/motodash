import Foundation
import MapKit

/// 保存地点(給油・休憩・その他)
struct Waypoint: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case fuel, rest, spot

        var label: String {
            switch self {
            case .fuel: return "給油"
            case .rest: return "休憩"
            case .spot: return "地点"
            }
        }

        var symbol: String {
            switch self {
            case .fuel: return "fuelpump.fill"
            case .rest: return "cup.and.saucer.fill"
            case .spot: return "mappin"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var latitude: Double
    var longitude: Double
    var date: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 案内先
struct Destination: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// 目的地案内(Apple 経路検索 MKDirections + 取得できない時は直線コンパス)・GPX ルート表示・保存地点。
/// 位置は MotoDashApp が RideManager.location を流し込む(画面がダッシュボードでも案内は進む)。
@MainActor
final class NavManager: ObservableObject {
    // MARK: 案内
    @Published private(set) var destination: Destination?
    @Published private(set) var route: MKRoute?
    /// ルートが差し替わるたびに +1(地図のオーバーレイ更新判定用)
    @Published private(set) var routeVersion = 0
    /// 現在走行中のステップ。次の操作は steps[stepIndex + 1]
    @Published private(set) var stepIndex = 0
    @Published private(set) var distanceToManeuver: Double?
    @Published private(set) var remainingRouteMeters: Double?
    /// 残りのルート(現在地の最近傍から終点まで・間引いて最大 ≒200 点)。地図の縮尺合わせ用
    @Published private(set) var remainingRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceToDestination: Double?
    @Published private(set) var bearingToDestination: Double = 0
    @Published private(set) var arrived = false
    @Published private(set) var isRouting = false
    /// ルート取得失敗時のメッセージ(この間は直線コンパス案内)
    @Published private(set) var routeError: String?

    // MARK: GPX ルート(表示のみ)
    @Published private(set) var gpxRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var gpxName: String?
    @Published private(set) var gpxVersion = 0
    @Published private(set) var gpxError: String?

    // MARK: 保存地点
    @Published private(set) var waypoints: [Waypoint] = []
    @Published private(set) var waypointsVersion = 0

    /// 到着とみなす距離(m)
    private let arriveRadius: Double = 40
    /// ステップ終端にこの距離まで近づいたら次のステップへ(m)
    private let stepAdvanceRadius: Double = 30
    /// ルートからこの距離以上外れた測位が続いたら再検索(m)
    private let offRouteMeters: Double = 60
    private let offRouteFixes = 4
    private let rerouteInterval: TimeInterval = 15

    private var steps: [MKRoute.Step] = []
    /// 各ステップ開始時の操作アイコン(steps と同じ添字)
    private var stepSymbols: [String] = []
    /// ルート全点と、各点が属するステップ番号(最近傍探索用)
    private var routePoints: [MKMapPoint] = []
    private var routePointStep: [Int] = []
    private var lastLocation: CLLocation?
    private var offRouteCount = 0
    private var lastRouteRequest = Date.distantPast

    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var waypointsURL: URL { docs.appendingPathComponent("waypoints.json") }
    private var gpxURL: URL { docs.appendingPathComponent("Routes/active.gpx") }
    private static let destinationKey = "nav.destination"
    private static let gpxNameKey = "nav.gpxName"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.destinationKey),
           let dest = try? JSONDecoder().decode(Destination.self, from: data) {
            destination = dest
        }
        if let data = try? Data(contentsOf: waypointsURL),
           let list = try? JSONDecoder().decode([Waypoint].self, from: data) {
            waypoints = list
        }
        if let data = try? Data(contentsOf: gpxURL) {
            gpxRoute = GPXParser.parse(data)
            gpxName = UserDefaults.standard.string(forKey: Self.gpxNameKey)
        }
    }

    // MARK: - 案内操作

    func setDestination(name: String, coordinate: CLLocationCoordinate2D) {
        destination = Destination(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let data = try? JSONEncoder().encode(destination) {
            UserDefaults.standard.set(data, forKey: Self.destinationKey)
        }
        clearRoute()
        arrived = false
        routeError = nil
        lastRouteRequest = .distantPast
        if let lastLocation { update(lastLocation) }
    }

    func clearDestination() {
        destination = nil
        UserDefaults.standard.removeObject(forKey: Self.destinationKey)
        clearRoute()
        arrived = false
        routeError = nil
        distanceToDestination = nil
    }

    /// 次の操作(右左折など)の案内文。最終ステップ後は nil
    var nextInstruction: String? {
        guard steps.indices.contains(stepIndex + 1) else { return nil }
        let text = steps[stepIndex + 1].instructions
        return text.isEmpty ? nil : text
    }

    /// 次の操作のアイコン(ルート形状の折れ角から判定。言語に依存しない)
    var nextManeuverSymbol: String {
        stepSymbols.indices.contains(stepIndex + 1) ? stepSymbols[stepIndex + 1] : "flag.checkered"
    }

    // MARK: - 位置更新(1Hz)

    func update(_ loc: CLLocation) {
        lastLocation = loc
        guard let dest = destination else { return }

        let destLoc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let d = loc.distance(from: destLoc)
        distanceToDestination = d
        bearingToDestination = Geo.bearing(from: loc.coordinate, to: dest.coordinate)
        if d < arriveRadius { arrived = true }
        if arrived { return }

        guard route != nil else {
            // 未取得 or 失敗: 一定間隔で取り直す(圏外から復帰した時など)
            if !isRouting, Date().timeIntervalSince(lastRouteRequest) > 30 { requestRoute(from: loc) }
            return
        }
        trackRoute(loc)
    }

    /// ルート上の最近傍点から現在ステップ・残距離・コース外れを求める
    private func trackRoute(_ loc: CLLocation) {
        guard routePoints.count >= 2 else { return }
        let p = MKMapPoint(loc.coordinate)
        let mpp = MKMetersPerMapPointAtLatitude(loc.coordinate.latitude)

        // 現在ステップの先頭から先だけを探す(周回ルートで過去区間に戻らないように)
        let startIdx = routePointStep.firstIndex(where: { $0 >= stepIndex }) ?? 0
        var best = Double.greatestFiniteMagnitude
        var bestSeg = startIdx
        for i in max(startIdx, 1)..<routePoints.count {
            let dist = Geo.distance(p, segment: routePoints[i - 1], routePoints[i])
            if dist < best { best = dist; bestSeg = i }
        }
        let offMeters = best * mpp

        if offMeters > offRouteMeters {
            offRouteCount += 1
            if offRouteCount >= offRouteFixes, !isRouting,
               Date().timeIntervalSince(lastRouteRequest) > rerouteInterval {
                requestRoute(from: loc)
            }
        } else {
            offRouteCount = 0
            // 1Hz 測位だと高速走行中は終端 30m 圏を飛び越すため、最近傍の属するステップへも進める
            stepIndex = max(stepIndex, routePointStep[bestSeg])
        }

        while stepIndex < steps.count - 1,
              let end = steps[stepIndex].polyline.coordinates.last,
              loc.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude)) < stepAdvanceRadius {
            stepIndex += 1
        }

        if let end = steps[stepIndex].polyline.coordinates.last {
            let toEnd = loc.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            distanceToManeuver = toEnd
            remainingRouteMeters = toEnd + steps.dropFirst(stepIndex + 1).reduce(0) { $0 + $1.distance }
        }

        let every = max(1, (routePoints.count - bestSeg) / 200)
        var rest = Swift.stride(from: bestSeg, to: routePoints.count, by: every).map { routePoints[$0].coordinate }
        if let last = routePoints.last?.coordinate { rest.append(last) }
        remainingRoute = rest
    }

    private func requestRoute(from loc: CLLocation) {
        guard let dest = destination else { return }
        isRouting = true
        lastRouteRequest = Date()
        offRouteCount = 0

        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest.coordinate))
        req.transportType = .automobile
        MKDirections(request: req).calculate { [weak self] response, _ in
            let route = response?.routes.first
            Task { @MainActor in
                guard let self, self.destination == dest else { return }
                self.isRouting = false
                if let route {
                    self.applyRoute(route)
                    self.routeError = nil
                    if let last = self.lastLocation { self.update(last) }
                } else {
                    self.routeError = "ルート取得失敗(直線案内)"
                }
            }
        }
    }

    private func applyRoute(_ r: MKRoute) {
        route = r
        routeVersion += 1
        steps = r.steps
        stepIndex = 0
        routePoints = []
        routePointStep = []
        for (i, step) in steps.enumerated() {
            for c in step.polyline.coordinates {
                routePoints.append(MKMapPoint(c))
                routePointStep.append(i)
            }
        }
        stepSymbols = steps.indices.map { i in
            guard i > 0 else { return "arrow.up" }
            return Geo.maneuverSymbol(instruction: steps[i].instructions,
                                      incoming: steps[i - 1].polyline.coordinates,
                                      outgoing: steps[i].polyline.coordinates)
        }
    }

    private func clearRoute() {
        route = nil
        routeVersion += 1
        steps = []
        stepSymbols = []
        routePoints = []
        routePointStep = []
        stepIndex = 0
        distanceToManeuver = nil
        remainingRouteMeters = nil
        remainingRoute = []
        isRouting = false
        offRouteCount = 0
    }

    // MARK: - GPX ルート

    func loadGPX(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            gpxError = "ファイルを読めませんでした"
            return
        }
        let coords = GPXParser.parse(data)
        guard coords.count >= 2 else {
            gpxError = "GPX にルート点がありません"
            return
        }
        try? FileManager.default.createDirectory(at: gpxURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: gpxURL)
        gpxRoute = coords
        gpxName = url.deletingPathExtension().lastPathComponent
        UserDefaults.standard.set(gpxName, forKey: Self.gpxNameKey)
        gpxVersion += 1
        gpxError = nil
    }

    func clearGPX() {
        try? FileManager.default.removeItem(at: gpxURL)
        UserDefaults.standard.removeObject(forKey: Self.gpxNameKey)
        gpxRoute = []
        gpxName = nil
        gpxVersion += 1
    }

    // MARK: - 保存地点

    func addWaypoint(_ kind: Waypoint.Kind, at coordinate: CLLocationCoordinate2D) {
        let name = "\(kind.label) \(Self.waypointNameFormatter.string(from: Date()))"
        waypoints.insert(Waypoint(kind: kind, name: name, latitude: coordinate.latitude,
                                  longitude: coordinate.longitude, date: Date()), at: 0)
        saveWaypoints()
    }

    func deleteWaypoints(at offsets: IndexSet) {
        waypoints.remove(atOffsets: offsets)
        saveWaypoints()
    }

    private func saveWaypoints() {
        waypointsVersion += 1
        if let data = try? JSONEncoder().encode(waypoints) {
            try? data.write(to: waypointsURL, options: .atomic)
        }
    }

    private static let waypointNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}

// MARK: - 幾何ヘルパー

enum Geo {
    /// 方位角(0=北・時計回り, 度)
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 点と線分の距離(MKMapPoint 単位)
    static func distance(_ p: MKMapPoint, segment a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// 前ステップ終端の進入方向と次ステップ始端の進出方向の折れ角から、操作アイコンを決める
    /// 操作アイコン。案内文に左右の言葉があればそれを優先し(分岐で「左方向」なのに道なりは右へ曲がる、
    /// のような所で形だけだと逆向きになるため)、無ければルートの折れ角で判定する
    static func maneuverSymbol(instruction: String,
                               incoming: [CLLocationCoordinate2D],
                               outgoing: [CLLocationCoordinate2D]) -> String {
        if let symbol = symbolFromInstruction(instruction) { return symbol }
        return maneuverSymbol(incoming: incoming, outgoing: outgoing)
    }

    /// 案内文(日本語 / 英語)から左右と曲がり具合を読む。読めなければ nil
    static func symbolFromInstruction(_ text: String) -> String? {
        let t = text.lowercased()
        if t.contains("uターン") || t.contains("u-turn") || t.contains("u turn") { return "arrow.uturn.down" }
        let left = ["左折", "turn left", "sharp left"]
        let right = ["右折", "turn right", "sharp right"]
        let slightLeft = ["左方向", "左側の車線", "左に進", "keep left", "bear left", "slight left", "左寄り"]
        let slightRight = ["右方向", "右側の車線", "右に進", "keep right", "bear right", "slight right", "右寄り"]
        if left.contains { t.contains($0) } { return "arrow.turn.up.left" }
        if right.contains { t.contains($0) } { return "arrow.turn.up.right" }
        if slightLeft.contains { t.contains($0) } { return "arrow.up.left" }
        if slightRight.contains { t.contains($0) } { return "arrow.up.right" }
        return nil
    }

    static func maneuverSymbol(incoming: [CLLocationCoordinate2D],
                               outgoing: [CLLocationCoordinate2D]) -> String {
        guard let inEnd = incoming.last, let outStart = outgoing.first,
              let inFrom = point(in: incoming.reversed(), awayFrom: inEnd, meters: 15),
              let outTo = point(in: outgoing, awayFrom: outStart, meters: 15) else { return "arrow.up" }
        let inBearing = bearing(from: inFrom, to: inEnd)
        let outBearing = bearing(from: outStart, to: outTo)
        var delta = (outBearing - inBearing).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        switch abs(delta) {
        case ..<25:  return "arrow.up"
        case ..<60:  return delta > 0 ? "arrow.up.right" : "arrow.up.left"
        case ..<150: return delta > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left"
        default:     return "arrow.uturn.down"
        }
    }

    /// 列の中で基準点から指定距離以上離れた最初の点(無ければ最後の点)
    private static func point<S: Sequence>(in coords: S, awayFrom origin: CLLocationCoordinate2D,
                                           meters: Double) -> CLLocationCoordinate2D?
    where S.Element == CLLocationCoordinate2D {
        let o = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        var last: CLLocationCoordinate2D?
        for c in coords {
            last = c
            if o.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) >= meters { return c }
        }
        if let last, last.latitude != origin.latitude || last.longitude != origin.longitude { return last }
        return nil
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - GPX パーサー(trkpt / rtept、どちらも無ければ wpt)

final class GPXParser: NSObject, XMLParserDelegate {
    private var track: [CLLocationCoordinate2D] = []
    private var waypoints: [CLLocationCoordinate2D] = []

    static func parse(_ data: Data) -> [CLLocationCoordinate2D] {
        let delegate = GPXParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.track.isEmpty ? delegate.waypoints : delegate.track
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        guard let lat = attributes["lat"].flatMap(Double.init),
              let lon = attributes["lon"].flatMap(Double.init) else { return }
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        switch elementName {
        case "trkpt", "rtept": track.append(c)
        case "wpt": waypoints.append(c)
        default: break
        }
    }
}
