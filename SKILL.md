---
name: form-submit
description: >
  SES企業パートナー候補のお問い合わせフォームにPlaywright MCPで定型データを
  自動入力・一括送信する。Google Spreadsheetの企業リストから未送信分を自動取得し、
  フォーム検出→入力→送信→スプレッドシート更新を自動ループする。
  ユーザーが「フォーム送信」「お問い合わせ送信」「パートナーフォーム」「営業フォーム」
  「一括送信」「form submit」「フォーム自動入力」と言ったとき、またはSES企業への
  問い合わせやパートナー提携の営業活動に言及したときに必ずこのスキルを使用すること。
  /form-submit で直接呼び出し可能。
argument-hint: "[--company 企業名] [--max N]"
---

# フォーム自動送信スキル

SES企業のお問い合わせフォームを自動巡回し、定型データを入力・送信するスキル。
Playwright MCP のブラウザ操作を使ってフォームの検出・入力・送信・スプレッドシート更新を自動ループする。

---

## 呼び出し方

```
/form-submit                            → 未送信企業を最大 config.options.maxCompanies 件まで連続処理
/form-submit --company サイバーフリークス  → 特定企業のみ処理
/form-submit --max 30                   → 最大30社まで処理（config.options.maxCompanies を上書き）
/form-submit --max 10 --company 企業名   → 組み合わせも可能
```

引数: $ARGUMENTS
- `--company {企業名}` が指定された場合、その企業のみを処理対象とする
- `--max {N}` が指定された場合、処理する最大企業数を N に設定する（config.options.maxCompanies より優先）
- 引数なしの場合、未送信企業を先頭から順に config.options.maxCompanies 件まで処理する

---

## 設定ファイル

### `~/.claude/form-submit/config.json`

実行前に必ず Read ツールで読み込む。ネスト構造の詳細は `references/config-schema.md` を参照。

主要キー: `spreadsheet.url`, `spreadsheet.columns`, `spreadsheet.sheet`, `options.*`, `commonData`

### `~/.claude/form-submit/field-log.json`

未知フィールドへの対応を永続記録。実行前に読み込み、ループ終了後に保存。存在しなければ `{ "entries": [] }` として扱う。

### `docs/error-log.json`

失敗履歴の蓄積ファイル。セッションごとに追記・マージ。実行前に読み込み、ループ終了後に保存。存在しなければ `{ "entries": [] }` として扱う。

### `docs/error-rules.json`

`error-log.json` で3回以上発生したエラーパターンの自動スキップルール。フォームURL遷移前に参照。存在しなければ `{ "rules": [] }` として扱う。

---

## 全体フロー（バッチ処理）

### ステップ 1: 設定・ログ読み込み

まず `$ARGUMENTS` を解析する：
- `--max {N}` が含まれていれば、その値を `maxCompanies` として記憶する（config より優先）
- `--company {企業名}` が含まれていれば、その企業のみを処理対象とする

Read ツールで以下を読み込む：
1. `~/.claude/form-submit/config.json` → `spreadsheet.url`、`options`、`commonData` を取得。`--max` 引数があれば `options.maxCompanies` を上書きする
2. `~/.claude/form-submit/field-log.json` → 未知フィールドの過去回答を取得
3. `docs/progress.json` → 前回の最終処理行を取得
4. `docs/error-log.json` → 過去の失敗履歴を取得
5. `docs/error-rules.json` → 自動スキップルールを取得

6. Playwright MCP のプロファイル設定を確認する:
   - Playwright MCP の設定ファイル（`~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json`）を Read ツールで読み込む
   - `--user-data-dir` 引数が設定されているか確認する
   - 設定されていない場合: ユーザーに「Chromeプロファイルが未設定です。reCAPTCHA通過率が大幅に下がりますが続行しますか？」と確認する
   - 設定されている場合: プロファイルパスが存在するか確認し、問題なければ続行する

**progress.json が存在する場合:**
ユーザーに選択肢を提示する：
```
前回は行{lastRow}（{lastCompany}）まで処理済みです。
[1] 続きから処理する（行{lastRow + 1}から）
[2] 開始行を指定する
```

**progress.json が存在しない場合:**
ユーザーに開始行を直接聞く：
```
progress.json が見つかりません。何行目から開始しますか？
```

### ステップ 2: Googleログイン状態の確認

