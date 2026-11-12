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
    --cache "$work/cache" \
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

# Codex が書いた設定が、マージの後も残ることを確かめるための既存の内容
mkdir -p "$work/windows-main/home/.codex"
cat >"$work/windows-main/home/.codex/config.toml" <<'EOF'
model = "kept-model"

[windows]
sandbox = "unelevated"

[projects.'C:\work\repo']
trust_level = "trusted"
EOF

# gpg-agent.conf も、管理しない行は残る。Windows の Git の gpg は CRLF で書くこともある
mkdir -p "$work/windows-main/home/.gnupg"
printf 'default-cache-ttl 34560000\r\nmax-cache-ttl 34560000\r\npinentry-program C:\\pinentry.exe\r\n' >"$work/windows-main/home/.gnupg/gpg-agent.conf"

for name in linux-main linux-agent windows-main; do
  prepare "$name"
done

# 使い方: toml_json <os>-<profile> <ファイル>  (TOML を JSON にする。読めなければ失敗する)
toml_json() { cm "$1" execute-template --with-stdin '{{ .chezmoi.stdin | fromToml | toJson }}' <"$2"; }
# external はアーカイブを取ってきて中身まで並べるので、ここだけネットワークを使う
externals_of() { cm "$1" managed --include externals; }
expected_skills() {
  cm "$1" execute-template '{{ $d := dict "claude" ".claude/skills" "codex" ".agents/skills" }}{{ range $n, $s := .skills }}{{ range $s.targets }}{{ printf "%s/%s/SKILL.md\n" (get $d .) $n }}{{ end }}{{ end }}' | sort | paste -sd ' ' -
}
actual_skills() { externals_of "$1" | grep -E '^\.(claude|agents)/skills/[^/]+/SKILL\.md$' | sort | paste -sd ' ' -; }

# --- agent に置いてよいものは、ここに挙げたものだけ。足すときは隔離への影響を考える ---
equals "linux-agent: 置かれるファイルが許可した一覧と一致" "$(files_of linux-agent)" \
  ".bash_profile .bashrc .config/git/ignore .config/mise/config.toml .config/mise/mise.lock .gitconfig .ideavimrc .tmux.conf"
blocked "linux-agent: 署名の設定がない" 'grep -qE "signingkey|gpgsign" "$work/linux-agent/home/.gitconfig"'
equals "linux-agent: 実行するスクリプト" "$(scripts_of linux-agent)" "10-mise-install.sh 40-claude-code.sh"
equals "linux-agent: external がない (スキルを置かない)" "$(externals_of linux-agent | paste -sd ' ' -)" ""

# --- スキル (home/.chezmoidata/skills.toml) ---
# check に渡す文字列の中で使う
# shellcheck disable=SC2034
skills_json="$(cm linux-main execute-template '{{ .skills | toJson }}')"
check "スキル: commit が 40 桁のハッシュ" 'jq -e "all(.[]; .commit | test(\"^[0-9a-f]{40}$\"))" <<<"$skills_json"'
check "スキル: repo が owner/name" 'jq -e "all(.[]; .repo | test(\"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$\"))" <<<"$skills_json"'
check "スキル: path の前後に / がない" 'jq -e "all(.[]; .path | test(\"^/|/$\") | not)" <<<"$skills_json"'
for name in linux-main windows-main; do
  expected="$(expected_skills "$name")"
  check "$name: 置くスキルがある" '[ -n "$expected" ]'
  equals "$name: どのスキルにも SKILL.md が取れる" "$(actual_skills "$name")" "$expected"
done

# --- Codex (Windows だけ) ---
blocked "linux-main: .codex がない" '[ -e "$work/linux-main/home/.codex" ]'
# shellcheck disable=SC2034
codex_json="$(toml_json windows-main "$work/windows-main/home/.codex/config.toml")"
check "windows-main: Codex の設定が TOML として読める" '[ -n "$codex_json" ]'
check "windows-main: Codex の既存のキーが残る" 'jq -e ".model == \"kept-model\" and .projects[\"C:\\\\work\\\\repo\"].trust_level == \"trusted\"" <<<"$codex_json"'
check "windows-main: Codex の共通設定が優先される" 'jq -e ".windows.sandbox == \"elevated\"" <<<"$codex_json"'
check "Codex の設定がない環境でも共通設定から作れる" '[ "$(cm windows-main execute-template --with-stdin "$(cat "$root/home/dot_codex/modify_config.toml")" </dev/null | cm windows-main execute-template --with-stdin "{{ .chezmoi.stdin | fromToml | toJson }}")" = "$(toml_json windows-main "$root/home/.codex-config.toml")" ]'

