import Foundation
import CoreLocation
import UIKit
import WidgetKit

/// GPS由来の走行データ(速度・高度・Trip/Total距離・走行時間)
@MainActor
final class RideManager: NSObject, ObservableObject {
    @Published var speedKMH: Double = 0
    @Published var maxSpeedKMH: Double = 0        // 走行開始からの最高速(リセットでクリア)
    @Published var altitudeM: Double = 0
    @Published var tripMeters: Double = 0
    @Published var totalMeters: Double = 0
    @Published var ridingSeconds: TimeInterval = 0
    @Published var gpsStatus = "GPS待機中"
    @Published var phoneBatteryPercent: Int = 0
    @Published var headingDegrees: Double = 0     // コンパス方位(0=北)
    /// 有効なGPS測位を受信中か。false の間は速度を "--" 表示にする
    @Published var hasGPSFix = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastFixDate: Date?
    private var fixWatchdog: Timer?
    private var lastWidgetSync = Date.distantPast
    private var smoothedSpeed: Double = 0

    /// この速度未満は停車扱い(km/h)— GPSノイズで距離が育つのを防ぐ
    private let movingThresholdKMH: Double = 3.0
    /// この秒数、有効な測位が無ければ GPS ロスト扱い(速度が最後の値で固まるのを防ぐ)
    private let fixTimeout: TimeInterval = 3
    /// 測位間隔がこれを超えたら距離・時間を計上しない(バックグラウンド停止・長いロスト明け)
    private let maxGapSeconds: TimeInterval = 10
    /// 2点間の見かけ速度がこれを超えたら測位ジャンプとして捨てる(m/s ≒ 300km/h)
    private let maxPlausibleMPS: Double = 300 / 3.6

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation

        // 永続化された値を復元
        tripMeters = SharedStore.tripMeters
        totalMeters = SharedStore.totalMeters
        ridingSeconds = SharedStore.ridingSeconds

        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()

        // 電池残量・充電状態の変化を購読(GPS更新に依存せず更新される)
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryChanged),
            name: UIDevice.batteryLevelDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryChanged),
            name: UIDevice.batteryStateDidChangeNotification, object: nil
        )
    }

    @objc private func batteryChanged() {
        refreshBattery()
    }

    @objc private func orientationChanged() {
        updateHeadingOrientation()
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.pausesLocationUpdatesAutomatically = false
        // バックグラウンド(ホームへ戻る等)でも計測を継続。Info.plist の UIBackgroundModes=location が前提
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            // 方位は端末の向き基準で返るため、横マウント時は向きを伝えないと90°ずれる
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self, selector: #selector(orientationChanged),
                name: UIDevice.orientationDidChangeNotification, object: nil
            )
            updateHeadingOrientation()
            manager.startUpdatingHeading()
        }
        if fixWatchdog == nil {
            fixWatchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkFixTimeout() }
            }
        }
        // 走行中の画面消灯を防止(バイク用ダッシュボードの必須設定)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// 縦/横左/横右のときだけ反映(上下逆・水平置き・不明は直前の向きを維持)
    private func updateHeadingOrientation() {
        let o = UIDevice.current.orientation
        guard o == .portrait || o == .landscapeLeft || o == .landscapeRight,
              let cl = CLDeviceOrientation(rawValue: Int32(o.rawValue)) else { return }
        manager.headingOrientation = cl
    }

    /// 有効な測位が途絶えたら速度を落とし、表示を "--" にする
    private func checkFixTimeout() {
        guard hasGPSFix, let last = lastFixDate,
              Date().timeIntervalSince(last) > fixTimeout else { return }
        hasGPSFix = false
        smoothedSpeed = 0
        speedKMH = 0
        gpsStatus = "GPSロスト"
    }

    func resetTrip() {
        tripMeters = 0
        ridingSeconds = 0
        maxSpeedKMH = 0
        persist(force: true)
    }

    /// 最高速のみリセット(ゲージのMAX表示を長押し)。次のGPS更新から再追従。
    func resetMaxSpeed() {
        maxSpeedKMH = 0
    }

    private func refreshBattery() {
        let device = UIDevice.current
        // 充電完了(.full)時は batteryLevel が 1.0 未満を返すことがあるため補正
        if device.batteryState == .full {
            phoneBatteryPercent = 100
            return
        }
        let level = device.batteryLevel
        phoneBatteryPercent = level >= 0 ? Int((level * 100).rounded()) : 0
    }

    /// SharedStoreへ保存。ウィジェットのリロードは高頻度すぎると
    /// 予算制限に当たるため60秒に1回に絞る
    private func persist(force: Bool = false) {
        SharedStore.tripMeters = tripMeters
        SharedStore.totalMeters = totalMeters
        SharedStore.ridingSeconds = ridingSeconds
        if force || Date().timeIntervalSince(lastWidgetSync) > 60 {
            lastWidgetSync = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension RideManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.process(location)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.gpsStatus = "GPSエラー"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted:
                self.gpsStatus = "位置情報が許可されていません"
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let deg = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.headingDegrees = deg
        }
    }

    @MainActor
    private func process(_ location: CLLocation) {
        // 精度の悪い測位は捨てる
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 50 else { return }

        gpsStatus = "GPS ✅ (±\(Int(location.horizontalAccuracy))m)"
        hasGPSFix = true
        lastFixDate = Date()
        altitudeM = location.altitude

        // 速度: 負値(無効)は0扱い、軽くスムージングして針の暴れを抑える
        let rawKMH = max(0, location.speed) * 3.6
        smoothedSpeed = smoothedSpeed * 0.3 + rawKMH * 0.7
        speedKMH = smoothedSpeed < 1 ? 0 : smoothedSpeed
        if speedKMH > maxSpeedKMH { maxSpeedKMH = speedKMH }

        if let last = lastLocation, speedKMH >= movingThresholdKMH {
            // 測位時刻ベースで間隔を測る。空白が長すぎる(バックグラウンド停止・長いロスト明け)
            // か、見かけ速度があり得ない(測位ジャンプ)場合は距離・時間とも計上しない
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            let delta = location.distance(from: last)
            if dt > 0, dt <= maxGapSeconds, delta / dt <= maxPlausibleMPS {
                tripMeters += delta
                totalMeters += delta
                ridingSeconds += dt
            }
        }
        lastLocation = location

        refreshBattery()
        persist()
    }
}
