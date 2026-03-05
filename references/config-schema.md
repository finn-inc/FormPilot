# form-submit 設定ファイル スキーマリファレンス

`~/.claude/form-submit/config.json` の設定スキーマと設定例を説明するリファレンスドキュメント。

---

## 設定ファイルの全体構造

```json
{
  "spreadsheet": {
    "url": "(Google SpreadsheetのURL)",
    "columns": {
      "companyName": "A",
      "submitted": "B",
      "formUrl": "C"
    },
    "sheet": "シート1"
  },
  "commonData": {
    "会社名": "...",
    "会社フリガナ": "...",
    "氏名": "...",
    "姓": "...",
    "名": "...",
    "フリガナ（ひらがな）": "...",
    "フリガナ（カタカナ）": "...",
    "メールアドレス": "...",
    "担当者メールアドレス": "...",
    "電話番号": "...",
    "部署名": "...",
    "役職": "...",
    "お問い合わせ内容": "...",
    "お問い合わせ種別": "..."
  },
  "options": {
    "confirmBeforeSubmit": false,
    "screenshotAfterSubmit": true,
    "skipOnError": true,
    "maxCompanies": 30
  }
}
```

---

## 各フィールドの説明

### spreadsheet

Google Spreadsheet の接続情報と列構成を定義する。

| フィールド | 型 | 説明 |
|---|---|---|
| `url` | string | 対象の Google Spreadsheet の URL。企業リストを管理するシート。 |
| `columns` | object | 各列の役割を定義するオブジェクト。 |
| `sheet` | string | 対象シート名。デフォルト: `"シート1"` |

#### columns の詳細

| フィールド | 型 | デフォルト | 説明 |
|---|---|---|---|
| `companyName` | string | `"A"` | 企業名の列 |
| `submitted` | string | `"B"` | 送信済みフラグの列。チェックボックス形式で管理する。 |
| `formUrl` | string | `"C"` | お問い合わせフォームの URL の列 |

---

### commonData

全社共通の入力データ。キーはフォームのフィールドラベルとの**意味的マッチング**に使用される。

任意のキー・値を追加可能。フィールドログで頻出するフィールドは自動でここに昇格提案される（count が 3 以上で候補）。

#### マッチングロジックの詳細

commonData のキーとフォームのフィールドラベルの対応は、**LLM（Claude 自身）が意味的に判断する**。単純な文字列の一致ではなく、ラベルの意味・文脈を理解したうえで最適なキーを選択する。

**動作の原則:**

- **意味的対応の認識**: 表記が異なっていても同じ意味を指すラベルは同一として扱う。例えば config に `"会社名"` があれば、フォーム上の「御社名」「貴社名」「Company Name」「企業名」はすべて対応すると判断する。
- **セレクトボックスへの対応**: フィールドがセレクトボックスの場合、commonData の値に意味的に最も近い選択肢を選ぶ。例えば `"お問い合わせ種別": "資料請求"` に対して「資料のご請求」という選択肢があれば、それを選択する。
- **テキストエリアへの対応**: テキストエリアには改行を含む長文もそのまま入力する。commonData の値に `\n` が含まれていれば、実際の改行として扱う。
- **マッチしない場合**: 対応するキーが commonData に存在しないフィールドは、field-log.json に記録して後続の対応を促す。

#### マッチング例

| config のキー | マッチするフォームラベルの例 |
|---|---|
| `"会社名"` | 「御社名」「貴社名」「Company」「企業名」等 |
| `"氏名"` | 「お名前」「Name」「ご担当者名」「担当者氏名」等 |
| `"姓"` / `"名"` | 「苗字」「Last Name」/「名前」「First Name」等 |
| `"メールアドレス"` | 「E-mail」「email」「メール」「連絡先メール」等 |
| `"電話番号"` | 「TEL」「お電話番号」「Phone」「連絡先電話番号」等 |
| `"フリガナ（カタカナ）"` | 「フリガナ」「カナ」「お名前（カタカナ）」等 |
| `"フリガナ（ひらがな）"` | 「ふりがな」「かな」「お名前（ひらがな）」等 |
| `"お問い合わせ内容"` | 「お問い合わせ詳細」「ご要望」「メッセージ」「備考」等 |

---

### options

実行時の動作オプションを制御する。

| フィールド | 型 | デフォルト | 説明 |
|---|---|---|---|
| `confirmBeforeSubmit` | boolean | `false` | 送信前に毎回確認するか |
| `screenshotAfterSubmit` | boolean | `true` | 送信後にスクリーンショットを撮影するか |
| `skipOnError` | boolean | `true` | エラー発生時にスキップして次の企業に進むか |
| `maxCompanies` | number | `30` | 1 回の実行で処理する最大企業数 |

---

## フィールドログ（field-log.json）のスキーマ

