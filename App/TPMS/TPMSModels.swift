import Foundation

// MARK: - データモデル

enum WheelPosition: String, CaseIterable {
    case front = "FRONT"
    case rear  = "REAR"
}

/// TPMSセンサー1個分の読み取り値
struct TPMSReading {
    let sensorID: UUID          // CoreBluetoothのperipheral identifier
    let pressureBar: Double
    let temperatureC: Double
    let batteryPercent: Int?    // センサー電池残量(取得できる機種のみ)
    let timestamp: Date

    /// この秒数を超えて更新が無ければ「信号ロスト」扱い
    static let staleAfter: TimeInterval = 120
    var isStale: Bool { Date().timeIntervalSince(timestamp) > Self.staleAfter }
}

// MARK: - パーサープロトコル(ここがプラグインポイント)

/// BLEアドバタイズからTPMS値を取り出すパーサーのインターフェース。
/// センサーを購入したら、その機種のパケット形式に合わせた実装を1つ書いて
/// `TPMSManager.parsers` に追加するだけで連動する。
protocol TPMSAdvertisementParser {
    /// パーサー名(デバッグ表示用)
    var name: String { get }

    /// 解釈できないパケットなら nil を返す(次のパーサーに委ねられる)
    func parse(sensorID: UUID,
               localName: String?,
               manufacturerData: Data?) -> TPMSReading?
}

// MARK: - 実装例: 中華系格安BLE TPMSの一般的なフォーマット

/// バルブキャップ型の格安センサー(デバイス名 "TPMS1_xxxxxx" 等)で
/// 広く使われている18バイトのManufacturer Dataフォーマット。
///
/// ⚠️ 機種依存。購入後に必ずスニファー画面で実パケットを確認し、
///    オフセットが合わなければ調整するか、新しいパーサーを書くこと。
///
/// 想定レイアウト(リトルエンディアン):
///   [0-1]   Company ID
///   [2-7]   センサーアドレス
///   [8-11]  空気圧 (Pa, UInt32) → /100000 で bar
///   [12-15] 温度 (0.01℃, Int32)
///   [16]    電池残量 (%)
///   [17]    アラームフラグ
struct CommonChineseTPMSParser: TPMSAdvertisementParser {
    let name = "CommonChineseTPMS"

    func parse(sensorID: UUID,
               localName: String?,
               manufacturerData: Data?) -> TPMSReading? {
        // デバイス名でざっくり判定("TPMS" を含む名前のみ対象)
        guard let localName, localName.uppercased().contains("TPMS") else { return nil }
        guard let data = manufacturerData, data.count >= 18 else { return nil }

        let pressurePa = data.readUInt32LE(at: 8)
        let tempCenti  = data.readInt32LE(at: 12)
        let battery    = Int(data[data.startIndex + 16])

        let bar = Double(pressurePa) / 100_000.0
        let temp = Double(tempCenti) / 100.0

        // 物理的にあり得ない値はパース失敗とみなす(誤検出ガード)
        guard (0.0...10.0).contains(bar), (-40.0...150.0).contains(temp) else { return nil }

        return TPMSReading(
            sensorID: sensorID,
            pressureBar: bar,
            temperatureC: temp,
            batteryPercent: (0...100).contains(battery) ? battery : nil,
            timestamp: Date()
        )
    }
}

// MARK: - Data読み取りヘルパー

extension Data {
    func readUInt32LE(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        guard i + 4 <= endIndex else { return 0 }
        return UInt32(self[i])
            | UInt32(self[i + 1]) << 8
            | UInt32(self[i + 2]) << 16
            | UInt32(self[i + 3]) << 24
    }

    func readInt32LE(at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32LE(at: offset))
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
