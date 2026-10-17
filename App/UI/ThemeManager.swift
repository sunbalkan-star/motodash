import SwiftUI
import CoreLocation

enum ThemeMode: String, CaseIterable, Identifiable {
    case manual, auto
    var id: String { rawValue }
    var label: String { self == .manual ? "手動" : "時間帯で自動" }
}

enum ThemeAutoBasis: String, CaseIterable, Identifiable {
    case sun, clock
    var id: String { rawValue }
    var label: String { self == .sun ? "日の出・日の入り" : "時刻を指定" }
}

/// 配色の選択と自動切替(手動 / 昼夜で自動)。設定は UserDefaults に保存
@MainActor
final class ThemeManager: ObservableObject {
    /// 表示中の配色。変わると RootView が画面を作り直す
    @Published private(set) var current: ThemeID
    @Published private(set) var isDaytime = true

    @Published var mode: ThemeMode { didSet { save(); refresh() } }
    @Published var manualTheme: ThemeID { didSet { save(); refresh() } }
    @Published var dayTheme: ThemeID { didSet { save(); refresh() } }
    @Published var nightTheme: ThemeID { didSet { save(); refresh() } }
    @Published var basis: ThemeAutoBasis { didSet { save(); refresh() } }
    /// 時刻指定の切替時刻(0:00 からの分)
    @Published var dayStartMinutes: Int { didSet { save(); refresh() } }
    @Published var nightStartMinutes: Int { didSet { save(); refresh() } }

    /// 太陽の中心がこの高度(度)を上回る間を昼とする。-0.833° = 日の出・日の入り(大気差込み)
    private let sunriseAltitude = -0.833
    private var location: CLLocation?
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        mode = ThemeMode(rawValue: d.string(forKey: "theme.mode") ?? "") ?? .manual
        manualTheme = ThemeID(rawValue: d.string(forKey: "theme.manual") ?? "") ?? .lime
        dayTheme = ThemeID(rawValue: d.string(forKey: "theme.day") ?? "") ?? .sunlight
        nightTheme = ThemeID(rawValue: d.string(forKey: "theme.night") ?? "") ?? .lime
        basis = ThemeAutoBasis(rawValue: d.string(forKey: "theme.basis") ?? "") ?? .sun
        dayStartMinutes = d.object(forKey: "theme.dayStart") as? Int ?? 6 * 60
        nightStartMinutes = d.object(forKey: "theme.nightStart") as? Int ?? 18 * 60
        current = .lime
        refresh()
        // 昼夜の切替を拾うため 1 分ごとに判定(切り替わった時だけ画面を作り直す)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 日の出・日の入りの判定に使う現在地。最初の測位でだけ判定し直す(以降は 1 分ごとの判定で十分)
    func update(location: CLLocation) {
        let first = self.location == nil
        self.location = location
        if first { refresh() }
    }

    /// 日の出・日の入り基準なのに現在地が無い(GPS 未測位)ときは時刻指定で代用する
    var usesClockFallback: Bool { basis == .sun && location == nil }

    func refresh(now: Date = Date()) {
        isDaytime = computeDaytime(now)
        let next: ThemeID
        switch mode {
        case .manual: next = manualTheme
        case .auto:   next = isDaytime ? dayTheme : nightTheme
        }
        guard next != current else { return }
        // 画面の作り直しより先にトークンを差し替える
        Palette.current = next.palette
        current = next
    }

    private func computeDaytime(_ now: Date) -> Bool {
        if basis == .sun, let c = location?.coordinate {
            return SolarPosition.altitude(at: now, latitude: c.latitude, longitude: c.longitude) > sunriseAltitude
        }
        let cal = Calendar.current
        let m = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if dayStartMinutes <= nightStartMinutes {
            return m >= dayStartMinutes && m < nightStartMinutes
        }
        // 昼の開始が夜の開始より遅い(日付をまたぐ)設定
        return m >= dayStartMinutes || m < nightStartMinutes
    }

    private func save() {
        defaults.set(mode.rawValue, forKey: "theme.mode")
        defaults.set(manualTheme.rawValue, forKey: "theme.manual")
        defaults.set(dayTheme.rawValue, forKey: "theme.day")
        defaults.set(nightTheme.rawValue, forKey: "theme.night")
        defaults.set(basis.rawValue, forKey: "theme.basis")
        defaults.set(dayStartMinutes, forKey: "theme.dayStart")
        defaults.set(nightStartMinutes, forKey: "theme.nightStart")
    }
}
