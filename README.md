# FormPilot

Spreadsheet の企業リストからお問い合わせフォームへ自動入力・送信する Claude Code スキル。

---

## 特徴

| カテゴリ | 機能 |
|---|---|
| **入力** | LLM による意味的フィールドマッチング（表記ゆれ自動対応）、確認画面の自動処理 |
| **学習** | 未知フィールドを質問→記録→次回自動流用、3回以上出現で config 昇格提案 |
| **耐障害** | 最大3回リトライ、reCAPTCHA v2/v3 対応、3回失敗で自動スキップルール化 |
| **運用** | 最大150社バッチ処理、進捗記録で中断再開、送信前後スクリーンショット |

---

## 必要環境

| 必要なもの | 説明 |
|---|---|
| Claude Code | スキルの実行環境 |
| Playwright MCP サーバー | ブラウザ操作に使用（`mcp__playwright__*` ツール群） |
| Google Spreadsheet | 企業名・送信済みフラグ・フォームURLを管理するリスト |

---

## セットアップ

### クイックスタート（推奨）

```bash
git clone https://github.com/your-username/FormPilot.git
cd FormPilot
bash setup.sh
```

`setup.sh` が以下を自動で行う（冪等・既存ファイルは上書きしない）：

1. 前提条件チェック（`claude`, `npx`）
2. スキルのシンボリックリンク作成（`~/.claude/skills/form-submit`）
3. 設定・企業データディレクトリ作成（`company/`）
4. `config.json` テンプレート生成
5. `field-log.json` 初期ファイル生成
6. Playwright MCP 設定確認・案内

セットアップ完了後、`~/.claude/form-submit/config.json` を編集して自分の情報を入力する。送信データは `company/`（プロジェクトルート）に企業別で保存される。

スキーマの詳細と設定例は [`references/config-schema.example.md`](references/config-schema.example.md) を参照。

### Chrome を閉じてからスキルを実行

Playwright MCP は既存の Chrome プロファイルを再利用して reCAPTCHA の信頼スコアを確保している。Chrome と Playwright が同じプロファイルを同時使用できないため、**スキル実行前に Google Chrome を完全に閉じること**。

---

## 使い方

```
/form-submit                       未送信企業を maxCompanies 件まで連続処理
/form-submit --max 30              最大30社まで処理（config の maxCompanies を上書き）
/form-submit --company <企業名>     指定した企業のみ処理
```

---

## ディレクトリ構成

```
FormPilot/
├── setup.sh                  # セットアップスクリプト（冪等）
├── SKILL.md                  # スキル定義（Claude Code が読み込む）
├── docs/
│   ├── progress.json         # 前回の続きから再開するための進捗記録
│   ├── error-log.json        # セッション横断の失敗履歴
│   └── error-rules.json      # 3回以上失敗した企業の自動スキップルール
└── references/
    ├── config-schema.md      # 設定ファイルのスキーマリファレンス
    └── config-schema.example.md  # 設定例
```

実行時に使用する設定ファイルは `~/.claude/form-submit/` に配置する（リポジトリ外）。

```
~/.claude/form-submit/
├── config.json               # スプレッドシートURL・commonData・オプション
└── field-log.json            # 未知フィールドの回答ログ（自動作成）

company/                        # 企業別の送信データ（プロジェクトルート、git管理外）
└── {企業名}/
    ├── before.json           # 送信前の入力内容（JSON）
    └── after.png             # 送信後のスクリーンショット
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
