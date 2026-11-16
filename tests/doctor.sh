#!/bin/bash
# 環境が想定どおりか確認する。問題があれば終了コード 1 を返す。
# TODO は、ユーザーの手作業がまだ残っているだけで、失敗とは数えない。
#
# 使い方: doctor.sh [--container]
#   --container  CI のコンテナ用。コンテナには systemd がないので、その検査を飛ばす
# shellcheck disable=SC2016
set -uo pipefail

container=false
case "${1:-}" in
  "") ;;
  --container) container=true ;;
  *) echo "不明な引数: $1" >&2; exit 2 ;;
esac

export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# mise は親ディレクトリの設定も読むので、プロジェクトの設定に影響されないようにする
cd "$HOME" || exit 1
GPG_FPR="7AF93B4735CF2AAC930EF5CD78324D99D34D3111"
failures=0
# wsl、desktop (WSL ではない PC)、mac。desktop と mac は PC ごとの署名鍵を使う (docs/desktop.md、docs/mac.md)
host="$(chezmoi data --format json 2>/dev/null | jq -r '.host // "wsl"')"
# --global だけでは ~/.gitconfig.local を読まないので、そこで変えた値も見る
signing_key="$(git config --global --includes user.signingkey || true)"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
todo() { printf 'TODO %s\n' "$1"; }
skip() { printf 'SKIP %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
# GNU と BSD (mac) の stat は、権限の取り出し方が違う
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

if [ "$host" = mac ]; then
  check "macOS (Apple Silicon)" '[ "$(uname -s)-$(uname -m)" = Darwin-arm64 ]'
  check "Homebrew の一覧 (packages/Brewfile) がすべて入っている" 'brew bundle check --no-upgrade --file "$HOME/dotfiles/packages/Brewfile"'
else
  check "Ubuntu 26.04" 'grep -q "VERSION_ID=\"26.04\"" /etc/os-release'
  if [ "$host" = desktop ]; then
    check "wsl.conf がない" '[ ! -e /etc/wsl.conf ]'
    check "WSLg の設定がない" '[ ! -e ~/.config/environment.d/wslg.conf ]'
  else
    check "既定ユーザーが wsl.conf にある" 'grep -q "^default=$(id -un)$" /etc/wsl.conf'
  fi
  if "$container"; then
    skip "systemd が動いている"
  else
    check "systemd が動いている" '[ "$(cat /proc/1/comm)" = systemd ]'
  fi
  while read -r pkg; do
    check "apt: $pkg" "dpkg -s $pkg"
  done < <(grep -vE '^(#|$)' "$HOME/dotfiles/packages/apt.txt")
fi

check "mise" 'mise --version'
platform=linux-x64; [ "$host" = mac ] && platform=macos-arm64
# config.toml の os でほかの OS に絞ったツール (Windows の llama.cpp、mac の op と codex) は、
# lock にこの platform の行が無く、mise ls --current にも出ない。platform の行が 1 つも無いもの (rust など) は入る
lock_versions() {
  awk -v platform="$platform" '
    function flush() { if (name != "" && (!any_platform || this_platform)) print name, version }
    /^\[\[tools\./ { flush(); name = $0; gsub(/^\[\[tools\.|\]\]$|"/, "", name); version = ""; any_platform = 0; this_platform = 0 }
    /^version = / && version == "" { version = $3; gsub(/"/, "", version) }
    /"platforms\./ { any_platform = 1; if (index($0, "\"platforms." platform "\"")) this_platform = 1 }
    END { flush() }' "$HOME/.config/mise/mise.lock" | sort
}
check "ツールのバージョンが mise.lock と一致" 'diff <(lock_versions) <(mise ls --current | awk "{print \$1, \$2}" | sort)'
tools="chezmoi go node rustc deno bun uv python java terraform aws gh ghq rg fd shellcheck yt-dlp goimports"
[ "$host" = mac ] || tools="$tools op codex"
for tool in $tools; do
  check "ツール: $tool" "command -v $tool"
done

# settings.json は Claude Code 自身も書き換えるので比べない。フックの登録は下で確かめる
# status が失敗すると何も出力しないので、終了コードも見る
check "chezmoi の管理ファイルに差分がない" 'status="$(chezmoi status --exclude=scripts)" && [ -z "$(printf "%s\n" "$status" | grep -v "\.claude/settings\.json$")" ]'
# Windows では開発者モードでないとリンクを作れず、chezmoi apply が失敗する。skills.toml の exclude で外す
check "スキルにシンボリックリンクがない" '[ -z "$(find ~/.claude/skills ~/.agents/skills -path "*/skills/synced" -prune -o -type l -print 2>/dev/null)" ]'
check "gh の拡張: gh-stack" 'gh stack --version'
check ".gitconfig が実ファイル" '[ -f ~/.gitconfig ] && [ ! -L ~/.gitconfig ]'
check ".ssh が実ディレクトリ" '[ -d ~/.ssh ] && [ ! -L ~/.ssh ]'
check ".ssh の権限が 700" '[ "$(mode_of ~/.ssh)" = 700 ]'
check ".gnupg の権限が 700" '[ "$(mode_of ~/.gnupg)" = 700 ]'
check "コミット署名が有効" '[ "$(git config --global --includes commit.gpgsign)" = true ]'
if [ "$host" = mac ]; then
  # JetBrains IDE が書いたものも含め、gpg-agent.conf が指す pinentry が実行できる
  check "pinentry が実行できる" 'pinentry="$(sed -n "s/^pinentry-program //p" ~/.gnupg/gpg-agent.conf | tail -1)" && [ -x "$pinentry" ]'
  check "zsh のログインシェルで mise が使える" 'zsh -lic "command -v mise" </dev/null'
else
  # デスクトップでは、Ubuntu が入れる pinentry-gnome3 が選ばれることもある
  check "pinentry が GUI" 'readlink -f /usr/bin/pinentry | grep -qE "gtk|gnome3"'
  check "gpg-agent の設定" 'grep -q "^enable-ssh-support$" ~/.gnupg/gpg-agent.conf'
  if "$container"; then
    skip "systemd の環境に DISPLAY がある"
  else
    check "systemd の環境に DISPLAY がある (反映には再起動が必要)" 'systemctl --user show-environment | grep -q "^DISPLAY="'
  fi
fi

hook="$HOME/.claude/hooks/block-signing-bypass"
deny_input='{"tool_name":"Bash","tool_input":{"command":"git commit --no-gpg-sign"}}'
allow_input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
check "署名回避のフックが拒否する" "printf '%s' '$deny_input' | '$hook' | grep -q deny"
check "署名回避のフックが通常のコマンドを通す" "[ -z \"\$(printf '%s' '$allow_input' | '$hook')\" ]"
check "Claude の設定にフックがある" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"block-signing-bypass\")" ~/.claude/settings.json'
check "Claude Code" 'claude --version'
[ "$host" = mac ] || check "サンドボックスの依存" 'command -v bwrap && command -v socat'

# 一覧にあるものがすべて入っていること。ビルドの失敗までは分からない
plug_dir="$HOME/.vim/plugged"
# en_US.UTF-8 などでは sort と comm の順序が食い違うので、C の順序で比べる
declared_plugins() { sed -nE "s|^Plug '[^/']+/([^']+)'.*|\\1|p" "$HOME/.vimrc" | LC_ALL=C sort -u; }
installed_plugins() { for dir in "$plug_dir"/*/; do [ -d "$dir" ] && basename "$dir"; done | LC_ALL=C sort -u; }
declared_count="$(declared_plugins | wc -l)"
missing_plugins="$(LC_ALL=C comm -23 <(declared_plugins) <(installed_plugins) | paste -sd ' ' -)"
if [ "$declared_count" -eq 0 ]; then
  fail "vim プラグイン (~/.vimrc に一覧がない)"
elif [ -n "$missing_plugins" ]; then
  fail "vim プラグイン (足りない: $missing_plugins)"
else
  pass "vim プラグイン ($declared_count 個)"
fi
# エラーの内容は vim -N -es -u ~/.vimrc -i NONE +qall で見られる
check ".vimrc をエラーなしで読める" 'vim -N -es -u ~/.vimrc -i NONE +qall </dev/null'

if [ "$host" = desktop ] || [ "$host" = mac ]; then
  if [ -n "$signing_key" ] && gpg --list-secret-keys "$signing_key" >/dev/null 2>&1; then
    pass "GPG 署名鍵 (この PC 専用: $signing_key)"
    # 公開の API で、登録した鍵の ID を確かめる。主鍵の ID で署名するので、主鍵の key_id と比べる
    registered_gpg="$(curl -fsS --max-time 15 https://api.github.com/users/Maru32768/gpg_keys || true)"
    if jq -e --arg key "$signing_key" 'any(.[]; .key_id == $key)' <<<"$registered_gpg" >/dev/null 2>&1; then
      pass "GPG 署名鍵が GitHub に登録されている"
    else
      todo "GPG 署名鍵の登録: gpg --armor --export $signing_key を https://github.com/settings/gpg/new に登録"
    fi
  else
    todo "GPG 署名鍵: provision/setup-credentials.sh で作る"
  fi
elif gpg --list-secret-keys "$GPG_FPR" >/dev/null 2>&1; then
  check "GPG 署名鍵" '[ "$signing_key" = "${GPG_FPR: -16}" ]'
else
  todo "GPG 署名鍵: provision/setup-credentials.sh を実行"
fi

if [ -f ~/.ssh/github ]; then
  # 接続するとパスフレーズのポップアップが出ることがあるので、公開鍵の登録だけを確認する
  public_key="$(awk '{print $2}' ~/.ssh/github.pub)"
  registered_keys="$(curl -fsS --max-time 15 https://github.com/Maru32768.keys || true)"
  if [[ "$registered_keys" == *"$public_key"* ]]; then
    pass "SSH キーが GitHub に登録されている"
  else
    todo "SSH キーの登録: ~/.ssh/github.pub を GitHub に登録"
  fi
  if [ "$host" = mac ]; then
    check "SSH キーが ssh-agent に登録されている" 'ssh-add -l | grep -qF "$(ssh-keygen -lf ~/.ssh/github.pub | awk "{print \$2}")"'
  else
    check "SSH キーが gpg-agent に登録されている" 'SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)" ssh-add -l'
  fi
else
  todo "SSH キー: provision/setup-credentials.sh を実行"
fi

# mac では 1Password を使わない (docs/mac.md)
if [ "$host" = mac ]; then
  :
elif [ -s ~/.config/op-run/token.gpg ]; then
  pass "1Password のサービスアカウントのトークン"
else
  todo "1Password のサービスアカウントのトークン: op-run --set-token を実行 (docs/secrets.md)"
fi

if claude auth status >/dev/null 2>&1; then
  pass "Claude Code のログイン"
else
  todo "Claude Code のログイン: claude を起動"
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
printf '\n問題はありません\n'
