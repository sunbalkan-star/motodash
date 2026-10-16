import SwiftUI

// マップ画面とダッシュボードで共有する案内表示(アイコン・文言)

extension NavManager {
    /// 1km 未満は 10m 単位 "350 m"、以上は "12.4 km"
    static func distanceText(_ m: Double) -> String {
        m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000)
    }

    /// 大きく出す距離: ルートあり=次の操作まで / ルートなし=目的地までの直線距離
    var primaryText: String {
        if arrived { return "到着" }
        if route != nil, let d = distanceToManeuver { return Self.distanceText(d) }
        return distanceToDestination.map(Self.distanceText) ?? "--"
    }

    /// 案内文(ルートなし・到着時は目的地名)
    var secondaryText: String {
        let name = destination?.name ?? ""
        if arrived || route == nil { return name }
        return nextInstruction ?? name
    }

    /// 補足: 残り距離 / 検索中 / 失敗 / 直線距離
    var tertiaryText: String {
        if arrived { return "TAP TO END" }
        if isRouting { return "ROUTING…" }
        if let err = routeError { return err }
        if let r = remainingRouteMeters { return "残り \(Self.distanceText(r))" }
        return "直線距離"
    }

    var tertiaryIsWarning: Bool { routeError != nil }
}

/// 案内アイコン: ルートあり=次の操作 / ルートなし=目的地方向の矢印(直線コンパス) / 到着=旗
struct NavIcon: View {
    @EnvironmentObject var nav: NavManager
    /// 画面の上が向いている方位(進行方向が上なら進行方向、北が上なら 0)
    var screenUpHeading: Double
    var size: CGFloat = 32

    var body: some View {
        Group {
            if nav.arrived {
                Image(systemName: "flag.checkered")
                    .font(.system(size: size * 0.94, weight: .bold))
            } else if nav.route != nil {
                Image(systemName: nav.nextManeuverSymbol)
                    .font(.system(size: size, weight: .bold))
            } else {
                Image(systemName: "location.north.fill")
                    .font(.system(size: size * 0.94, weight: .bold))
                    .rotationEffect(.degrees(nav.bearingToDestination - screenUpHeading))
            }
        }
        .foregroundColor(Palette.lime)
    }
}
