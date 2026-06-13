import SwiftUI

struct ContentView: View {
    @StateObject private var notifications = NotificationManager()
    @StateObject private var bluetooth = BluetoothManager()
    @State private var counter = SharedStore.counter

    var body: some View {
        NavigationStack {
            List {
                // MARK: ウィジェット連携(App Group共有カウンター)
                Section("ウィジェット連携") {
                    HStack {
                        Text("共有カウンター")
                        Spacer()
                        Text("\(counter)")
                            .font(.title2.monospacedDigit())
                            .bold()
                    }
                    HStack {
                        Button("−1") { update(counter - 1) }
                            .buttonStyle(.bordered)
                        Button("+1") { update(counter + 1) }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("リセット") { update(0) }
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                    Text("値を変えるとウィジェットが即時更新されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: ローカル通知
                Section("ローカル通知") {
                    Button("通知の権限をリクエスト") {
                        notifications.requestPermission()
                    }
                    Button("5秒後にテスト通知") {
                        notifications.schedule(after: 5)
                    }
                    .disabled(!notifications.isAuthorized)
                    if !notifications.lastResult.isEmpty {
                        Text(notifications.lastResult)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Bluetooth
                Section("Bluetooth (BLE スキャン)") {
                    HStack {
                        Text(bluetooth.stateText)
                            .font(.caption)
                        Spacer()
                        Button(bluetooth.isScanning ? "停止" : "スキャン開始") {
                            bluetooth.toggleScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(bluetooth.isScanning ? .red : .blue)
                    }
                    ForEach(bluetooth.peripherals) { p in
                        HStack {
                            Text(p.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(p.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(rssiColor(p.rssi))
                        }
                    }
                }
            }
            .navigationTitle("MyApp")
        }
    }

    private func update(_ newValue: Int) {
        counter = newValue
        SharedStore.counter = newValue
    }

    private func rssiColor(_ rssi: Int) -> Color {
        switch rssi {
        case (-60)...: return .green
        case (-80)...: return .orange
        default:       return .secondary
        }
    }
}

#Preview {
    ContentView()
}
