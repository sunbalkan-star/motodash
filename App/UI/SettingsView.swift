import SwiftUI

/// 設定画面(ダッシュボードの歯車から)。配色の手動選択と、昼夜での自動切替
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("切り替え", selection: $theme.mode) {
                        ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if theme.mode == .manual {
                        themeChoices($theme.manualTheme)
                    }
                } header: {
                    Text("配色")
                }

                if theme.mode == .auto {
                    Section {
                        Picker("基準", selection: $theme.basis) {
                            ForEach(ThemeAutoBasis.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if theme.basis == .clock || theme.usesClockFallback {
                            DatePicker("昼の開始", selection: timeBinding($theme.dayStartMinutes),
                                       displayedComponents: .hourAndMinute)
                            DatePicker("夜の開始", selection: timeBinding($theme.nightStartMinutes),
                                       displayedComponents: .hourAndMinute)
                        }
                    } header: {
                        Text("切り替えのタイミング")
                    } footer: {
                        Text(timingFooter)
                    }

                    Section {
                        themeChoices($theme.dayTheme)
                    } header: {
                        Label("昼の配色", systemImage: "sun.max.fill")
                    }

                    Section {
                        themeChoices($theme.nightTheme)
                    } header: {
                        Label("夜の配色", systemImage: "moon.fill")
                    }
                }

                Section {
                    HStack {
                        Text("表示中")
                        Spacer()
                        Text(currentText).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
        .preferredColorScheme(theme.current.palette.isLight ? .light : .dark)
    }

    private var timingFooter: String {
        switch theme.basis {
        case .sun:
            return theme.usesClockFallback
                ? "GPS で現在地が取れるまでは、上の時刻で切り替えます。"
                : "現在地の日の出で昼、日の入りで夜の配色に切り替えます。"
        case .clock:
            return "指定した時刻で切り替えます。"
        }
    }

    private var currentText: String {
        guard theme.mode == .auto else { return theme.current.name }
        return "\(theme.current.name)(\(theme.isDaytime ? "昼" : "夜"))"
    }

    /// 配色の一覧(見本 + 名前 + 説明)。タップで選択
    private func themeChoices(_ selection: Binding<ThemeID>) -> some View {
        ForEach(ThemeID.allCases) { id in
            Button {
                selection.wrappedValue = id
            } label: {
                HStack(spacing: 12) {
                    ThemeSwatch(palette: id.palette)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(id.name).font(.headline).foregroundColor(.primary)
                        Text(id.summary).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if selection.wrappedValue == id {
                        Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 0:00 からの分 ⇄ DatePicker 用の今日の時刻
    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// 配色の見本(小さなメーター: 地色・速度の数字・ゲージ・方位)
struct ThemeSwatch: View {
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("48").font(motoNumberFont(18, .heavy)).foregroundColor(palette.textHi)
                Text("NE").font(motoNumberFont(9, .heavy)).foregroundColor(palette.heading)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(palette.accent).frame(width: 22)
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 7)
        .frame(width: 64, height: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.borderStrong, lineWidth: 1))
    }
}
