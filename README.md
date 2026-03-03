# FormPilot

SES企業向けお問い合わせフォーム自動送信スキル。Claude Code のスキルとして動作し、Playwright MCP でブラウザ操作を行う。Google Spreadsheet で管理した企業リストから未送信分を自動取得し、フォームの検出・入力・送信・スプレッドシート更新を自動ループする。

---

## 特徴

- **意味的フィールドマッチング** — フォームのラベル名と commonData のキーを LLM が意味的に照合するため、表記ゆれ（「御社名」「貴社名」「Company」等）に対応
- **未知フィールドの学習** — commonData に対応するキーがないフィールドはユーザーに質問し、回答を `field-log.json` に記録して次回以降に自動流用
- **config 昇格提案** — 同じフィールドが3回以上出現した場合、`config.json` の commonData への追加を自動提案
- **確認画面の自動対応** — 日本のフォームに多い「入力→確認→送信」の2段階フローを自動処理
- **バッチ処理** — 1バッチで最大 150 社（設定変更可能）を連続処理し、スプレッドシートを一括更新
- **エラースキップ** — CAPTCHA・タイムアウト・ログイン要求等を検出した場合はスキップして次の企業へ
- **フォーム自動探索** — 指定 URL がフォームページでない場合、関連リンクを最大2階層まで探索

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
mkdir -p ~/.claude/form-submit
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

スキーマの詳細と設定例は [`references/config-schema.md`](references/config-schema.md) を参照。

### 5. field-log.json を作成

```bash
echo '{"entries": []}' > ~/.claude/form-submit/field-log.json
```

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
└── references/
    └── config-schema.md      # config.json および field-log.json のスキーマリファレンス
```

実行時に使用する設定ファイルは `~/.claude/form-submit/` に配置する（リポジトリ外）。

```
~/.claude/form-submit/
├── config.json               # スプレッドシートURL・commonData・オプション
└── field-log.json            # 未知フィールドの回答ログ
```

---

## ライセンス

MIT
