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

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
todo() { printf 'TODO %s\n' "$1"; }
skip() { printf 'SKIP %s\n' "$1"; }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }

check "Ubuntu 26.04" 'grep -q "VERSION_ID=\"26.04\"" /etc/os-release'
check "既定ユーザーが wsl.conf にある" 'grep -q "^default=$(id -un)$" /etc/wsl.conf'
if "$container"; then
  skip "systemd が動いている"
else
  check "systemd が動いている" '[ "$(cat /proc/1/comm)" = systemd ]'
fi

while read -r pkg; do
  check "apt: $pkg" "dpkg -s $pkg"
done < <(grep -vE '^(#|$)' "$HOME/dotfiles/packages/apt.txt")

check "mise" 'mise --version'
lock_versions() {
  awk '/^\[\[tools\./ { name = $0; gsub(/^\[\[tools\.|\]\]$|"/, "", name) }
       /^version = / { version = $3; gsub(/"/, "", version); print name, version }' \
    "$HOME/.config/mise/mise.lock" | sort
}
check "ツールのバージョンが mise.lock と一致" 'diff <(lock_versions) <(mise ls --current | awk "{print \$1, \$2}" | sort)'
for tool in chezmoi go node rustc deno bun uv python java terraform aws bws gh ghq rg fd shellcheck yt-dlp goimports; do
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
check ".ssh の権限が 700" '[ "$(stat -c %a ~/.ssh)" = 700 ]'
check ".gnupg の権限が 700" '[ "$(stat -c %a ~/.gnupg)" = 700 ]'
check "コミット署名が有効" '[ "$(git config --global commit.gpgsign)" = true ]'
check "pinentry が GUI" 'readlink -f /usr/bin/pinentry | grep -q gtk'
check "gpg-agent の設定" 'grep -q "^enable-ssh-support$" ~/.gnupg/gpg-agent.conf'
if "$container"; then
  skip "systemd の環境に DISPLAY がある"
else
  check "systemd の環境に DISPLAY がある (反映には再起動が必要)" 'systemctl --user show-environment | grep -q "^DISPLAY="'
fi

hook="$HOME/.claude/hooks/block-signing-bypass"
deny_input='{"tool_name":"Bash","tool_input":{"command":"git commit --no-gpg-sign"}}'
allow_input='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
check "署名回避のフックが拒否する" "printf '%s' '$deny_input' | '$hook' | grep -q deny"
check "署名回避のフックが通常のコマンドを通す" "[ -z \"\$(printf '%s' '$allow_input' | '$hook')\" ]"
check "Claude の設定にフックがある" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"block-signing-bypass\")" ~/.claude/settings.json'
check "Claude Code" 'claude --version'
check "サンドボックスの依存" 'command -v bwrap && command -v socat'

# 一覧にあるものがすべて入っていること。ビルドの失敗までは分からない
plug_dir="$HOME/.vim/plugged"
declared_plugins() { sed -nE "s|^Plug '[^/']+/([^']+)'.*|\\1|p" "$HOME/.vimrc" | sort -u; }
installed_plugins() { find "$plug_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -u; }
declared_count="$(declared_plugins | wc -l)"
missing_plugins="$(comm -23 <(declared_plugins) <(installed_plugins) | paste -sd ' ' -)"
if [ "$declared_count" -eq 0 ]; then
  fail "vim プラグイン (~/.vimrc に一覧がない)"
elif [ -n "$missing_plugins" ]; then
  fail "vim プラグイン (足りない: $missing_plugins)"
else
  pass "vim プラグイン ($declared_count 個)"
fi
# エラーの内容は vim -N -es -u ~/.vimrc -i NONE +qall で見られる
check ".vimrc をエラーなしで読める" 'vim -N -es -u ~/.vimrc -i NONE +qall </dev/null'

if gpg --list-secret-keys "$GPG_FPR" >/dev/null 2>&1; then
  pass "GPG 署名鍵"
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
  check "SSH キーが gpg-agent に登録されている" 'SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)" ssh-add -l'
else
  todo "SSH キー: provision/setup-credentials.sh を実行"
fi

if [ -s ~/.config/bws/token.gpg ]; then
  pass "Bitwarden Secrets Manager のトークン"
else
  todo "Bitwarden Secrets Manager のトークン: bws-run --set-token を実行 (docs/secrets.md)"
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
