import SwiftUI

/// BLEスニファー兼センサー割当画面。
/// TPMSセンサー購入後の流れ:
///   1. センサーをタイヤに装着(走行で加圧検知するタイプは少し走る)
///   2. この画面で電波の強いデバイスを特定(Manufacturer Dataのhexを確認)
///   3. 「フロント」「リア」ボタンで割当て → ダッシュボードに反映
///   4. 値が出ない場合は hex をメモしてパーサーを調整
struct SnifferView: View {
    @EnvironmentObject var tpms: TPMSManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(tpms.bluetoothReady ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(tpms.bluetoothReady ? "Bluetooth ON / スキャン中" : "Bluetooth OFF")
                            .font(.caption)
                        Spacer()
                        Text("\(tpms.rawPackets.count)台検出")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("スニファー")
                } footer: {
                    Text("Manufacturer Data を持つBLEデバイスのみ表示。TPMSセンサーは名前に「TPMS」を含むことが多い。")
                }

                Section("検出デバイス(電波強度順)") {
                    if tpms.rawPackets.isEmpty {
                        Text("スキャン中…(センサーは加圧時のみ発信する機種あり)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tpms.rawPackets) { packet in
                        packetRow(packet)
                    }
                }

                Section("現在の割当") {
                    ForEach(WheelPosition.allCases, id: \.self) { pos in
                        HStack {
                            Text(pos == .front ? "フロント" : "リア")
                            Spacer()
                            if let id = tpms.assignments[pos] {
                                Text(shortID(id))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Button("解除") { tpms.clearAssignment(pos) }
                                    .font(.caption)
                                    .tint(.red)
                            } else {
                                Text("未割当")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("TPMSセンサー設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    private func packetRow(_ packet: RawBLEPacket) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(packet.localName ?? "(名称不明)")
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                Spacer()
                Text("\(packet.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(packet.rssi > -70 ? .green : .secondary)
            }
            // 生パケット(パーサー作成時の解析材料)
            Text(packet.manufacturerHex)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button("フロントに割当") { tpms.assign(packet.id, to: .front) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("リアに割当") { tpms.assign(packet.id, to: .rear) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Text(packet.lastSeen, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
