#!/bin/bash
# chezmoi のソースを環境ごとに描画して、置かれるものを確かめる。スクリプトは実行しない。
# Linux の上で Windows 向けも描画できるが、テンプレートの .chezmoi.os を差し替えるだけなので、
# Windows での実際の動作までは分からない。
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# HOME を差し替えると mise の shim が動かないので、先に実体を探す
chezmoi="$(cd "$HOME" && mise which chezmoi)" || exit 1
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
blocked() { if eval "$2" >/dev/null 2>&1; then fail "$1"; else pass "$1"; fi; }
# 使い方: equals <名前> <実際の値> <期待する値>
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: $2"; fi; }

# 使い方: cm <os>-<profile> <chezmoi の引数...>
cm() {
  local name="$1" os="${1%%-*}"
  shift
  HOME="$work/$name/fakehome" "$chezmoi" "$@" \
    --source "$root" \
    --config "$work/$name/chezmoi.toml" \
    --persistent-state "$work/$name/state.db" \
    --destination "$work/$name/home" \
    --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}"
}

prepare() {
  local name="$1" profile="${1#*-}"
  mkdir -p "$work/$name/home" "$work/$name/fakehome"
  if ! DOTFILES_PROFILE="$profile" cm "$name" init; then
    fail "$name: chezmoi init"
    return 1
  fi
  check "$name: 適用できる" 'cm "$name" apply --exclude scripts,externals'
  check "$name: 適用の後に差分がない" 'cm "$name" verify --exclude scripts,externals'
}

scripts_of() { cm "$1" managed --include scripts | sort | paste -sd ' ' -; }
files_of() { (cd "$work/$1/home" && find . -type f | sed 's|^\./||' | sort | paste -sd ' ' -); }

for name in linux-main linux-agent windows-main; do
  prepare "$name"
done

# --- agent に置いてよいものは、ここに挙げたものだけ。足すときは隔離への影響を考える ---
equals "linux-agent: 置かれるファイルが許可した一覧と一致" "$(files_of linux-agent)" \
  ".bash_profile .bashrc .config/git/ignore .config/mise/config.toml .config/mise/mise.lock .gitconfig .ideavimrc .tmux.conf"
blocked "linux-agent: 署名の設定がない" 'grep -qE "signingkey|gpgsign" "$work/linux-agent/home/.gitconfig"'
equals "linux-agent: 実行するスクリプト" "$(scripts_of linux-agent)" "10-mise-install.sh 40-claude-code.sh"

# --- 普段の環境 ---
for file in .ssh/config .gnupg/gpg-agent.conf .claude/settings.json .tmux.conf .vimrc; do
  check "linux-main: $file がある" '[ -f "$work/linux-main/home/$file" ]'
done
check "linux-main: コミット署名が有効" 'grep -q "gpgsign = true" "$work/linux-main/home/.gitconfig"'
check "linux-main: Claude の設定にフックがある" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"block-signing-bypass\")" "$work/linux-main/home/.claude/settings.json"'
equals "linux-main: 実行するスクリプト" "$(scripts_of linux-main)" "10-mise-install.sh 20-build-hooks.sh 30-vim-plugins.sh 40-claude-code.sh"

# --- Windows ---
for file in .wslconfig OneDrive/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 .claude/settings.json .vimrc; do
  check "windows-main: $file がある" '[ -f "$work/windows-main/home/$file" ]'
done
for file in .tmux.conf .ssh .gnupg .config/environment.d; do
  blocked "windows-main: $file がない" '[ -e "$work/windows-main/home/$file" ]'
done
check "windows-main: .vimrc が VS Code 用" 'cmp -s "$work/windows-main/home/.vimrc" "$root/home/.vimrc-files/vscode.vimrc"'
equals "windows-main: 実行するスクリプト" "$(scripts_of windows-main)" "10-mise-install.ps1 20-build-hooks.ps1"

# --- プロファイル ---
profile_of() { sed -n 's/^ *profile = "\(.*\)"$/\1/p' "$work/$1/chezmoi.toml"; }
unset DOTFILES_PROFILE
cm linux-agent init >/dev/null 2>&1
equals "環境変数なしで init し直しても agent のまま" "$(profile_of linux-agent)" agent
mkdir -p "$work/linux-default/home" "$work/linux-default/fakehome"
cm linux-default init >/dev/null 2>&1
equals "新しい環境の既定は main" "$(profile_of linux-default)" main

# --- テンプレートから作られるシェルスクリプト ---
for template in "$root"/home/*.sh.tmpl "$root"/home/dot_bashrc.tmpl "$root"/home/dot_bash_profile.tmpl; do
  rendered="$work/rendered-$(basename "$template")"
  for name in linux-main linux-agent; do
    if ! cm "$name" execute-template <"$template" >"$rendered" 2>"$rendered.err"; then
      fail "$name: $(basename "$template") を描画できない: $(cat "$rendered.err")"
      continue
    fi
    check "$name: $(basename "$template") の構文" 'bash -n "$rendered"'
  done
  case "$template" in
    *.sh.tmpl) check "shellcheck: $(basename "$template")" 'shellcheck -s bash "$rendered"' ;;
  esac
done

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
