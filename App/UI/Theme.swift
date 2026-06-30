import SwiftUI

/// デザインハンドオフ(MotoDash dashboard, hifi)のデザイントークン。
/// 色は全てハンドオフ表のHex。フォントはSaira/IBM Plex Monoの代替として
/// SF Pro + monospacedDigit / monospaced design を使う。
enum Palette {
    static let bg           = Color.black               // #000000
    static let track        = Color(hex: 0x0D0F13)      // ゲージトラック面
    static let button       = Color(hex: 0x26282D)      // ボタン面
    static let borderStrong = Color(hex: 0x2C2F36)      // 枠線(TPMS / 強)
    static let borderWeak   = Color(hex: 0x23262D)      // 枠線(データカード / 弱)
    static let tickMinor    = Color(hex: 0x23262D)      // 目盛り minor
    static let tickMajor    = Color(hex: 0x3A3E46)      // 目盛り major
    static let lime         = Color(hex: 0xA6F226)      // アクセント・速度 / OK
    static let cyan         = Color(hex: 0x3FE0E6)      // アクセント2・方位
    static let amber        = Color(hex: 0xF5B324)      // 注意・未割当
    static let red          = Color(hex: 0xFF4136)      // 危険・低圧
    static let textHi       = Color.white               // 文字 hi
    static let textMid      = Color(hex: 0x9A9DA6)      // 文字 mid
    static let label        = Color(hex: 0x7D818A)      // ラベル
    static let dim          = Color(hex: 0x5C6066)      // 文字 dim / 未接続
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
    static var lowPressureBar: Double = 2.0   // これ未満=赤
    static var cautionBar: Double = 2.2       // これ未満=アンバー
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

    /// 速度ゲージのフィル色(速度域で変化)。~80=ライム / 80~120=アンバー / 120~=レッド。
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
