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
| 恒久ルール | `C:\Users\Tadashi\Downloads\design\DESIGN_RULES.md` | Design に一度貼る恒久ルール（データ制約・崩れ防止・レイアウト鉄則・トークン）。Code が更新したらここに反映 |
| Code → Design | `C:\Users\Tadashi\Downloads\design\PROMPT.md` | Claude Code が現状レイアウトをまとめてここに **上書き** する。ユーザーは開いてコピーするだけ |
| Design → Code | `C:\Users\Tadashi\Downloads\design\MotoDash.dc.html` | ユーザーが Claude Design の出力 HTML をここに **上書き保存**。Claude Code はここを読んで SwiftUI へ移植 |
| 仕様参照 | `C:\Users\Tadashi\Downloads\design\README.md` | デザイントークン・状態色の正典 |

### 合言葉（ユーザーが言ったら自動実行）
- **「デザイン用プロンプト出して」** → `App/UI/DashboardView.swift` の現状（レイアウト構成・サイズ・トークン・状態色）を読み取り、`design\PROMPT.md` に完結型プロンプトとして上書き。**必ず「# SwiftUI 実装制約（レイアウト崩れ防止）」セクションを含める**（実機 pt キャンバス固定 / SF Pro 字幅の余白 / 素直な flex のみ / overflow 非依存）。最後の「# 私のデザインコンセプト」欄は空にしておき、ユーザーがそこだけ書き換えて使う。完了後「PROMPT.md を開いてコピーしてください」と返す。
- **「デザイン更新して」/「デザイン反映して」** → `design\MotoDash.dc.html` を読み、現行 SwiftUI（`DashboardView.swift`・`Theme.swift`・`GaugeBar.swift`）との差分を実装。レイアウト変更のみで、データ配線やビジネスロジックは触らない。
- どちらも、変更後は `feat/...` ブランチにコミット→必要なら main へマージ→push（CI ビルドのため）。

### 移植時の注意
- HTML をそのまま使わない。SwiftUI ネイティブ描画（Shape / Path / Text / SF Symbols）で再現する。
- デザイントークンは `Theme.swift` の `Palette` / `StateColor` に集約。色を直書きしない。
- アクセント色 `#A6F226` = `Color(red: 0.65, green: 0.95, blue: 0.15)`。

## レイアウト収まり確認（必須ルール）

**機能の追加・削除・レイアウト変更を行った後は、必ず以下を確認して再調整すること。**

### 確認項目
1. **横画面（812×375 pt）**: 全要素が左 46pt・右 18pt のセーフエリア内に収まっているか。速度数字・TPMS カード・下辺ストリップが重なったり見切れていないか。
2. **縦画面（375×812 pt）**: ステータスバー〜ゲージ〜ヒーロー速度〜カードエリアの合計高さが画面内に収まっているか（下に Spacer が残っているか確認）。
3. **カード固定高さ**: `pTPMSCard` / `pDataCard` は h70pt 固定。内容を増やした場合は高さを変更し、カードエリア全体の合計高さを再計算する。
4. **下辺ストリップ（横画面）**: h80pt ストリップ + top padding 28pt + bottom 10pt の合計が、速度+TPMS エリアと干渉しないか。

### 再調整の手順
- 収まらない場合は padding / spacing / フォントサイズ を段階的に縮小して収める。
- カード高さを変えた場合は、**両画面のカードエリア合計高さをコメントで明記**してコードに残す。
- 調整後、変更内容をコミットメッセージに記載する。

## リポジトリ
- GitHub: https://github.com/sunbalkan-star/motodash.git
- ローカル: `C:\Users\Tadashi\Downloads\ios-template`
- push すると GitHub Actions が unsigned IPA をビルド。実機確認は AltStore 経由。