1. `browser_navigate` で `https://accounts.google.com` に遷移し `browser_snapshot` で状態確認
2. ログイン済み → ステップ3へ
3. アカウント選択画面 → ユーザーにブラウザでの選択を依頼し、完了後 `browser_snapshot` で再確認
4. 未ログイン → ユーザーにログインを依頼し、完了後 `browser_snapshot` で再確認

### ステップ 3: スプレッドシートから企業リスト取得

1. `browser_navigate` で `config.spreadsheet.url` に遷移する
2. `browser_run_code` でJavaScriptを実行し、スプレッドシートから必要なデータのみ取得する（`browser_snapshot` の全DOMは数千〜数万トークンになるため、JS経由で必要データのみ抽出する）：
   ```javascript
   // スプレッドシートのテーブルから企業名・送信済み・URLを抽出
   const rows = document.querySelectorAll('table tbody tr');
   const data = Array.from(rows).map(row => {
     const cells = row.querySelectorAll('td');
     return { company: cells[0]?.textContent?.trim(), submitted: cells[1]?.textContent?.trim(), url: cells[2]?.textContent?.trim() };
   }).filter(r => r.company);
   JSON.stringify(data);
   ```
   ※ 実際のスプレッドシートのDOM構造に応じてセレクタを調整する
3. B列が未チェック（空欄またはFALSE）の行を抽出し、企業リストを作成する
4. `--company` オプション指定時は該当企業名の行のみを対象とする

### ステップ 4: 企業ループ開始

未送信企業を先頭から順番に処理する。バッチ処理の効率を最大化するため、個々のフォーム入力・送信にはユーザー確認を挟まない（未知フィールドへの質問のみが中断ポイント）。

進捗は都度表示してユーザーが状況を把握できるようにする：

```
[3/150] 株式会社XXX を処理中...
```

成功した企業名はメモリ内リストに追記し、ループ終了後にスプレッドシートをまとめて更新する（1社ごとにスプレッドシートへ戻るとブラウザ往復コストが高いため）。

---

## 1社あたりのステップ

### ステップ 5: フォームURLに遷移

フォームURLに遷移する前に `error-rules.json` を確認する：

1. `error-rules.json` の `rules` から、現在の企業名に一致するルールを検索する
2. 一致するルールが存在し `action` が `"skip"` の場合:
   スキップしてエラーリストに「自動スキップ: {reason}」として記録し、次の企業に進む
3. 一致するルールがない場合: `browser_navigate` でC列のURLに遷移する

### ステップ 6: フォーム検出

1. `browser_snapshot` でページ構造を取得する
2. `<input>` / `<textarea>` / `<select>` 等のフォームフィールドが存在するか確認する
3. フィールドが見つかった場合: そのままステップ7へ進む
4. フィールドが見つからない場合: フォーム探索ロジック（後述）を実行する

### ステップ 7: フィールド照合

意味的にマッチングする。詳細は `references/config-schema.md` のマッチングロジック参照。

### ステップ 8: 未知フィールド対応

各フィールドについて以下を判断する：

**マッチ済みフィールド:** `commonData` の対応値を自動使用する

**未知フィールド（`commonData` にも意味的に近いキーがない場合）:**
1. `field-log.json` の `entries` を検索し、同じまたは類似した `fieldLabel` のエントリを探す
2. ログに記録あり → そのエントリの `value` を使用し、`count` を +1、`companies` に当該企業名を追加する
3. ログに記録なし → `AskUserQuestion` ツールでユーザーに質問する：

```
[未知フィールド] 「{フィールドラベル}」への入力値を教えてください。
（このフォームでは選択肢: {選択肢リスト} があります）
```

ユーザーの回答を `field-log.json` に新規エントリとして追加する（`count: 1`）。

### ステップ 9: フォーム入力

`browser_fill_form` を優先使用し、複数のテキストフィールドを1回のAPI呼び出しでまとめて入力する。
`browser_fill_form` で対応できないフィールドは個別に処理する：
- チェックボックス・ラジオボタン: `browser_click`
- セレクトボックス: `browser_select_option`

バッチ処理の効率を最大化するため、個々の入力にユーザー確認は挟まない。

### ステップ 10: 送信前スクリーンショット

