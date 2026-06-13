import WidgetKit
import SwiftUI

// MARK: - Timeline

struct CounterEntry: TimelineEntry {
    let date: Date
    let counter: Int
    let updatedAt: Date?
}

struct CounterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CounterEntry {
        CounterEntry(date: .now, counter: 42, updatedAt: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (CounterEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CounterEntry>) -> Void) {
        // アプリ側が WidgetCenter.reloadAllTimelines() を呼ぶため、
        // ここでは現在値1件 + 15分後の再評価のみ
        let timeline = Timeline(
            entries: [currentEntry()],
            policy: .after(.now.addingTimeInterval(15 * 60))
        )
        completion(timeline)
    }

    private func currentEntry() -> CounterEntry {
        CounterEntry(
            date: .now,
            counter: SharedStore.counter,
            updatedAt: SharedStore.updatedAt
        )
    }
}

// MARK: - Views

struct CounterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CounterEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            // ロック画面(円形)
            ZStack {
                AccessoryWidgetBackground()
                Text("\(entry.counter)")
                    .font(.title3.monospacedDigit())
                    .bold()
            }
        case .accessoryRectangular:
            // ロック画面(長方形)
            VStack(alignment: .leading, spacing: 2) {
                Text("共有カウンター")
                    .font(.caption2)
                Text("\(entry.counter)")
                    .font(.title2.monospacedDigit())
                    .bold()
            }
        default:
            // ホーム画面 (small / medium)
            VStack(spacing: 6) {
                Text("共有カウンター")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.counter)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                if let updatedAt = entry.updatedAt {
                    Text(updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // .containerBackground は iOS 17+ のため使用しない(iOS 16互換)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Widget定義

struct CounterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CounterWidget", provider: CounterProvider()) { entry in
            CounterWidgetView(entry: entry)
        }
        .configurationDisplayName("共有カウンター")
        .description("アプリで設定した値を表示します")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular  // ロック画面 (iOS 16+)
        ])
    }
}

@main
struct MyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
    }
}
