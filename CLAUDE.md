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

## Claude Code ⇄ Claude Design ブリッジ

### 基本ルート：Design キャンバス直結（ユーザーの手動の行き来なし）
Claude Code が Artifact ツールの **Design タイプ**（claude.ai のデザインキャンバス）を直接作成・読み取りする。ユーザーはリンクを開いて見るだけ。コピペ・ファイル保存は不要。

- **「デザイン案作って（コンセプト）」** →
  1. 現行 SwiftUI（`DashboardView.swift`・`MapDashView.swift`・`Theme.swift`・`GaugeBar.swift`）から実寸・トークン・状態色を読み取る。
  2. `design\DESIGN_RULES.md` の制約（データ制約・SwiftUI 移植ルール・レイアウト鉄則・トークン・状態色）を守り、Design タイプで**新規キャンバス**を作る。横 812×375・縦 375×812 を必ず両方。案が複数なら案ごとに 1 アートボードにし、共通の画面は 1 ファイルに書いて `<dc-import>` で使い回す。状態色が確認できるサンプル値（例: 後輪 注意）と、案内中の状態を入れる。
  3. 作成後は Chrome（claude-in-chrome）でキャンバスを開いてレイアウト崩れ（はみ出し・重なり・見切れ）を確認し、あれば直す（ユーザーの常設指示）。確認用に開いたタブは閉じる。
  4. `design\CANVASES.md` に 日付・タイトル・URL・案・状態 を追記し、リンクと各案の狙いを返す。
  - コンセプトが無い・「おまかせ」なら聞き返さず、現行踏襲で案を作る。
- **「デザイン直して（指示）」** → 直近（または指定）のキャンバスを**更新**する（新規作成しない）。ユーザーがキャンバス上で手編集している可能性があるので、変更するアートボードは読み直してから直す。直した後は 3 と同じ確認をする。
- **「（案名）で実装して」** → 指定キャンバスを Artifact `read` で読み、その案のアートボード（`project/*.dc.html`）を SwiftUI へ移植する（下の「移植時の注意」「レイアウト収まり確認」に従う）。`CANVASES.md` の状態を「実装済み（コミット）」に更新。
- **テスト扱い**と言われたキャンバスは実装せず、`CANVASES.md` の状態を「保留」にする。
- キャンバスは非公開で作られる。他人に見せるときはユーザーがページの共有メニューから共有する（Claude Code からは共有設定を変えられない）。

### 予備ルート：Claude Design アプリを手で使う場合（従来のファイル受け渡し）
| 方向 | パス | 役割 |
|---|---|---|
| 恒久ルール | `C:\Users\Tadashi\Downloads\design\DESIGN_RULES.md` | Design に一度貼る恒久ルール（データ制約・崩れ防止・レイアウト鉄則・トークン）。Code が更新したらここに反映。基本ルートでも Claude Code が参照する |
| Code → Design | `C:\Users\Tadashi\Downloads\design\PROMPT.md` | Claude Code が現状レイアウトをまとめてここに **上書き** する。ユーザーは開いてコピーするだけ |
| Design → Code | `C:\Users\Tadashi\Downloads\design\MotoDash.dc.html` | ユーザーが Claude Design の出力 HTML をここに **上書き保存**。Claude Code はここを読んで SwiftUI へ移植 |
| キャンバス台帳 | `C:\Users\Tadashi\Downloads\design\CANVASES.md` | 基本ルートで作ったキャンバスの一覧（Claude Code が追記・更新） |
| 仕様参照 | `C:\Users\Tadashi\Downloads\design\README.md` | デザイントークン・状態色の正典 |

- **「デザイン用プロンプト出して」** → `App/UI/DashboardView.swift`（とマップ画面）の現状（レイアウト構成・サイズ・トークン・状態色）を読み取り、`design\PROMPT.md` に完結型プロンプトとして上書き。**必ず「# SwiftUI 実装制約（レイアウト崩れ防止）」セクションを含める**（実機 pt キャンバス固定 / SF Pro 字幅の余白 / 素直な flex のみ / overflow 非依存）。最後の「# 私のデザインコンセプト」欄は空にしておき、ユーザーがそこだけ書き換えて使う。完了後「PROMPT.md を開いてコピーしてください」と返す。
- **「デザイン更新して」** → `design\MotoDash.dc.html` を読み、現行 SwiftUI（`DashboardView.swift`・`MapDashView.swift`・`Theme.swift`・`GaugeBar.swift`）との差分を実装。レイアウト変更のみで、データ配線やビジネスロジックは触らない。ファイルが前回反映時から更新されていなければ、反映せずにそう伝える。
- **「デザイン反映して」**（どちらのルートか言わなかった場合）→ `MotoDash.dc.html` の更新日時と `CANVASES.md` の最新エントリを比べ、新しい方を使う。

### 共通
- 実装した変更は `feat/...` ブランチにコミット→必要なら main へマージ→push（CI ビルドのため）。

### 移植時の注意
- HTML をそのまま使わない。SwiftUI ネイティブ描画（Shape / Path / Text / SF Symbols）で再現する。
- デザイントークンは `Theme.swift` の `Palette` / `StateColor` に集約。色を直書きしない。
- アクセント色 `#A6F226` = `Color(red: 0.65, green: 0.95, blue: 0.15)`。

## レイアウト収まり確認（必須ルール）

**機能の追加・削除・レイアウト変更を行った後は、必ず以下を確認して再調整すること。**

### 確認項目
1. **横画面（812×375 pt）**: セーフエリアは無視し、画面端からノッチ側 46pt・反対側 18pt（向きで左右反転）の内側に全要素が収まっているか。速度数字・TPMS カード・下辺ストリップが重なったり見切れていないか。
2. **縦画面（375×812 pt）**: ステータスバー〜ゲージ〜ヒーロー速度〜カードエリアの合計高さが画面内に収まっているか（下に Spacer が残っているか確認）。
3. **カード固定高さ**: `pTPMSCard` / `pDataCard` は h70pt 固定。内容を増やした場合は高さを変更し、カードエリア全体の合計高さを再計算する。
4. **下辺ストリップ（横画面）**: h80pt ストリップ + top padding 22pt + bottom 40pt の合計が、速度+TPMS エリアと干渉しないか（中段の余りは 4pt のみ）。

### 再調整の手順
- 収まらない場合は padding / spacing / フォントサイズ を段階的に縮小して収める。
- カード高さを変えた場合は、**両画面のカードエリア合計高さをコメントで明記**してコードに残す。
- 調整後、変更内容をコミットメッセージに記載する。

## リポジトリ
- GitHub: https://github.com/sunbalkan-star/motodash.git
- ローカル: `C:\Users\Tadashi\Downloads\ios-template`
- push すると GitHub Actions が unsigned IPA をビルド。実機確認は AltStore 経由。
