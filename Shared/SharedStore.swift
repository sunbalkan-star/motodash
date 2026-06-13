import Foundation

/// アプリ本体とウィジェットでデータを共有するためのストア。
/// App Group の UserDefaults を使う。
/// (ウィジェットのリロードは呼び出し側 RideManager がスロットリング付きで行う)
enum SharedStore {
    /// project.yml の application-groups と一致させること
    static let appGroupID = "group.com.tadashi.myapp"

    private static let tripKey = "ride.tripMeters"
    private static let totalKey = "ride.totalMeters"
    private static let timeKey = "ride.ridingSeconds"
    private static let updatedAtKey = "ride.updatedAt"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var tripMeters: Double {
        get { defaults.double(forKey: tripKey) }
        set {
            defaults.set(newValue, forKey: tripKey)
            defaults.set(Date(), forKey: updatedAtKey)
        }
    }

    static var totalMeters: Double {
        get { defaults.double(forKey: totalKey) }
        set { defaults.set(newValue, forKey: totalKey) }
    }

    static var ridingSeconds: Double {
        get { defaults.double(forKey: timeKey) }
        set { defaults.set(newValue, forKey: timeKey) }
    }

    static var updatedAt: Date? {
        defaults.object(forKey: updatedAtKey) as? Date
    }
}
