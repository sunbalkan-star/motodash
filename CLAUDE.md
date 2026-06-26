# MotoDash — プロジェクト規約

iPhone をバイクのハンドルにマウントするデジタルメーターアプリ。
横画面=主画面（ハンドルマウント）/ 縦画面=従画面。Windows のみで開発し、ビルドは GitHub Actions CI 経由（Mac 無し）。

## データ制約（厳守）
表示してよいのは iPhone 内蔵センサー + BLE のみ：
- GPS（速度 / 距離 / 走行時間 / 最高速）
- 気圧センサー（高度）
- 磁気センサー（コンパス方位）
- 端末バッテリー
- BLE TPMS（前/後タイヤ空気圧 bar）

**絶対に表示しない**（OBD-II/CAN 非接続で取得不可）: rpm・スロットル・油温・水温・車両バッテリー・燃料・ギア。これらを出すと "ウソの UI" になる。

## Claude Code ⇄ Claude Design ブリッジ（コピペ最小化ワークフロー）

Claude Code（コード）と Claude Design（ビジュアル）の間はファイルで橋渡しする。固定パスを使い、口頭でパスを伝える手間をなくす。

### 固定パス
| 方向 | パス | 役割 |
|---|---|---|
| Code → Design | `C:\Users\Tadashi\Downloads\design\PROMPT.md` | Claude Code が現状レイアウトをまとめてここに **上書き** する。ユーザーは開いてコピーするだけ |
| Design → Code | `C:\Users\Tadashi\Downloads\design\MotoDash.dc.html` | ユーザーが Claude Design の出力 HTML をここに **上書き保存**。Claude Code はここを読んで SwiftUI へ移植 |
| 仕様参照 | `C:\Users\Tadashi\Downloads\design\README.md` | デザイントークン・状態色の正典 |

### 合言葉（ユーザーが言ったら自動実行）
- **「デザイン用プロンプト出して」** → `App/UI/DashboardView.swift` の現状（レイアウト構成・サイズ・トークン・状態色）を読み取り、`design\PROMPT.md` に完結型プロンプトとして上書き。最後の「# 私のデザインコンセプト」欄は空にしておき、ユーザーがそこだけ書き換えて使う。完了後「PROMPT.md を開いてコピーしてください」と返す。
- **「デザイン更新して」/「デザイン反映して」** → `design\MotoDash.dc.html` を読み、現行 SwiftUI（`DashboardView.swift`・`Theme.swift`・`GaugeBar.swift`）との差分を実装。レイアウト変更のみで、データ配線やビジネスロジックは触らない。
- どちらも、変更後は `feat/...` ブランチにコミット→必要なら main へマージ→push（CI ビルドのため）。

### 移植時の注意
- HTML をそのまま使わない。SwiftUI ネイティブ描画（Shape / Path / Text / SF Symbols）で再現する。
- デザイントークンは `Theme.swift` の `Palette` / `StateColor` に集約。色を直書きしない。
- アクセント色 `#A6F226` = `Color(red: 0.65, green: 0.95, blue: 0.15)`。

## リポジトリ
- GitHub: https://github.com/sunbalkan-star/motodash.git
- ローカル: `C:\Users\Tadashi\Downloads\ios-template`
- push すると GitHub Actions が unsigned IPA をビルド。実機確認は AltStore 経由。
