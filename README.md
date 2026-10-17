# MotoDash — バイク用ダッシュボードアプリ (iOS 16 / iPhone X)

GPS速度計 + TPMS(タイヤ空気圧)+ Trip計 + マップ・目的地案内 + ウィジェット。
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
| マップ画面(モノクロ・3D/H-UP/N-UP) | ✅ 即動作 | `App/UI/MapDashView.swift`(Apple MapKit) |
| 目的地案内(右左折・残り距離・再検索) | ✅ 要通信 | `App/Nav/NavManager.swift`(MKDirections。圏外は直線コンパス案内) |
| GPX ルート表示 / 保存地点(給油・休憩) | ✅ 即動作 | 同上 + `App/UI/NavSheet.swift` |
| 配色 4 種(LIME / ARCTIC / STEALTH / SUNLIGHT)・昼夜自動切替 | ✅ 即動作 | `App/UI/Theme.swift` + `ThemeManager.swift` + `SettingsView.swift` |

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
│   ├── Nav/NavManager.swift      # 目的地案内・GPX ルート・保存地点
│   └── UI/
│       ├── RootView.swift        # ダッシュボード ⇄ マップ(左右スワイプ)
│       ├── DashboardView.swift   # メイン画面(横向き・黒背景)
│       ├── MapDashView.swift     # マップ画面(モノクロ MapKit + HUD)
│       ├── NavSheet.swift        # 目的地検索・保存地点・GPX 読込
│       ├── NavGlance.swift       # 案内アイコン・文言(マップ/ダッシュボード共通)
│       ├── Theme.swift           # 配色 4 種のトークン(Palette)
│       ├── ThemeManager.swift    # 配色の手動選択・昼夜自動切替
│       ├── SettingsView.swift    # 設定画面
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
- **マップ切替**: ダッシュボードで左スワイプ → マップ、右スワイプで戻る
- **地図の向き**: マップをタップで 3D(バードビュー)→ H-UP → N-UP
- **目的地**: マップ右上の🔍で検索 / 保存地点から選択 / 停車中の操作モードで地図を長押し。
  案内中はダッシュボードにも表示(タップでマップへ)
- **地点保存**: マップ右上のピンで現在地を給油・休憩・地点として保存
- **設定(配色)**: ダッシュボード右上の歯車。手動で 4 種から選ぶか、時間帯で自動
  (日の出・日の入り / 指定時刻で昼の配色・夜の配色を切替)
- **停車中の地図操作**: 3km/h 未満で出る移動ボタン → 拡大縮小・スクロール。5km/h 以上で自動で追従に戻る
- **画面は自動消灯しない**(`isIdleTimerDisabled`)。バッテリー消費に注意、給電マウント推奨

## 実機運用の注意

- **振動対策**: バイクのエンジン振動はiPhoneカメラのOISを損傷することがある(Apple公式警告)。
  振動吸収マウント推奨
- **熱**: 夏場の直射日光 + 給電 + GPS常時で熱停止しやすい。日陰になる位置に
- **App Group ID**: `project.yml`(2箇所)と `Shared/SharedStore.swift` の計3箇所一致が必須
- **無料ID制限**: 7日で署名失効(再署名でデータ保持)、同時3アプリまで
- **iOS 16縛り**: `.containerBackground` / SwiftData / インタラクティブウィジェット不可
