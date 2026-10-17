import SwiftUI
import MapKit
import UniformTypeIdentifiers

/// ナビ設定シート(マップ画面の検索ボタンから): 目的地検索 / 案内終了 / 保存地点 / GPX ルート
struct NavSheet: View {
    @EnvironmentObject var nav: NavManager
    @EnvironmentObject var ride: RideManager
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var showImporter = false

    var body: some View {
        NavigationView {
            List {
                searchSection
                if let dest = nav.destination {
                    Section("案内中") {
                        Label(dest.name, systemImage: "flag.checkered")
                        Button("案内を終了", role: .destructive) {
                            nav.clearDestination()
                            dismiss()
                        }
                    }
                }
                waypointSection
                gpxSection
            }
            .navigationTitle("ナビ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .preferredColorScheme(Palette.colorScheme)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.gpxTypes) { result in
            if case .success(let url) = result { nav.loadGPX(url) }
        }
    }

    // MARK: - 目的地検索(Apple 地図検索)

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("目的地を検索", text: $query)
                    .submitLabel(.search)
                    .onSubmit(search)
                if searching { ProgressView() }
            }
            if searchFailed {
                Text("見つかりませんでした").foregroundColor(.secondary)
            }
            ForEach(results, id: \.self) { item in
                Button {
                    nav.setDestination(name: item.name ?? "目的地", coordinate: item.placemark.coordinate)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "名称なし").foregroundColor(.primary)
                        HStack {
                            if let d = distanceText(to: item.placemark.coordinate) { Text(d) }
                            Text(item.placemark.title ?? "").lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("目的地")
        } footer: {
            Text("停車中にマップ画面の操作モードで地図を長押ししても目的地にできます。")
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        searchFailed = false
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        if let loc = ride.location {
            req.region = MKCoordinateRegion(center: loc.coordinate,
                                            latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        MKLocalSearch(request: req).start { response, _ in
            let items = response?.mapItems ?? []
            Task { @MainActor in
                searching = false
                results = items
                searchFailed = items.isEmpty
            }
        }
    }

    // MARK: - 保存地点

    private var waypointSection: some View {
        Section {
            if nav.waypoints.isEmpty {
                Text("マップ画面のピンボタンで現在地を保存できます").foregroundColor(.secondary)
            }
            ForEach(nav.waypoints) { wp in
                Button {
                    nav.setDestination(name: wp.name, coordinate: wp.coordinate)
                    dismiss()
                } label: {
                    HStack {
                        Label(wp.name, systemImage: wp.kind.symbol).foregroundColor(.primary)
                        Spacer()
                        if let d = distanceText(to: wp.coordinate) {
                            Text(d).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onDelete { nav.deleteWaypoints(at: $0) }
        } header: {
            Text("保存地点(タップで目的地)")
        }
    }

    // MARK: - GPX ルート

    private var gpxSection: some View {
        Section {
            if let name = nav.gpxName, !nav.gpxRoute.isEmpty {
                Label("\(name)(\(nav.gpxRoute.count) 点)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Button("ルートを消す", role: .destructive) { nav.clearGPX() }
            }
            Button("GPX を読み込む") { showImporter = true }
            if let err = nav.gpxError {
                Text(err).foregroundColor(Palette.amber)
            }
        } header: {
            Text("GPX ルート(地図に点線で表示)")
        }
    }

    /// .gpx は機種により型登録が無いことがあるため、XML と汎用データも許可する
    private static let gpxTypes: [UTType] =
        [UTType(filenameExtension: "gpx"), .xml, .data].compactMap { $0 }

    private func distanceText(to c: CLLocationCoordinate2D) -> String? {
        guard let loc = ride.location else { return nil }
        let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        return d < 1000 ? "\(Int(d)) m" : String(format: "%.1f km", d / 1000)
    }
}
