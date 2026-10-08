import Foundation
import CoreLocation

/// 走行ログ(GPX書き出し用)。走行中の測位点を 1走行=1ファイル で Documents/Rides に追記する。
/// 記録は軽量な行形式(.track: lat,lon,ele,unixTime)で、GPX は書き出し時に生成する。
/// 記録が 30分以上途切れたら、次の点から新しい走行として別ファイルにする。
/// 容量目安: 1Hz 記録で 1時間 ≒ 150KB。メインスレッド(RideManager)からのみ使う。
final class RideLogger {
    struct Ride: Identifiable, Hashable {
        let url: URL
        let start: Date
        let end: Date
        let distanceMeters: Double
        var id: URL { url }
    }

    private struct Point {
        let lat: Double
        let lon: Double
        let ele: Double
        let time: Date
    }

    private let dir: URL
    private var currentURL: URL?
    private var lastPointDate: Date?
    private let newRideGap: TimeInterval = 30 * 60

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Rides", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // アプリ再起動を挟んでも、直近の走行が続いていれば同じファイルに追記する
        if let latest = trackFiles().last,
           let modified = try? latest.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate {
            currentURL = latest
            lastPointDate = modified
        }
    }

    // MARK: - 記録

    func append(_ location: CLLocation, altitude: Double) {
        let t = location.timestamp
        if currentURL == nil || t.timeIntervalSince(lastPointDate ?? .distantPast) > newRideGap {
            currentURL = dir.appendingPathComponent("\(Self.fileNameFormatter.string(from: t)).track")
        }
        lastPointDate = t

        let line = String(format: "%.7f,%.7f,%.1f,%.3f\n",
                          location.coordinate.latitude, location.coordinate.longitude,
                          altitude, t.timeIntervalSince1970)
        guard let url = currentURL, let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }

    // MARK: - 一覧・書き出し・削除

    /// 新しい順
    func rides() -> [Ride] {
        trackFiles().reversed().compactMap { url in
            let points = readPoints(url)
            guard let first = points.first, let last = points.last else { return nil }
            return Ride(url: url, start: first.time, end: last.time,
                        distanceMeters: distance(points))
        }
    }

    /// GPX 1.1 を一時ディレクトリに生成して URL を返す(共有シート用)
    func exportGPX(_ ride: Ride) throws -> URL {
        let points = readPoints(ride.url)
        let iso = ISO8601DateFormatter()
        let name = "MotoDash \(Self.titleFormatter.string(from: ride.start))"

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="MotoDash" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(name)</name><trkseg>

        """
        for p in points {
            gpx += String(format: "<trkpt lat=\"%.7f\" lon=\"%.7f\"><ele>%.1f</ele>", p.lat, p.lon, p.ele)
            gpx += "<time>\(iso.string(from: p.time))</time></trkpt>\n"
        }
        gpx += "</trkseg></trk>\n</gpx>\n"

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("MotoDash_\(Self.fileNameFormatter.string(from: ride.start)).gpx")
        try gpx.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    func delete(_ ride: Ride) {
        try? FileManager.default.removeItem(at: ride.url)
        if ride.url == currentURL {
            currentURL = nil
            lastPointDate = nil
        }
    }

    // MARK: - 内部

    /// ファイル名(開始日時)順 = 古い順
    private func trackFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.pathExtension == "track" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readPoints(_ url: URL) -> [Point] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: ",")
            guard f.count >= 4,
                  let lat = Double(f[0]), let lon = Double(f[1]),
                  let ele = Double(f[2]), let ts = Double(f[3]) else { return nil }
            return Point(lat: lat, lon: lon, ele: ele, time: Date(timeIntervalSince1970: ts))
        }
    }

    private func distance(_ points: [Point]) -> Double {
        var total = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            total += CLLocation(latitude: a.lat, longitude: a.lon)
                .distance(from: CLLocation(latitude: b.lat, longitude: b.lon))
        }
        return total
    }

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
