#!/bin/bash
# Claude Code の共通設定を WSL と Windows の両方に反映する。
#   ./scripts/008_claude.sh          反映する
#   ./scripts/008_claude.sh --check  差分を表示するだけで何も変更しない
#
# settings.json は Claude Code 自身も書き換えるため symlink にせず、claude/settings.json の内容を
# 既存の設定へマージする。環境固有のキーは残り、同じキーは claude/settings.json が優先される
# (配列は丸ごと置き換わる)。詳細は docs/claude.md。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SHARED_SETTINGS="$DOTFILES_DIR/claude/settings.json"
HOOK_NAME="block-signing-bypass"
HOOK_SRC="$DOTFILES_DIR/claude/hooks/$HOOK_NAME"

check_only=false
[ "${1:-}" = "--check" ] && check_only=true

if ! has_cmd jq; then
  warn "jq が見つからないためスキップします"
  exit 1
fi

# 001_lang_runtimes.sh で入れた直後は PATH に載っていないことがある
has_cmd go || PATH="$PATH:/usr/local/go/bin"
if ! $check_only && ! has_cmd go; then
  warn "go が見つからないためスキップします。フックをビルドできません"
  exit 1
fi

# 実行中のセッションが書きかけのファイルを起動しないよう、別名でビルドしてから置き換える
build_hook() {
  local goos="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  (cd "$HOOK_SRC" && GOOS="$goos" go build -o "$dst.tmp" .) && mv -f "$dst.tmp" "$dst"
}

if ! $check_only; then
  if ! (cd "$HOOK_SRC" && go test ./... >/dev/null); then
    warn "フックのテストに失敗したため反映しません"
    exit 1
  fi
  build_hook linux "$HOME/.claude/hooks/$HOOK_NAME" || exit 1
fi

merge_settings() {
  local target="$1" base="$1" merged
  [ -e "$target" ] || base=/dev/null

  if [ -e "$target" ] && ! jq empty "$target" 2>/dev/null; then
    warn "$target は不正な JSON のため変更しません"
    return 1
  fi

  if [ "$base" = /dev/null ]; then
    merged="$(jq . "$SHARED_SETTINGS")"
  else
    merged="$(jq -s '.[0] * .[1]' "$target" "$SHARED_SETTINGS")"
  fi

  if [ -e "$target" ] && [ "$merged" = "$(jq . "$target")" ]; then
    log "$target は最新です"
    return 0
  fi

  if $check_only; then
    log "$target の差分:"
    diff -u <(jq . "$base") <(echo "$merged") || true
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  [ -e "$target" ] && cp "$target" "$target.bak.$(date +%s)"
  echo "$merged" >"$target"
  log "$target を更新しました"
}

merge_settings "$HOME/.claude/settings.json"

if is_wsl; then
  if [ -z "${WINHOME:-}" ] && has_cmd wslvar; then
    WINHOME="$(wslpath "$(wslvar USERPROFILE)")"
  fi
  if [ -n "${WINHOME:-}" ]; then
    if ! $check_only; then
      build_hook windows "$WINHOME/.claude/hooks/$HOOK_NAME.exe" || exit 1
    fi
    merge_settings "$WINHOME/.claude/settings.json"
  else
    warn "Windows のホームを特定できないため Windows 側をスキップします"
  fi
fi
