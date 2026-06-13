import WidgetKit
import SwiftUI

// MARK: - Timeline

struct RideEntry: TimelineEntry {
    let date: Date
    let tripKM: Double
    let totalKM: Double
    let ridingMinutes: Int
    let updatedAt: Date?
}

struct RideProvider: TimelineProvider {
    func placeholder(in context: Context) -> RideEntry {
        RideEntry(date: .now, tripKM: 63.9, totalKM: 3580, ridingMinutes: 85, updatedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RideEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RideEntry>) -> Void) {
        // 走行中はアプリ側が約60秒ごとにリロードを要求してくる
        let timeline = Timeline(
            entries: [currentEntry()],
            policy: .after(.now.addingTimeInterval(30 * 60))
        )
        completion(timeline)
    }

    private func currentEntry() -> RideEntry {
        RideEntry(
            date: .now,
            tripKM: SharedStore.tripMeters / 1000,
            totalKM: SharedStore.totalMeters / 1000,
            ridingMinutes: Int(SharedStore.ridingSeconds / 60),
            updatedAt: SharedStore.updatedAt
        )
    }
}

// MARK: - Views

struct RideWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RideEntry

    private let accent = Color(red: 0.65, green: 0.95, blue: 0.15)

    var body: some View {
        switch family {
        case .accessoryCircular:
            // ロック画面(円形): Trip距離
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", entry.tripKM))
                        .font(.headline.monospacedDigit())
                        .bold()
                    Text("km")
                        .font(.caption2)
                }
            }
        case .accessoryRectangular:
            // ロック画面(長方形)
            VStack(alignment: .leading, spacing: 2) {
                Text("🏍️ Trip")
                    .font(.caption2)
                Text(String(format: "%.1f km", entry.tripKM))
                    .font(.title3.monospacedDigit())
                    .bold()
                Text("\(entry.ridingMinutes) min")
                    .font(.caption2)
            }
        default:
            // ホーム画面 (small / medium)
            VStack(spacing: 8) {
                HStack {
                    Text("🏍️ RIDE")
                        .font(.caption.bold())
                        .foregroundStyle(accent)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", entry.tripKM))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                    Text("km")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("\(entry.ridingMinutes)min", systemImage: "clock")
                    Spacer()
                    Text(String(format: "計 %.0fkm", entry.totalKM))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // .containerBackground は iOS 17+ のため使用しない(iOS 16互換)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Widget定義

struct RideWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RideWidget", provider: RideProvider()) { entry in
            RideWidgetView(entry: entry)
        }
        .configurationDisplayName("ライド情報")
        .description("Trip距離と走行時間を表示します")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular  // ロック画面 (iOS 16+)
        ])
    }
}

@main
struct MyWidgetBundle: WidgetBundle {
    var body: some Widget {
        RideWidget()
    }
}