フォーム入力完了後、送信前に `browser_take_screenshot` で撮影する。
保存先: `~/.claude/form-submit/screenshots/{企業名}/before.png`（企業名の `/` 等は `_` に置換）

### ステップ 11: 送信・確認画面対応・結果確認

日本のフォームは「確認画面→送信」の2段階が一般的なため、完了まで最大3回のクリックを試みる：

1. 送信ボタン（「送信」「Submit」「確認する」「次へ」等）を `browser_click` でクリック
2. `browser_snapshot` でページ状態を確認する
3. **確認画面の場合**: 「送信する」「上記内容で送信」「確定する」等のボタンを `browser_click` でクリックし、再度 `browser_snapshot` で確認（最大3回）
4. **完了画面の場合**（「送信完了」「ありがとうございました」等、またはURL が `/thanks`、`/complete` 等に遷移）:
   - `config.options.screenshotAfterSubmit` が `true` なら `browser_take_screenshot` で撮影（保存先: `~/.claude/form-submit/screenshots/{企業名}/after.png`）
   - 成功として記録
5. 成功と判断できない場合はステップ 12（リトライ＆エラー時の処理）に進む

### ステップ 12: リトライ＆エラー時の処理

**リトライルール（最大3回）:**

エラーが発生した場合、同じ企業に対して最大3回までリトライする。

1. 1回目の試行でエラー → ページをリロードして2回目を試行
2. 2回目もエラー → フォームURLに再遷移して3回目を試行
3. 3回目もエラー → その企業をパス（スキップ）する

リトライ中に成功した場合は、成功企業リストに追加する。

**3回失敗した場合:**
- エラー内容（企業名・エラー種別・詳細・試行回数）をメモリ内のエラーリストに追加する
- `error-log.json` に失敗を記録する（同じ `company` + `errorType` の既存エントリがあれば `count` +1・`sessions` に追記、なければ新規追加）
- スプレッドシートのB列は更新しない
- 次の企業の処理に進む（ステップ 5 に戻る）

`config.options.skipOnError: false` の場合:
- 3回リトライしても失敗した時点でバッチ処理を停止する

---

## ループ終了後の処理

### ステップ 13: スプレッドシートを一括更新

全社処理完了後にまとめてB列を更新する：

1. `browser_navigate` で `config.spreadsheet.url` に遷移する
2. `browser_run_code` でJavaScriptを実行し、成功企業のチェックボックスを一括操作する：
   - メモリ内の成功企業リストに基づき、A列を検索して各企業の行を特定
   - B列のチェックボックスをクリックしてONにする
   ※ Google Spreadsheetの場合、チェックボックスのクリックはDOM操作では反映されないことがあるため、`browser_click` でのクリックにフォールバックする
3. `browser_run_code` で更新結果を確認する

### ステップ 14: フィールドログ保存

処理中に更新した `field-log.json` の内容を Write ツールで保存する。
パス: `~/.claude/form-submit/field-log.json`

### ステップ 15: エラーログ保存

処理中に更新した `error-log.json` を `docs/error-log.json` に Write ツールで保存する。

### ステップ 16: エラールール昇格提案

`error-log.json` の `entries` の中で `count >= 3` のエントリを抽出し、
かつ `error-rules.json` にまだルール化されていないものを以下の形式で提案する：

```
以下のエラーが3回以上発生しています。自動スキップルールに追加しますか？

- イプソス株式会社: CAPTCHA検出（3回発生）
- 株式会社XXX: タイムアウト（4回発生）

[Y] すべて追加  [n] スキップ  または追加する企業を番号で指定してください
```

ユーザーが承認した場合は `error-rules.json` に該当ルールを追加して `docs/error-rules.json` に Write ツールで保存する。

### ステップ 17: config昇格提案

`field-log.json` の `entries` の中で `count >= 3` のエントリを抽出し、以下の形式でユーザーに提案する：

```
以下のフィールドが3回以上出現しています。config.json の commonData に追加しますか？

- 「部署名」→ 値: 営業部（5回出現）
- 「ご担当者名カナ」→ 値: ヤマダ タロウ（3回出現）

[Y] すべて追加  [n] スキップ  または追加するフィールドを番号で指定してください
```

ユーザーが承認した場合は `config.json` の `commonData` に該当キーバリューを追加して Write ツールで保存する。

### ステップ 18: 進捗記録

