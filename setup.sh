#!/usr/bin/env bash
# =============================================================================
# FormPilot セットアップスクリプト
#
# 概要:
#   FormPilot の実行に必要な設定ファイル・ディレクトリ・シンボリックリンクを
#   冪等に作成する。既存ファイルは上書きしない。
#
# 使い方:
#   bash setup.sh
#
# 実行ステップ:
#   1/7 前提条件チェック（claude, npx の存在確認）
#   2/7 スキルのシンボリックリンク作成
#   3/7 設定ディレクトリ作成
#   4/7 config.json テンプレート生成
#   5/7 field-log.json 初期ファイル生成
#   6/7 Playwright MCP 設定確認・案内
#   7/7 セットアップ完了メッセージ＋使い方表示
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# カラー出力
# tty でない場合（パイプ等）はカラーコードを無効にする
# -----------------------------------------------------------------------------
if [ -t 1 ]; then
  COLOR_GREEN="\033[0;32m"
  COLOR_YELLOW="\033[0;33m"
  COLOR_RED="\033[0;31m"
  COLOR_CYAN="\033[0;36m"
  COLOR_RESET="\033[0m"
  COLOR_BOLD="\033[1m"
else
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_RED=""
  COLOR_CYAN=""
  COLOR_RESET=""
  COLOR_BOLD=""
fi

print_success() { printf "${COLOR_GREEN}✓${COLOR_RESET} %s\n" "$*"; }
print_warn()    { printf "${COLOR_YELLOW}⚠${COLOR_RESET} %s\n" "$*"; }
print_error()   { printf "${COLOR_RED}✗${COLOR_RESET} %s\n" "$*" >&2; }
print_info()    { printf "  %s\n" "$*"; }
print_step()    { printf "\n${COLOR_BOLD}${COLOR_CYAN}[%s]${COLOR_RESET} %s\n" "$1" "$2"; }

# -----------------------------------------------------------------------------
# get_repo_root
# BASH_SOURCE[0] からスクリプト自身の絶対パスを求め、その親ディレクトリを返す
# -----------------------------------------------------------------------------
get_repo_root() {
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${script_path}"
}

