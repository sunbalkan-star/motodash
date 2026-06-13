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
    @Published var rawPackets: [RawBLEPacket] = []   // スニファー用
    @Published var isScanning = false

    // MARK: 前後輪へのセンサー割当(UserDefaultsに永続化)
    @Published var assignments: [WheelPosition: UUID] = [:] {
        didSet { saveAssignments() }
    }

    private var central: CBCentralManager!
    private var lastAlertDate: [WheelPosition: Date] = [:]

    /// 低圧アラート閾値(bar)。車種に合わせて調整
    var lowPressureThreshold: Double = 1.8
    /// アラートの再通知間隔(秒)
    private let alertCooldown: TimeInterval = 10 * 60

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
        }
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
        guard reading.pressureBar < lowPressureThreshold else { return }
        let last = lastAlertDate[position] ?? .distantPast
        guard Date().timeIntervalSince(last) > alertCooldown else { return }
        lastAlertDate[position] = Date()

        let content = UNMutableNotificationContent()
        content.title = "⚠️ タイヤ空気圧 低下"
        content.body = String(
            format: "%@: %.2f bar(閾値 %.2f bar)",
            position == .front ? "フロント" : "リア",
            reading.pressureBar, lowPressureThreshold
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

        // 1) スニファー記録(全デバイス、Manufacturer Data持ちのみ)
        if let mfgData {
            updateRawPacket(
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
            readings[position] = reading
            checkLowPressure(reading, position: position)
        }
    }

    private func updateRawPacket(id: UUID, name: String?, hex: String, rssi: Int) {
        if let idx = rawPackets.firstIndex(where: { $0.id == id }) {
            rawPackets[idx].localName = name ?? rawPackets[idx].localName
            rawPackets[idx].manufacturerHex = hex
            rawPackets[idx].rssi = rssi
            rawPackets[idx].lastSeen = Date()
        } else {
            rawPackets.append(RawBLEPacket(
                id: id, localName: name,
                manufacturerHex: hex, rssi: rssi, lastSeen: Date()
            ))
        }
        rawPackets.sort { $0.rssi > $1.rssi }
    }
}
