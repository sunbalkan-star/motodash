# MotoDash — バイク用ダッシュボードアプリ (iOS 16 / iPhone X)

GPS速度計 + TPMS(タイヤ空気圧)+ Trip計 + ウィジェット。
iPhone X (iOS 16.7.x) + 無料Apple ID サイドロード運用前提。

## 機能と状態

| 機能 | 状態 | 実装 |
|---|---|---|
| 速度 (km/h) | ✅ 即動作 | `App/Ride/RideManager.swift` (GPS + スムージング) |
| 高度 | ✅ 即動作 | 同上 |
| Trip / Total / 走行時間 | ✅ 即動作 | 同上(永続化、Trip長押しリセット) |
| iPhone電池残量 | ✅ 即動作 | 同上 |
| タイヤ空気圧・温度 | 🔌 センサー購入後 | `App/TPMS/`(下記の連動手順参照) |
| 低圧アラート(ローカル通知) | 🔌 同上 | `TPMSManager.checkLowPressure` |
| Trip距離ウィジェット | ✅ 即動作 | ホーム + ロック画面、走行中約60秒ごと更新 |

## TPMSセンサー購入後の連動手順

設計方針: **パーサープラグイン方式**。BLEアドバタイズ → 登録済みパーサー群 → 前後輪割当。

1. **センサー選び**: バルブキャップ型のBLEタイプ(デバイス名が `TPMS1_xxxx` 等の格安品でOK)。
   「専用アプリ必須」「BLE接続型」と書かれたものより、**ブロードキャスト型**が扱いやすい
2. センサー装着後、アプリのタイヤパネルをタップ → **スニファー画面**を開く
3. 検出デバイス一覧から該当センサーを特定(電波強度と Manufacturer Data hex で判断)
4. 「フロントに割当」「リアに割当」をタップ → ダッシュボードに値が出れば完了
5. **値が出ない場合**: 同梱の `CommonChineseTPMSParser` とパケット形式が違う機種。
   スニファー画面の hex(長押しコピー可)をメモして、
   `App/TPMS/TPMSModels.swift` に新パーサーを追加 → `TPMSManager.parsers` に登録

```swift
// パーサー追加の例
struct MySensorParser: TPMSAdvertisementParser {
    let name = "MySensor"
    func parse(sensorID: UUID, localName: String?, manufacturerData: Data?) -> TPMSReading? {
        // hexダンプを見ながらオフセットを合わせる
    }
}
```

## ディレクトリ構成

```
ios-template/
├── project.yml              # xcodegen定義
├── .github/workflows/       # push → 未署名.ipa 自動ビルド
├── App/
│   ├── MyTemplateApp.swift
│   ├── Ride/RideManager.swift    # GPS: 速度/高度/Trip/時間
│   ├── TPMS/TPMSModels.swift     # 読み値モデル + パーサープロトコル + 実装例
│   ├── TPMS/TPMSManager.swift    # BLEスキャン/割当/低圧通知
│   └── UI/
│       ├── DashboardView.swift   # メイン画面(横向き・黒背景)
│       └── SnifferView.swift     # BLEスニファー + センサー割当
├── Shared/SharedStore.swift      # App Group共有(Trip等)
└── Widget/RideWidget.swift       # Trip距離ウィジェット
```

## ビルド〜転送

1. push → GitHub Actions が未署名 `.ipa` を Artifacts に出力
2. Windows の Sideloadly で無料Apple ID署名 + USB転送(7日ごと再署名)

詳細はワークフロー `.github/workflows/build.yml` を参照。

## 操作メモ

- **Trip リセット**: 画面右下の Trip を長押し
- **センサー設定**: タイヤパネルをタップ
- **画面は自動消灯しない**(`isIdleTimerDisabled`)。バッテリー消費に注意、給電マウント推奨

## 実機運用の注意

- **振動対策**: バイクのエンジン振動はiPhoneカメラのOISを損傷することがある(Apple公式警告)。
  振動吸収マウント推奨
- **熱**: 夏場の直射日光 + 給電 + GPS常時で熱停止しやすい。日陰になる位置に
- **App Group ID**: `project.yml`(2箇所)と `Shared/SharedStore.swift` の計3箇所一致が必須
- **無料ID制限**: 7日で署名失効(再署名でデータ保持)、同時3アプリまで
- **iOS 16縛り**: `.containerBackground` / SwiftData / インタラクティブウィジェット不可