# -----------------------------------------------------------------------------
# check_prerequisites
# claude と npx の存在を確認する
# -----------------------------------------------------------------------------
check_prerequisites() {
  print_step "1/7" "前提条件チェック"

  local ok=true

  if command -v claude &>/dev/null; then
    print_success "claude が見つかりました: $(command -v claude)"
  else
    print_error "claude が見つかりません。Claude Code をインストールしてください。"
    print_info "インストール: https://claude.ai/code"
    ok=false
  fi

  if command -v npx &>/dev/null; then
    print_success "npx が見つかりました: $(command -v npx)"
  else
    print_error "npx が見つかりません。Node.js をインストールしてください。"
    print_info "インストール: https://nodejs.org/"
    ok=false
  fi

  if [ "${ok}" = false ]; then
    print_error "前提条件を満たしていません。上記のツールをインストール後、再実行してください。"
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# create_skill_symlink
# ~/.claude/skills/form-submit -> リポジトリルート のシンボリックリンクを作成する
# -----------------------------------------------------------------------------
create_skill_symlink() {
  print_step "2/7" "スキルのシンボリックリンク作成"

  local repo_root="$1"
  local skills_dir="${HOME}/.claude/skills"
  local link_path="${skills_dir}/form-submit"

  # skills ディレクトリがなければ作成
  if [ ! -d "${skills_dir}" ]; then
    mkdir -p "${skills_dir}"
    print_success "ディレクトリを作成しました: ${skills_dir}"
  fi

  if [ -L "${link_path}" ]; then
    local existing_target
    existing_target="$(readlink "${link_path}")"
    if [ "${existing_target}" = "${repo_root}" ]; then
      print_success "シンボリックリンクは既に正しく設定されています: ${link_path} -> ${repo_root}"
    else
      print_warn "シンボリックリンクが異なるターゲットを指しています。上書きしません。"
      print_info "現在のリンク先: ${existing_target}"
      print_info "期待するリンク先: ${repo_root}"
      print_info "手動で修正する場合: rm \"${link_path}\" && ln -s \"${repo_root}\" \"${link_path}\""
    fi
  elif [ -e "${link_path}" ]; then
    print_warn "${link_path} はシンボリックリンクではないファイル/ディレクトリが存在します。スキップします。"
  else
    ln -s "${repo_root}" "${link_path}"
    print_success "シンボリックリンクを作成しました: ${link_path} -> ${repo_root}"
  fi
}

# -----------------------------------------------------------------------------
# create_directories
# ~/.claude/form-submit/screenshots/ を作成する
# -----------------------------------------------------------------------------
create_directories() {
  print_step "3/7" "設定ディレクトリ作成"

  local screenshots_dir="${HOME}/.claude/form-submit/screenshots"

  mkdir -p "${screenshots_dir}"
  print_success "ディレクトリを作成しました（既存の場合はスキップ）: ${screenshots_dir}"
}

# -----------------------------------------------------------------------------
# create_config_json
# ~/.claude/form-submit/config.json をプレースホルダ付きで生成する
# 既存ファイルがある場合はスキップ
# -----------------------------------------------------------------------------
create_config_json() {
  print_step "4/7" "config.json テンプレート生成"

  local config_path="${HOME}/.claude/form-submit/config.json"

  if [ -f "${config_path}" ]; then
    print_success "config.json は既に存在します。スキップします: ${config_path}"
    return
  fi

  cat > "${config_path}" <<'EOF'
{
  "spreadsheet": {
    "url": "<YOUR_GOOGLE_SPREADSHEET_URL>"
  },
  "commonData": {
    "会社名": "<YOUR_COMPANY_NAME>",
    "氏名": "<YOUR_NAME>",
    "フリガナ": "<YOUR_NAME_KANA>",
    "メールアドレス": "<YOUR_EMAIL>",
    "電話番号": "<YOUR_PHONE>",
    "お問い合わせ内容": "<YOUR_MESSAGE>"
  }
}
EOF

  print_success "config.json を生成しました: ${config_path}"
  print_info "次のステップで各フィールドを編集してください。"
}

# -----------------------------------------------------------------------------
# create_field_log
# ~/.claude/form-submit/field-log.json を生成する
# 既存ファイルがある場合はスキップ
# -----------------------------------------------------------------------------
create_field_log() {
  print_step "5/7" "field-log.json 初期ファイル生成"

  local field_log_path="${HOME}/.claude/form-submit/field-log.json"

  if [ -f "${field_log_path}" ]; then
    print_success "field-log.json は既に存在します。スキップします: ${field_log_path}"
    return
  fi

  cat > "${field_log_path}" <<'EOF'
{
  "entries": []
}
EOF

  print_success "field-log.json を生成しました: ${field_log_path}"
}

# -----------------------------------------------------------------------------
# check_playwright_mcp
# ~/.claude.json の存在と playwright キーワードの有無を確認する
# Chrome プロファイルパスが存在する場合は情報を表示する
# -----------------------------------------------------------------------------
check_playwright_mcp() {
  print_step "6/7" "Playwright MCP 設定確認"

  local claude_json="${HOME}/.claude.json"

  if [ ! -f "${claude_json}" ]; then
    print_warn "~/.claude.json が見つかりません。"
    _print_playwright_setup_guide
  else
    if grep -q "playwright" "${claude_json}" 2>/dev/null; then
      print_success "Playwright MCP が設定されています: ${claude_json}"
    else
      print_warn "Playwright MCP が ~/.claude.json に設定されていません。"
      _print_playwright_setup_guide
    fi
  fi

  # Chrome プロファイルパスの確認（macOS / Linux）
  local chrome_profile_path=""
  if [ "$(uname)" = "Darwin" ]; then
    chrome_profile_path="${HOME}/Library/Application Support/Google/Chrome"
  else
    chrome_profile_path="${HOME}/.config/google-chrome"
  fi

  if [ -d "${chrome_profile_path}" ]; then
    print_info ""
    print_info "Chrome プロファイル検出: ${chrome_profile_path}"
    print_info "user-data-dir を設定すると既存のログイン状態を利用できます"
  fi
}

# Playwright MCP 設定方法の案内を表示するヘルパー
_print_playwright_setup_guide() {
  print_info ""
  print_info "Playwright MCP が未設定です。以下を ~/.claude.json に追加してください:"
  print_info ""
  print_info '  {'
  print_info '    "mcpServers": {'
  print_info '      "playwright": {'
  print_info '        "command": "npx",'
  print_info '        "args": ["@anthropic-ai/mcp-playwright@latest"]'
  print_info '      }'
  print_info '    }'
  print_info '  }'
  print_info ""
}

# -----------------------------------------------------------------------------
# print_completion
# セットアップ完了メッセージと使い方を表示する
# -----------------------------------------------------------------------------
print_completion() {
  print_step "7/7" "セットアップ完了"

  printf "\n${COLOR_BOLD}==============================${COLOR_RESET}\n"
  printf "${COLOR_BOLD} セットアップ完了！${COLOR_RESET}\n"
  printf "${COLOR_BOLD}==============================${COLOR_RESET}\n"

  cat <<'USAGE'

【次のステップ】
  1. config.json を編集してください:
     ~/.claude/form-submit/config.json

     必須項目:
       - spreadsheet.url    : Google スプレッドシートのURL
       - commonData.会社名  : あなたの会社名
       - commonData.氏名    : あなたの氏名
       - commonData.メールアドレス : メールアドレス
       - commonData.電話番号 : 電話番号
       - commonData.お問い合わせ内容 : 送信メッセージ

  2. Google Chrome を完全に閉じてください
     （Playwright MCP と Chrome が同じプロファイルを共有するため）

【使い方】
  /form-submit                       未送信企業を一括処理（最大150社）
  /form-submit --company 企業名      特定企業のみ処理

【設定ファイル】
  ~/.claude/form-submit/config.json         送信データ設定
  ~/.claude/form-submit/field-log.json      未知フィールド学習データ
  ~/.claude/form-submit/screenshots/        送信前後のスクリーンショット

【詳細】
  references/config-schema.example.md       設定スキーマの詳細
  README.md                                 プロジェクト説明
USAGE
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
main() {
  local repo_root
  repo_root="$(get_repo_root)"

  printf "${COLOR_BOLD}FormPilot セットアップ${COLOR_RESET}\n"
  printf "リポジトリルート: %s\n" "${repo_root}"

  check_prerequisites
  create_skill_symlink "${repo_root}"
  create_directories
  create_config_json
  create_field_log
  check_playwright_mcp
  print_completion
}

main "$@"
