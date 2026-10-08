import SwiftUI
import UIKit

/// 走行記録シート(ダッシュボードの TIME カードをタップで開く)。
/// Trip A / Trip B の距離・走行時間・平均速度、最高速・総距離、GPX 走行ログの書き出し。
/// 表示値はすべて GPS 由来(CLAUDE.md のデータ制約内)。
struct RideLogView: View {
    @EnvironmentObject var ride: RideManager
    @Environment(\.dismiss) private var dismiss

    @State private var rides: [RideLogger.Ride] = []
    @State private var share: ShareItem?
    @State private var resetTarget: TripKind?
    @State private var exportError: String?

    enum TripKind: String, Identifiable {
        case a = "Trip A", b = "Trip B"
        var id: String { rawValue }
    }

    struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            List {
                tripSection(.a, meters: ride.tripMeters, seconds: ride.ridingSeconds,
                            footer: "リセットで走行時間・最高速も 0 に戻ります(ウィジェット表示対象)")
                tripSection(.b, meters: ride.tripBMeters, seconds: ride.tripBSeconds,
                            footer: "給油間隔などの手動管理用。リセットは Trip B のみ")

                Section("全体") {
                    row("最高速", String(format: "%.0f km/h", ride.maxSpeedKMH))
                    row("総距離", String(format: "%.0f km", ride.totalMeters / 1000))
                }

                Section {
                    if rides.isEmpty {
                        Text("走行するとここに記録されます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rides) { r in
                        rideRow(r)
                    }
                    .onDelete { indexSet in
                        indexSet.map { rides[$0] }.forEach(ride.logger.delete)
                        reload()
                    }
                } header: {
                    Text("走行ログ(GPX)")
                } footer: {
                    Text("走行中の位置を自動記録。30分以上止まると次の走行として分かれます。左スワイプで削除。")
                }
            }
            .navigationTitle("走行記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .sheet(item: $share) { item in
                ActivityView(items: [item.url])
            }
            .confirmationDialog(
                "\(resetTarget?.rawValue ?? "") をリセットしますか？",
                isPresented: Binding(get: { resetTarget != nil },
                                     set: { if !$0 { resetTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("リセット", role: .destructive) {
                    if resetTarget == .a { ride.resetTrip() } else { ride.resetTripB() }
                    resetTarget = nil
                }
            }
            .alert("書き出しに失敗しました",
                   isPresented: Binding(get: { exportError != nil },
                                        set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    // MARK: - 部品

    private func tripSection(_ kind: TripKind, meters: Double, seconds: TimeInterval,
                             footer: String) -> some View {
        Section {
            row("距離", String(format: "%.1f km", meters / 1000))
            row("走行時間", formatDuration(seconds))
            row("平均速度", RideManager.averageKMH(meters: meters, seconds: seconds)
                .map { String(format: "%.0f km/h", $0) } ?? "--")
            Button("\(kind.rawValue) をリセット", role: .destructive) { resetTarget = kind }
        } header: {
            Text(kind.rawValue)
        } footer: {
            Text(footer)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func rideRow(_ r: RideLogger.Ride) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.start, format: .dateTime.year().month().day().hour().minute())
                    .font(.subheadline)
                Text("\(String(format: "%.1f km", r.distanceMeters / 1000)) ・ \(formatDuration(r.end.timeIntervalSince(r.start)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                do {
                    share = ShareItem(url: try ride.logger.exportGPX(r))
                } catch {
                    exportError = error.localizedDescription
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
    }

    private func reload() {
        rides = ride.logger.rides()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return "\(h)h \(m)m"
    }
}

/// 共有シート(ファイルに保存 / AirDrop / 他アプリ)
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