フォーム送信時に検出されたフィールド情報を蓄積するログファイル。
パス: `~/.claude/form-submit/field-log.json`

### 構造

```json
{
  "entries": [
    {
      "fieldLabel": "(フォーム上のフィールドラベル)",
      "category": "(意味カテゴリ: department, position, url 等)",
      "value": "(ユーザーが入力した値)",
      "count": 1,
      "companies": ["(出現した企業名)"]
    }
  ]
}
```

### 各フィールドの説明

| フィールド | 型 | 説明 |
|---|---|---|
| `fieldLabel` | string | フォーム上で検出されたフィールドのラベルテキスト |
| `category` | string | LLM が判断した意味カテゴリ。同じ意味のフィールドをグループ化するために使用する（例: `department`, `position`, `url`）。 |
| `value` | string | そのフィールドに入力する値 |
| `count` | number | 出現回数。**3 以上で config への昇格候補**となる。 |
| `companies` | string[] | 出現した企業名のリスト |

### category フィールドのガイドライン

category はフィールドの意味を表す識別子で、LLM がフォームのラベルから判断して付与する。同じ意味のフィールドを異なるフォームをまたいで集計するために使用するため、表記ゆれを吸収した統一的な値を設定する。

| category 値 | 対象フィールドの例 |
|---|---|
| `department` | 部署名・所属部署・担当部署 |
| `position` | 役職・職位・肩書き |
| `inquiry_type` | お問い合わせ種別・お問い合わせカテゴリ・ご用件 |
| `company_url` | 会社URL・企業サイト・ホームページURL |
| `employee_count` | 従業員数・社員数・会社規模 |
| `how_found` | 弊社を知ったきっかけ・本サービスを知ったルート・参照元 |
| `other` | 上記いずれにも該当しない雑多なフィールド |

---

## エラーログ（error-log.json）のスキーマ

フォーム送信時に発生したエラーの履歴を蓄積するログファイル。セッションごとに上書きせず追記・マージする。
パス: `docs/error-log.json`

### 構造

```json
{
  "entries": [
    {
      "errorType": "(エラー種別)",
      "company": "(企業名)",
      "formUrl": "(フォームURL)",
      "count": 1,
      "lastOccurrence": "2026-03-04T14:57:00+09:00",
      "sessions": ["2026-03-04"]
    }
  ]
}
```

### 各フィールドの説明

| フィールド | 型 | 説明 |
|---|---|---|
| `errorType` | string | エラーの種別。「CAPTCHA検出」「タイムアウト」「送信エラー」「フォーム未検出」「ログイン要求」等 |
| `company` | string | エラーが発生した企業名 |
| `formUrl` | string | エラーが発生したフォームのURL |
| `count` | number | 同じ `company` + `errorType` の組み合わせでの発生回数。**3 以上で error-rules への昇格候補**となる |
| `lastOccurrence` | string | 最後にエラーが発生した日時（ISO 8601形式） |
| `sessions` | string[] | エラーが発生したセッションの日付リスト |

### マージルール

- 同じ `company` + `errorType` の組み合わせで既存エントリがあれば `count` を +1、`sessions` に現在の日付を追記、`lastOccurrence` を更新する
- 新規の組み合わせなら新規エントリを追加する
- ファイルが存在しない場合は `{ "entries": [] }` として扱う

---

## エラールール（error-rules.json）のスキーマ

`error-log.json` で `count >= 3` になったエラーパターンから昇格した自動スキップルール。
スキル実行時にフォームURL遷移前に参照し、該当企業・エラーパターンは自動スキップする。
パス: `docs/error-rules.json`

### 構造

```json
{
  "rules": [
    {
      "errorType": "(エラー種別)",
      "company": "(企業名)",
      "formUrl": "(フォームURL)",
      "action": "skip",
      "reason": "(昇格理由)",
      "createdAt": "2026-03-04T15:00:00+09:00"
    }
  ]
}
```

### 各フィールドの説明

| フィールド | 型 | 説明 |
|---|---|---|
| `errorType` | string | エラーの種別。error-log.json の `errorType` と同じ値 |
| `company` | string | 対象企業名 |
| `formUrl` | string | 対象フォームのURL |
| `action` | string | ルールのアクション。現在は `"skip"`（自動スキップ）固定。将来的に拡張可能 |
| `reason` | string | ルール昇格の理由（例: 「CAPTCHA検出が3回以上発生」） |
| `createdAt` | string | ルールが作成された日時（ISO 8601形式） |

### ルール照合ロジック

1. スキル実行時、フォームURL遷移前に `error-rules.json` の `rules` を走査する
2. 現在の企業名と一致する `company` のルールが存在し、`action` が `"skip"` の場合、その企業をスキップする
3. スキップした場合、エラーリストに「自動スキップ: {reason}」として記録する
