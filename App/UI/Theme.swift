import SwiftUI

/// 配色の種類(Design キャンバス「MotoDash 配色バリエーション」2026-10-17 の 4 案)
enum ThemeID: String, CaseIterable, Identifiable {
    case lime, arctic, stealth, sunlight

    var id: String { rawValue }
    var name: String { rawValue.uppercased() }

    var summary: String {
        switch self {
        case .lime:     return "黒地にライム、方位はシアン。標準"
        case .arctic:   return "寒色だけでまとめ、夜の長距離でも目が疲れにくい"
        case .stealth:  return "ほぼモノクロ。色が出るのは注意・危険のときだけ"
        case .sunlight: return "明るい地に濃い文字。直射日光の下で読みやすい昼間用"
        }
    }

    var palette: ThemePalette {
        switch self {
        case .lime:
            return ThemePalette(
                bg: Color(hex: 0x000000), track: Color(hex: 0x0D0F13), button: Color(hex: 0x26282D),
                borderStrong: Color(hex: 0x2C2F36), borderWeak: Color(hex: 0x23262D),
                tickMinor: Color(hex: 0x23262D), tickMajor: Color(hex: 0x3A3E46),
                accent: Color(hex: 0xA6F226), heading: Color(hex: 0x3FE0E6),
                amber: Color(hex: 0xF5B324), red: Color(hex: 0xFF4136),
                textHi: Color(hex: 0xFFFFFF), textMid: Color(hex: 0x9A9DA6),
                label: Color(hex: 0x7D818A), dim: Color(hex: 0x5C6066), isLight: false)
        case .arctic:
            return ThemePalette(
                bg: Color(hex: 0x02070C), track: Color(hex: 0x0B1520), button: Color(hex: 0x1A2633),
                borderStrong: Color(hex: 0x26394B), borderWeak: Color(hex: 0x1B2938),
                tickMinor: Color(hex: 0x1B2938), tickMajor: Color(hex: 0x33475A),
                accent: Color(hex: 0x4CC9FF), heading: Color(hex: 0x9FF0DC),
                amber: Color(hex: 0xF5B324), red: Color(hex: 0xFF4D5E),
                textHi: Color(hex: 0xF2F8FC), textMid: Color(hex: 0x94A7B8),
                label: Color(hex: 0x6F8497), dim: Color(hex: 0x52667A), isLight: false)
        case .stealth:
            return ThemePalette(
                bg: Color(hex: 0x000000), track: Color(hex: 0x121212), button: Color(hex: 0x222222),
                borderStrong: Color(hex: 0x303030), borderWeak: Color(hex: 0x232323),
                tickMinor: Color(hex: 0x232323), tickMajor: Color(hex: 0x3C3C3C),
                accent: Color(hex: 0xFFFFFF), heading: Color(hex: 0xD9D9D9),
                amber: Color(hex: 0xFFB020), red: Color(hex: 0xFF3B30),
                textHi: Color(hex: 0xFFFFFF), textMid: Color(hex: 0x8F8F8F),
                label: Color(hex: 0x6E6E6E), dim: Color(hex: 0x5A5A5A), isLight: false)
        case .sunlight:
            // 明るい地: dim(未接続・GPS ロスト)は地に近い薄いグレーにする
            return ThemePalette(
                bg: Color(hex: 0xEEF0EA), track: Color(hex: 0xD3D8CC), button: Color(hex: 0xD9DDD3),
                borderStrong: Color(hex: 0x8F968A), borderWeak: Color(hex: 0xBCC2B5),
                tickMinor: Color(hex: 0xBCC2B5), tickMajor: Color(hex: 0x8F968A),
                accent: Color(hex: 0x2E7D00), heading: Color(hex: 0x00657E),
                amber: Color(hex: 0xA35F00), red: Color(hex: 0xC8102E),
                textHi: Color(hex: 0x0A0B0A), textMid: Color(hex: 0x474C44),
                label: Color(hex: 0x5A6055), dim: Color(hex: 0x9AA095), isLight: true)
        }
    }
}

struct ThemePalette {
    let bg, track, button, borderStrong, borderWeak, tickMinor, tickMajor: Color
    /// アクセント(LIME 案ではライム)・方位(LIME 案ではシアン)
    let accent, heading: Color
    let amber, red, textHi, textMid, label, dim: Color
    /// 明るい地の配色か(地図・シートを明るいスタイルにする)
    let isLight: Bool
}

/// 表示中の配色のデザイントークン。ThemeManager が切り替え、RootView が画面を作り直して反映する。
/// フォントは Saira / IBM Plex Mono の代替として SF Pro + monospacedDigit / monospaced design を使う。
enum Palette {
    static var current: ThemePalette = ThemeID.lime.palette

    static var bg: Color           { current.bg }
    static var track: Color        { current.track }          // ゲージトラック面
    static var button: Color       { current.button }         // ボタン面
    static var borderStrong: Color { current.borderStrong }   // 枠線(TPMS / 強)
    static var borderWeak: Color   { current.borderWeak }     // 枠線(データカード / 弱)
    static var tickMinor: Color    { current.tickMinor }      // 目盛り minor
    static var tickMajor: Color    { current.tickMajor }      // 目盛り major
    static var lime: Color         { current.accent }         // アクセント・速度 / OK
    static var cyan: Color         { current.heading }        // アクセント2・方位
    static var amber: Color        { current.amber }          // 注意・未割当
    static var red: Color          { current.red }            // 危険・低圧
    static var textHi: Color       { current.textHi }         // 文字 hi
    static var textMid: Color      { current.textMid }        // 文字 mid
    static var label: Color        { current.label }          // ラベル
    static var dim: Color          { current.dim }            // 文字 dim / 未接続
    static var isLight: Bool       { current.isLight }
    static var colorScheme: ColorScheme { current.isLight ? .light : .dark }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// 状態色ロジック(ハンドオフ「状態色ロジック」より。しきい値は調整可能パラメータ)
enum StateColor {
    static var lowPressureBar: Double { TPMSThreshold.lowBar }     // これ未満=赤(通知と共通)
    static var cautionBar: Double { TPMSThreshold.cautionBar }     // これ未満=アンバー
    static var lowBatteryPercent: Int = 20    // これ以下=赤

    static var gaugeAmberKMH: Double = 80     // これ以上=アンバー
    static var gaugeRedKMH: Double = 120      // これ以上=レッド

    /// タイヤ空気圧の色。未接続(nil)は dim。
    static func pressure(_ v: Double?) -> Color {
        guard let v else { return Palette.dim }
        if v < lowPressureBar { return Palette.red }
        if v < cautionBar     { return Palette.amber }
        return Palette.textHi
    }

    static func battery(_ percent: Int) -> Color {
        percent <= lowBatteryPercent ? Palette.red : Palette.textHi
    }

    /// 速度ゲージのフィル色(速度域で変化)。~80=アクセント / 80~120=アンバー / 120~=レッド。
    static func gauge(_ kmh: Double) -> Color {
        if kmh >= gaugeRedKMH   { return Palette.red }
        if kmh >= gaugeAmberKMH { return Palette.amber }
        return Palette.lime
    }
}

/// 数字・見出し用(Saira代替): 等幅数字でガタつき防止
func motoNumberFont(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight).monospacedDigit()
}

/// ラベル・単位用(IBM Plex Mono代替): monospaced design
func motoLabelFont(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
}
