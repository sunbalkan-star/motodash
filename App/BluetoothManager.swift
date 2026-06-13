import Foundation
import CoreBluetooth

struct DiscoveredPeripheral: Identifiable {
    let id: UUID
    let name: String
    var rssi: Int
}

/// BLEスキャナ。周辺のペリフェラルを列挙する最小実装。
final class BluetoothManager: NSObject, ObservableObject {
    @Published var stateText = "初期化中…"
    @Published var isScanning = false
    @Published var peripherals: [DiscoveredPeripheral] = []

    private var central: CBCentralManager!

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func toggleScan() {
        guard central.state == .poweredOn else { return }
        if isScanning {
            central.stopScan()
            isScanning = false
        } else {
            peripherals.removeAll()
            // 重複検出を許可してRSSIをライブ更新
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isScanning = true
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:   stateText = "Bluetooth ON ✅"
        case .poweredOff:  stateText = "BluetoothがOFFです"
        case .unauthorized: stateText = "Bluetooth権限がありません"
        case .unsupported: stateText = "BLE非対応デバイス"
        default:           stateText = "状態: \(central.state.rawValue)"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "(名称不明)"

        if let idx = peripherals.firstIndex(where: { $0.id == peripheral.identifier }) {
            peripherals[idx].rssi = RSSI.intValue
        } else {
            peripherals.append(
                DiscoveredPeripheral(
                    id: peripheral.identifier, name: name, rssi: RSSI.intValue
                )
            )
        }
        // 信号強度順にソート
        peripherals.sort { $0.rssi > $1.rssi }
    }
}