セッション終了時、スプレッドシートの最後に処理した行番号と各企業の結果を `docs/progress.json` に記録する。
次回セッション開始時にこのファイルを読み込み、前回の続きから処理を再開できるようにする。

lastRow, lastCompany, updatedAt を記録する。

### ステップ 19: 最終レポート表示

処理範囲・成功数（リトライ後成功含む）・失敗数・スキップ数を集計表示する。
成功/失敗の詳細（行番号・企業名・結果）を一覧表示する。
config昇格候補・エラールール昇格候補の処理結果も表示する。
進捗保存先（progress.json）を表示する。

---

## フォーム探索ロジック

URLがフォームページでない場合（ステップ6でフォームが見つからない場合）に実行する。

1. `browser_snapshot` の現在のページから以下のキーワードを含むリンクを検索する：
   「お問い合わせ」「Contact」「パートナー」「協業」「提携」「SES」「採用」「ビジネス」
2. 最も関連性が高いリンクを選択し、`browser_click` で遷移する
3. 遷移先で `browser_snapshot` を再取得し、フォームフィールドの有無を確認する
4. フォームが見つかればステップ7へ進む
5. 1階層目でも見つからない場合: 同様のキーワードで2階層目まで探索する
6. 2階層探索してもフォームが見つからない場合: スキップしてエラーリストに「フォーム未検出」として記録する

---

## エラーハンドリング

エラーは **リトライ対象** と **即スキップ** に分類される。リトライ対象のエラーはステップ 12 のリトライルール（最大3回）に従い、即スキップのエラーはリトライせず次の企業に進む。

### CAPTCHA対応

`browser_snapshot` でCAPTCHA要素を検出した場合、以下の対応を行う：

| CAPTCHAの種類 | 対応 |
|---|---|
| reCAPTCHA v2 | チェックボックスをクリック→通過すれば続行、画像チャレンジが出たら即スキップ |
| reCAPTCHA v3 | そのまま送信→CAPTCHAエラー時はステップ12でリトライ |
| hCaptcha/その他 | 即スキップ |

### タイムアウト

`browser_navigate` または `browser_snapshot` が想定時間内に完了しない場合:
→ ステップ 12（リトライ＆エラー時の処理）に進む。3回リトライしても失敗した場合は「タイムアウト」としてエラーリストに記録する

### ログイン要求

`browser_snapshot` の結果にログインフォーム（`type="password"` フィールドや「ログイン」「サインイン」ボタン）が含まれる場合:
→ スキップしてエラーリストに「ログイン要求」として記録する

### 送信エラー

送信後のページに「エラー」「入力内容をご確認」「必須項目」「送信に失敗」等のメッセージが含まれる場合、またはフォームが再表示されている場合:
→ ステップ 12（リトライ＆エラー時の処理）に進む。3回リトライしても失敗した場合は「送信エラー: {エラーメッセージ内容}」としてエラーリストに記録する

### フォーム未検出

→ フォーム探索ロジック（上記）のステップ6に従う

---

## 前提条件（reCAPTCHA 対策）

- Playwright MCP は既存の Chrome プロファイル（Google ログイン済み）を使用する設定になっている
- **スキル実行前に Google Chrome を閉じること**（プロファイルロック競合を回避するため）
- Chrome を閉じ忘れた場合はエラーになるので、ユーザーに閉じるよう案内する

## 人間的な操作パターン

bot 検出を回避するため、フォーム入力開始前に `browser_run_code` で 1〜2秒の待機を1回だけ実施する。
入力自体は `browser_fill_form` でまとめて実行し、フィールド間の個別遅延は不要。
送信ボタンクリック前にも 1〜2秒の待機を実施する。

---

## 注意事項

- スプレッドシートの操作は Google Sheets API ではなく、Playwright MCP 経由のブラウザ操作で行う
- 未知フィールドへの質問には `AskUserQuestion` ツールを使用する
- 処理中は成功企業リストをメモリに保持し、ループ終了後にスプレッドシートへ一括反映する（毎回戻ると非効率）
- 独立したツール呼び出しは1ターンでまとめて実行する（例: navigate後のsnapshot取得など依存関係があるものは除く）

---

## 参考リソース

- [設定ファイル スキーマリファレンス](references/config-schema.md) — config.json / field-log.json / error-log.json / error-rules.json の詳細なフィールド定義・設定例
