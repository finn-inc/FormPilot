# FormPilot

SES企業向けお問い合わせフォーム自動送信スキル。Claude Code のスキルとして動作し、Playwright MCP でブラウザ操作を行う。Google Spreadsheet で管理した企業リストから未送信分を自動取得し、フォームの検出・入力・送信・スプレッドシート更新を自動ループする。

---

## 特徴

- **意味的フィールドマッチング** — フォームのラベル名と commonData のキーを LLM が意味的に照合するため、表記ゆれ（「御社名」「貴社名」「Company」等）に対応
- **未知フィールドの学習** — commonData に対応するキーがないフィールドはユーザーに質問し、回答を `field-log.json` に記録して次回以降に自動流用
- **config 昇格提案** — 同じフィールドが3回以上出現した場合、`config.json` の commonData への追加を自動提案
- **確認画面の自動対応** — 日本のフォームに多い「入力→確認→送信」の2段階フローを自動処理
- **バッチ処理** — 1バッチで最大 150 社（設定変更可能）を連続処理し、スプレッドシートを一括更新
- **エラー履歴蓄積** — `docs/error-log.json` で失敗履歴をセッション横断で蓄積（上書きせず追記・マージ）
- **自動スキップルール** — `docs/error-rules.json` で3回以上失敗した企業を自動スキップ
- **進捗トラッキング** — `docs/progress.json` で前回の続きから再開可能
- **リトライロジック** — タイムアウト・送信エラー等は最大3回リトライ（リロード→再遷移→スキップ）
- **reCAPTCHA 対応** — Chrome プロファイル活用、v2（チェックボックス）自動クリック、v3（非表示型）はリトライ、hCaptcha 等はスキップ
- **フォーム自動探索** — 指定 URL がフォームページでない場合、関連リンクを最大2階層まで探索
- **人間的な操作パターン** — フィールド間 500ms〜1500ms ランダム遅延、送信前 1〜2秒待機

---

## 必要環境

| 必要なもの | 説明 |
|---|---|
| Claude Code | スキルの実行環境 |
| Playwright MCP サーバー | ブラウザ操作に使用（`mcp__playwright__*` ツール群） |
| Google Spreadsheet | 企業名・送信済みフラグ・フォームURLを管理するリスト |

---

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/your-username/FormPilot.git
```

### 2. スキルとしてシンボリックリンクを作成

```bash
ln -s /path/to/FormPilot ~/.claude/skills/form-submit
```

### 3. 設定ディレクトリを作成

```bash
mkdir -p ~/.claude/form-submit/screenshots
```

### 4. config.json を作成

`~/.claude/form-submit/config.json` を以下の内容で作成し、各値を入力する。

```json
{
  "spreadsheet": {
    "url": "https://docs.google.com/spreadsheets/d/XXXXXX/edit",
    "columns": {
      "companyName": "A",
      "submitted": "B",
      "formUrl": "C"
    },
    "sheet": "シート1"
  },
  "commonData": {
    "会社名": "株式会社サンプル",
    "氏名": "山田 太郎",
    "フリガナ": "ヤマダ タロウ",
    "メールアドレス": "yamada@example.com",
    "電話番号": "03-1234-5678",
    "お問い合わせ内容": "資料のご送付をお願いしたく存じます。"
  },
  "options": {
    "confirmBeforeSubmit": false,
    "screenshotAfterSubmit": true,
    "skipOnError": true,
    "maxCompanies": 150
  }
}
```

スキーマの詳細と設定例は [`references/config-schema.example.md`](references/config-schema.example.md) を参照。
実際に使用する際は、このファイルを `references/config-schema.md` にコピーして自分の情報に書き換えること。

`field-log.json`、`docs/error-log.json`、`docs/error-rules.json` はファイルが存在しない場合にデフォルト値として自動的に扱われるため、事前作成は不要。

### 5. Chrome を閉じてからスキルを実行

Playwright MCP は既存の Chrome プロファイルを再利用して reCAPTCHA の信頼スコアを確保している。Chrome と Playwright が同じプロファイルを同時使用できないため、**スキル実行前に Google Chrome を完全に閉じること**。

---

## 使い方

```
/form-submit
```

未送信企業をスプレッドシートから取得し、`maxCompanies` 件まで連続処理する。

```
/form-submit --company <企業名>
```

指定した企業のフォームのみを処理する。

---

## ディレクトリ構成

```
FormPilot/
├── SKILL.md                  # スキル定義（Claude Code が読み込む）
├── docs/
│   ├── progress.json         # 前回の続きから再開するための進捗記録
│   ├── error-log.json        # セッション横断の失敗履歴
│   └── error-rules.json      # 3回以上失敗した企業の自動スキップルール
└── references/
    └── config-schema.md      # 設定ファイルのスキーマリファレンス
```

実行時に使用する設定ファイルは `~/.claude/form-submit/` に配置する（リポジトリ外）。

```
~/.claude/form-submit/
├── config.json               # スプレッドシートURL・commonData・オプション
├── field-log.json            # 未知フィールドの回答ログ（自動作成）
└── screenshots/              # 送信前後のスクリーンショット保存先
    ├── {企業名}_before.png
    └── {企業名}_after.png
```

---

## エラーハンドリング

エラーは **リトライ対象** と **即スキップ** に分類される。

| 分類 | エラー種別 | 動作 |
|---|---|---|
| リトライ対象 | タイムアウト | 最大3回リトライ（リロード→再遷移→スキップ） |
| リトライ対象 | 送信エラー（必須項目・入力不備等） | 最大3回リトライ |
| リトライ対象 | reCAPTCHA v3（非表示型） | 送信後にエラーが返された場合、最大3回リトライ |
| 即スキップ | CAPTCHA画像チャレンジ | リトライせずスキップ |
| 即スキップ | hCaptcha / その他CAPTCHA | リトライせずスキップ |
| 即スキップ | ログイン要求 | リトライせずスキップ |
| 即スキップ | フォーム未検出（2階層探索後） | リトライせずスキップ |

3回以上失敗した企業は `docs/error-log.json` に蓄積され、セッション終了時に `docs/error-rules.json` への昇格をユーザーに提案する。次回セッション以降、該当企業はフォーム遷移前に自動スキップされる。

---

## 設定ファイル一覧

| ファイル | 場所 | 内容 |
|---|---|---|
| `config.json` | `~/.claude/form-submit/` | スプレッドシートURL・commonData・オプション |
| `field-log.json` | `~/.claude/form-submit/` | 未知フィールドの回答ログ（自動作成） |
| `progress.json` | `docs/` | 前回の最終処理行・各社結果 |
| `error-log.json` | `docs/` | セッション横断の失敗履歴 |
| `error-rules.json` | `docs/` | 自動スキップルール |

---

## ライセンス

MIT
