import Foundation
import CoreBluetooth
import UserNotifications

/// スニファー画面用: 受信した生パケットの記録
struct RawBLEPacket: Identifiable {
    let id: UUID                // peripheral identifier
    var localName: String?
    var manufacturerHex: String
    var rssi: Int
    var lastSeen: Date
}

/// スニファー画面用の生パケット記録。TPMSManager とは別の ObservableObject にして、
/// 周囲の全BLE機器の受信でダッシュボードが再描画されないようにする。
final class BLESniffer: ObservableObject {
    @Published private(set) var packets: [RawBLEPacket] = []

    /// スニファー画面の表示中のみ記録する(非表示にしたら一覧を捨ててメモリも解放)
    var isActive = false {
        didSet { if !isActive { packets.removeAll() } }
    }

    /// この秒数受信が無いデバイスは一覧から外す
    private let expireAfter: TimeInterval = 30

    func record(id: UUID, name: String?, hex: String, rssi: Int) {
        guard isActive else { return }
        let now = Date()
        var list = packets.filter { now.timeIntervalSince($0.lastSeen) <= expireAfter }
        if let idx = list.firstIndex(where: { $0.id == id }) {
            list[idx].localName = name ?? list[idx].localName
            list[idx].manufacturerHex = hex
            list[idx].rssi = rssi
            list[idx].lastSeen = now
        } else {
            list.append(RawBLEPacket(
                id: id, localName: name,
                manufacturerHex: hex, rssi: rssi, lastSeen: now
            ))
        }
        list.sort { $0.rssi > $1.rssi }
        packets = list   // publish は1受信につき1回
    }
}

/// TPMSの中枢。BLEスキャン → パーサー群に流す → 前後輪に振り分け。
/// センサー未購入でもスニファーとして動き、購入後は割当てるだけで連動する。
final class TPMSManager: NSObject, ObservableObject {
    // MARK: パーサー登録(プラグインポイント)
    /// 新しいセンサーに対応する時はここに実装を追加するだけ
    private let parsers: [TPMSAdvertisementParser] = [
        CommonChineseTPMSParser(),
        // 例: MySensorXYZParser(),
    ]

    // MARK: Published状態
    @Published var bluetoothReady = false
    @Published var readings: [WheelPosition: TPMSReading] = [:]
    @Published var isScanning = false

    /// スニファー画面用(別オブジェクト。ここの更新はダッシュボードを再描画しない)
    let sniffer = BLESniffer()

    // MARK: 前後輪へのセンサー割当(UserDefaultsに永続化)
    @Published var assignments: [WheelPosition: UUID] = [:] {
        didSet { saveAssignments() }
    }

    private var central: CBCentralManager!
    private var lastAlertDate: [WheelPosition: Date] = [:]

    /// アラートの再通知間隔(秒)
    private let alertCooldown: TimeInterval = 10 * 60
    /// 値が変わらない受信はこの秒数まで反映を省く(再描画抑制。staleAfter より十分短く)
    private let readingRefreshInterval: TimeInterval = 10

    override init() {
        super.init()
        loadAssignments()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn, !isScanning else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
    }

    func assign(_ sensorID: UUID, to position: WheelPosition) {
        // 同じセンサーが別ポジションに割当て済みなら外す
        for (pos, id) in assignments where id == sensorID {
            assignments[pos] = nil
            readings[pos] = nil
        }
        // 付け替え時は前のセンサーの値を残さない
        if assignments[position] != sensorID { readings[position] = nil }
        assignments[position] = sensorID
    }

    func clearAssignment(_ position: WheelPosition) {
        assignments[position] = nil
        readings[position] = nil
    }

    // MARK: - 永続化

    private static let assignmentsKey = "tpmsAssignments"

    private func saveAssignments() {
        let dict = assignments.reduce(into: [String: String]()) {
            $0[$1.key.rawValue] = $1.value.uuidString
        }
        UserDefaults.standard.set(dict, forKey: Self.assignmentsKey)
    }

    private func loadAssignments() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.assignmentsKey)
                as? [String: String] else { return }
        for (key, value) in dict {
            if let pos = WheelPosition(rawValue: key), let id = UUID(uuidString: value) {
                assignments[pos] = id
            }
        }
    }

    // MARK: - 低圧アラート(ローカル通知)

    private func checkLowPressure(_ reading: TPMSReading, position: WheelPosition) {
        let threshold = TPMSThreshold.lowBar
        guard reading.pressureBar < threshold else { return }
        let last = lastAlertDate[position] ?? .distantPast
        guard Date().timeIntervalSince(last) > alertCooldown else { return }
        lastAlertDate[position] = Date()

        let content = UNMutableNotificationContent()
        content.title = "⚠️ タイヤ空気圧 低下"
        content.body = String(
            format: "%@: %.2f bar(閾値 %.2f bar)",
            position == .front ? "フロント" : "リア",
            reading.pressureBar, threshold
        )
        content.sound = .defaultCritical
        let request = UNNotificationRequest(
            identifier: "lowPressure-\(position.rawValue)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - CBCentralManagerDelegate

extension TPMSManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothReady = central.state == .poweredOn
        if bluetoothReady { startScanning() }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let sensorID = peripheral.identifier
        let localName = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data

        // 1) スニファー記録(画面表示中のみ・Manufacturer Data持ちのみ)
        if sniffer.isActive, let mfgData {
            sniffer.record(
                id: sensorID, name: localName,
                hex: mfgData.hexString, rssi: RSSI.intValue
            )
        }

        // 2) パーサー群に順番に流す(最初に解釈できたものを採用)
        guard let reading = parsers.lazy.compactMap({
            $0.parse(sensorID: sensorID, localName: localName, manufacturerData: mfgData)
        }).first else { return }

        // 3) 割当て済みポジションに反映
        for (position, assignedID) in assignments where assignedID == sensorID {
            // 同じ値を直近に反映済みなら publish しない(センサーは毎秒発信するため)
            if let prev = readings[position],
               prev.pressureBar == reading.pressureBar,
               prev.temperatureC == reading.temperatureC,
               reading.timestamp.timeIntervalSince(prev.timestamp) < readingRefreshInterval {
                continue
            }
            readings[position] = reading
            checkLowPressure(reading, position: position)
        }
    }
}