# --- 普段の環境 ---
for file in .ssh/config .gnupg/gpg-agent.conf .claude/settings.json .claude/CLAUDE.md .tmux.conf .vimrc .local/bin/bws-run .local/bin/split-pdf; do
  check "linux-main: $file がある" '[ -f "$work/linux-main/home/$file" ]'
done
check "linux-main: bws-run が実行できる" '[ -x "$work/linux-main/home/.local/bin/bws-run" ]'
check "linux-main: split-pdf が実行できる" '[ -x "$work/linux-main/home/.local/bin/split-pdf" ]'
for file in .local/bin/bws-run.ps1 .local/bin/bws-run.cmd .local/bin/split-pdf.cmd; do
  blocked "linux-main: $file がない" '[ -e "$work/linux-main/home/$file" ]'
done
equals "linux-main: gpg-agent.conf" "$(cat "$work/linux-main/home/.gnupg/gpg-agent.conf")" 'default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200
enable-ssh-support
disable-scdaemon'
check "linux-main: コミット署名が有効" 'grep -q "gpgsign = true" "$work/linux-main/home/.gitconfig"'
check "linux-main: Claude の設定にフックがある" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"block-signing-bypass\")" "$work/linux-main/home/.claude/settings.json"'
equals "linux-main: 実行するスクリプト" "$(scripts_of linux-main)" "10-mise-install.sh 20-build-hooks.sh 30-vim-plugins.sh 40-claude-code.sh 50-gh-extensions.sh"

# --- knowledge-capture (docs/skills.md) ---
# 許可を広げるときは、何を許すことになるかを確かめてから、期待する値を直す
knowledge_tools='Bash(git remote -v) Read(~/work/blog/marulabs-knowledge/**) Edit(~/work/blog/marulabs-knowledge/knowledge/**) Bash(git -C ~/work/blog/marulabs-knowledge add *) Bash(git -C ~/work/blog/marulabs-knowledge commit *) Bash(gh repo clone Maru32768/marulabs-knowledge ~/work/blog/marulabs-knowledge)'
for name in linux-main windows-main; do
  skill="$work/$name/home/.claude/skills/knowledge-capture/SKILL.md"
  check "$name: knowledge-capture がある" '[ -f "$skill" ]'
  # description を除く frontmatter の完全一致。hooks などのキーを足して許可を広げる変更も落ちる
  equals "$name: knowledge-capture の frontmatter" "$(sed -n '1{/^---$/!q;d};/^---$/q;/^description: /d;p' "$skill" 2>/dev/null)" "name: knowledge-capture
argument-hint: \"[記録する内容のメモ]\"
allowed-tools: $knowledge_tools"
  check "$name: knowledge-capture がコミットの前に gitleaks で調べる" 'grep -qF "先に\`mise -C ~/work/blog/marulabs-knowledge exec -- gitleaks dir --no-banner --redact -v --config .gitleaks.toml --exit-code 3 <記録のパス>\`を" "$skill"'
  check "$name: knowledge-capture で gitleaks の手順がコミットより前にある" '[ "$(grep -oE "exec -- gitleaks dir|commit -m" "$skill" | head -1)" = "exec -- gitleaks dir" ]'
  check "$name: knowledge-capture は gitleaks を実行できないときコミットしない" 'grep -qF "gitleaksを実行できなかったとき(許可されなかったときも)は、コミットせずに" "$skill"'
  check "$name: CLAUDE.md に記録の提案の形がある" 'grep -qF "記録候補: <タイトル案>(/knowledge-capture)" "$work/$name/home/.claude/CLAUDE.md"'
done

# --- Windows ---
for file in .wslconfig OneDrive/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 .claude/settings.json .claude/CLAUDE.md .vimrc .local/bin/bws-run.ps1 .local/bin/bws-run.cmd .local/bin/split-pdf .local/bin/split-pdf.cmd; do
  check "windows-main: $file がある" '[ -f "$work/windows-main/home/$file" ]'
done
for file in .tmux.conf .ssh .config/environment.d .local/bin/bws-run; do
  blocked "windows-main: $file がない" '[ -e "$work/windows-main/home/$file" ]'
done
equals "windows-main: gpg-agent.conf は既存の行を残し、キャッシュを WSL と同じにする" "$(cat "$work/windows-main/home/.gnupg/gpg-agent.conf")" 'pinentry-program C:\pinentry.exe
default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200'
check "windows-main: .vimrc が VS Code 用" 'cmp -s "$work/windows-main/home/.vimrc" "$root/home/.vimrc-files/vscode.vimrc"'
equals "windows-main: 実行するスクリプト" "$(scripts_of windows-main)" "10-mise-install.ps1 20-build-hooks.ps1 50-gh-extensions.ps1"

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
