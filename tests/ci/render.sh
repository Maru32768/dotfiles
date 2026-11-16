#!/bin/bash
# chezmoi のソースを環境ごとに描画して、置かれるものを確かめる。スクリプトは実行しない。
# Windows と mac 向けも、テンプレートの .chezmoi.os を差し替えて描画する。差し替えるだけなので、
# Windows と mac での実際の動作までは分からない。
# shellcheck disable=SC2016
set -uo pipefail
# 呼び出し元が export していると、「環境変数なしで init し直す」検査が何も試さずに通る
unset DOTFILES_PROFILE DOTFILES_HOST DOTFILES_WORK DOTFILES_SIGNING_KEY

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

# 使い方: cm <os>-<profile> <chezmoi の引数...>。KERNEL があれば、カーネルの osrelease も差し替える
cm() {
  local name="$1" os="${1%%-*}" kernel=""
  shift
  [ -n "${KERNEL:-}" ] && kernel=",\"kernel\":{\"osrelease\":\"$KERNEL\"}"
  HOME="$work/$name/fakehome" "$chezmoi" "$@" \
    --source "$root" \
    --config "$work/$name/chezmoi.toml" \
    --persistent-state "$work/$name/state.db" \
    --destination "$work/$name/home" \
    --cache "$work/cache" \
    --no-tty \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"$kernel}}"
}

# chezmoi init は設定のテンプレートに --override-data を効かせず、動いている機械の OS とカーネルを読む。
# execute-template --init なら効くので、その結果を設定にする
init_of() {
  cm "$1" execute-template --init <"$root/home/.chezmoi.toml.tmpl" >"$work/$1/chezmoi.toml.new" || { rm -f "$work/$1/chezmoi.toml.new"; return 1; }
  mv "$work/$1/chezmoi.toml.new" "$work/$1/chezmoi.toml"
}

# linux-main と linux-agent は WSL、linux-desktop は WSL ではない PC。CI はどちらのカーネルでも動くので、host を指定する
prepare() {
  local name="$1" profile="${1#*-}" host=wsl work_pc=""
  case "$name" in
    windows-* | darwin-main) host="" ;;
    darwin-work) profile=main host="" work_pc=1 ;;
    linux-desktop) profile=main host=desktop ;;
  esac
  mkdir -p "$work/$name/home" "$work/$name/fakehome"
  if ! DOTFILES_PROFILE="$profile" DOTFILES_HOST="$host" DOTFILES_WORK="$work_pc" init_of "$name"; then
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

# Claude Code が書いた許可も、マージの後に残ることを確かめる
mkdir -p "$work/windows-main/home/.claude"
printf '{"model":"kept-model","permissions":{"allow":["Bash(ls)"],"additionalDirectories":["D:/x"]}}' >"$work/windows-main/home/.claude/settings.json"

# review-loop の台帳は、反映の後も残る
mkdir -p "$work/linux-main/home/.local/state/review-loop/repo/branch"
printf 'kept\n' >"$work/linux-main/home/.local/state/review-loop/repo/branch/ledger.md"

# gpg-agent.conf も、管理しない行は残る。Windows の Git の gpg は CRLF で書くこともある
mkdir -p "$work/windows-main/home/.gnupg"
printf 'default-cache-ttl 34560000\r\nmax-cache-ttl 34560000\r\npinentry-program C:\\pinentry.exe\r\n' >"$work/windows-main/home/.gnupg/gpg-agent.conf"
mkdir -p "$work/darwin-work/home/.gnupg"
printf 'default-cache-ttl 600\npinentry-program /Applications/IDE.app/pinentry.sh\n' >"$work/darwin-work/home/.gnupg/gpg-agent.conf"

for name in linux-main linux-agent linux-desktop windows-main darwin-main darwin-work; do
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
blocked "linux-agent: review-loop の台帳の置き場を作らない" '[ -e "$work/linux-agent/home/.local/state" ]'
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
for file in .ssh/config .gnupg/gpg-agent.conf .claude/settings.json .claude/CLAUDE.md .tmux.conf .vimrc .local/bin/op-run .local/bin/split-pdf .local/bin/usage-log; do
  check "linux-main: $file がある" '[ -f "$work/linux-main/home/$file" ]'
done
for tool in op-run split-pdf usage-log; do
  check "linux-main: $tool が実行できる" '[ -x "$work/linux-main/home/.local/bin/$tool" ]'
done
for file in .local/bin/op-run.ps1 .local/bin/op-run.cmd .local/bin/split-pdf.cmd .local/bin/usage-log.cmd .zshrc .zprofile; do
  blocked "linux-main: $file がない" '[ -e "$work/linux-main/home/$file" ]'
done
blocked "linux-main: plamo-server.cmd がない" '[ -e "$work/linux-main/home/.local/bin/plamo-server.cmd" ]'
equals "linux-main: gpg-agent.conf" "$(cat "$work/linux-main/home/.gnupg/gpg-agent.conf")" 'default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200
enable-ssh-support
disable-scdaemon'
check "linux-main: コミット署名が有効" 'grep -q "gpgsign = true" "$work/linux-main/home/.gitconfig"'
check "linux-main: Claude の設定にフックがある" 'jq -e ".hooks.PreToolUse[0].hooks[0].command | test(\"block-signing-bypass\")" "$work/linux-main/home/.claude/settings.json"'
# 初回は数分かかるので、セッションを待たせないようにバックグラウンドで動かす
check "linux-main: 開始時に usage-log の collect をバックグラウンドで動かす" 'jq -e ".hooks.SessionStart[0].hooks[0] | .async == true and (.command | test(\"usage-log\\\" collect\"))" "$work/linux-main/home/.claude/settings.json"'
equals "linux-main: 実行するスクリプト" "$(scripts_of linux-main)" "10-mise-install.sh 20-build-hooks.sh 30-vim-plugins.sh 40-claude-code.sh 50-gh-extensions.sh"

# --- knowledge-capture (docs/skills.md) ---
# 許可を広げるときは、何を許すことになるかを確かめてから、期待する値を直す
knowledge_tools='Bash(git remote -v) Read(~/work/blog/marulabs-knowledge/**) Edit(~/work/blog/marulabs-knowledge/knowledge/**) Bash(git -C ~/work/blog/marulabs-knowledge add *) Bash(git -C ~/work/blog/marulabs-knowledge commit *) Bash(gh repo clone Maru32768/marulabs-knowledge ~/work/blog/marulabs-knowledge)'
for name in linux-main windows-main; do
  skill="$work/$name/home/.claude/skills/knowledge-capture/SKILL.md"
  check "$name: knowledge-capture がある" '[ -f "$skill" ]'
  # description を除く frontmatter の完全一致。hooks などのキーを足して許可を広げる変更も落ちる
  equals "$name: knowledge-capture の frontmatter" "$(sed -n '1{/^---$/!q;d;};/^---$/q;/^description: /d;p' "$skill" 2>/dev/null)" "name: knowledge-capture
argument-hint: \"[記録する内容のメモ]\"
allowed-tools: $knowledge_tools"
  check "$name: knowledge-capture がコミットの前に gitleaks で調べる" 'grep -qF "先に\`mise -C ~/work/blog/marulabs-knowledge exec -- gitleaks dir --no-banner --redact -v --config .gitleaks.toml --exit-code 3 <記録のパス>\`を" "$skill"'
  check "$name: knowledge-capture で gitleaks の手順がコミットより前にある" '[ "$(grep -oE "exec -- gitleaks dir|commit -m" "$skill" | head -1)" = "exec -- gitleaks dir" ]'
  check "$name: knowledge-capture は gitleaks を実行できないときコミットしない" 'grep -qF "gitleaksを実行できなかったとき(許可されなかったときも)は、コミットせずに" "$skill"'
  check "$name: CLAUDE.md に記録の提案の形がある" 'grep -qF "記録候補: <タイトル案>(/knowledge-capture)" "$work/$name/home/.claude/CLAUDE.md"'
done

# --- review-loop の台帳 (docs/claude.md) ---
# 許可を広げるときは、何を許すことになるかを確かめてから、期待する値を直す
for name in linux-main windows-main; do
  # shellcheck disable=SC2034
  ledger="$(cm "$name" execute-template '{{ .chezmoi.homeDir }}')/.local/state/review-loop"
  check "$name: Claude の設定に台帳の置き場がある" 'jq -e --arg d "$ledger" ".permissions.additionalDirectories == [\$d]" "$work/$name/home/.claude/settings.json"'
  # Claude Code はセッションの開始時に無いディレクトリを外すので、反映のときに作る
  # linux-main には既存の台帳を置くので、ディレクトリがあるかではなく、反映が作るかを見る
  check "$name: 台帳の置き場のディレクトリができる" 'cm "$name" managed --include dirs --exclude externals | grep -qx ".local/state/review-loop"'
  check "$name: review-loop が台帳を許可したディレクトリに置く" 'grep -qF "~/.local/state/review-loop/<リポジトリ>/<名前>/" "$work/$name/home/.claude/skills/review-loop/SKILL.md"'
  check "$name: review-loop が書く終了の行を ship-task が読む" 'grep -qF "\`- 終了: <" "$work/$name/home/.claude/skills/review-loop/SKILL.md" && grep -qF "\`- 終了:\`の行" "$work/$name/home/.claude/skills/ship-task/SKILL.md"'
done
check "linux-main: 既存の review-loop の台帳が反映の後も残る" '[ "$(cat "$work/linux-main/home/.local/state/review-loop/repo/branch/ledger.md")" = kept ]'
check "linux-main: 共通の設定は permissions に台帳の置き場のほかを足さない" 'jq -e ".permissions | keys == [\"additionalDirectories\"]" "$work/linux-main/home/.claude/settings.json"'
check "windows-main: 共通の設定は permissions に台帳の置き場のほかを足さない" 'jq -e ".permissions | keys == [\"additionalDirectories\", \"allow\"]" "$work/windows-main/home/.claude/settings.json"'
check "windows-main: Claude の設定の既存のキーと permissions.allow が残る" 'jq -e ".model == \"kept-model\" and .permissions.allow == [\"Bash(ls)\"]" "$work/windows-main/home/.claude/settings.json"'

# --- usage-cap (docs/claude.md) ---
# 許可を広げるときは、何を許すことになるかを確かめてから、期待する値を直す
for name in linux-main windows-main; do
  skill="$work/$name/home/.claude/skills/usage-cap/SKILL.md"
  # description を除く frontmatter の完全一致。hooks などのキーを足して許可を広げる変更も落ちる
  equals "$name: usage-cap の frontmatter" "$(sed -n '1{/^---$/!q;d;};/^---$/q;/^description: /d;p' "$skill" 2>/dev/null)" "name: usage-cap
user-invocable: false
allowed-tools: Read(~/.local/state/usage/weekly-cap) mcp__ccd_session_mgmt__get_usage"
  # 本体が読むのは description だけなので、止まる側に倒す約束と、本体で呼ばない約束を確かめる
  check "$name: usage-cap の description が、CONTINUE のほかは止まらせる" 'sed -n "/^description: /p" "$skill" | grep -qF "返った1行目が\`CONTINUE\`なら続け、それ以外なら新しい単位を始めずに止まり"'
  check "$name: usage-cap の description が、本体には呼ばせない" 'sed -n "/^description: /p" "$skill" | grep -qF "このスキルを呼ぶのは、確かめるサブエージェントだけ。大きい仕事の本体は呼ばず"'
  check "$name: usage-cap の本文が、許可したファイルを読む" 'grep -qF "\`~/.local/state/usage/weekly-cap\`を、このままのパスでReadで読む" "$skill"'
  check "$name: usage-log cap が、usage-cap の読むファイルに書く" 'grep -qF "\".local/state/usage/usage.sqlite3\"" "$work/$name/home/.local/bin/usage-log" && grep -qF "\"weekly-cap\"" "$work/$name/home/.local/bin/usage-log"'
done

# --- ローカルのファイルの読み込み (git と SSH) ---
ghome="$work/git-home"
mkdir -p "$ghome"
printf '[user]\n\temail = local@example.com\n[commit]\n\tgpgsign = false\n[gpg]\n\tprogram = /bin/false\n' >"$ghome/.gitconfig.local"
gitconfig_of() { HOME="$ghome" git config -f "$work/linux-main/home/.gitconfig" --includes "$1"; }
equals "linux-main: ~/.gitconfig.local の値が勝つが、署名の設定は変えられない" "$(gitconfig_of user.email) $(gitconfig_of commit.gpgsign) $(gitconfig_of gpg.program)" "local@example.com true gpg"
blocked "linux-agent: .gitconfig が ~/.gitconfig.local を読まない" 'git config -f "$work/linux-agent/home/.gitconfig" --get include.path'
# mac の設定も Linux の ssh で読めること (IgnoreUnknown) を確かめるので、どちらの設定も動いている ssh で読む。
# config.local は ~/.ssh からの相対パスで、本物のホームを指すので、ここだけ絶対パスに替えて試す
for ssh_env in linux-main darwin-main; do
  sdir="$work/ssh-$ssh_env"
  mkdir -p "$sdir"
  sed "s|^Include config.local$|Include $sdir/config.local|" "$work/$ssh_env/home/.ssh/config" >"$sdir/config"
  printf 'Host *\n    IdentityFile ~/.ssh/other\nHost box\n    HostName box.example.org\n' >"$sdir/config.local"
  equals "$ssh_env: GitHub では、config.local の Host * の鍵より GitHub の鍵を先に試す" "$(ssh -G -F "$sdir/config" github.com </dev/null 2>/dev/null | sed -n 's|^identityfile ~/\.ssh/||p' | paste -sd ' ' -)" "github other"
  equals "$ssh_env: config.local のホストの設定が効く" "$(ssh -G -F "$sdir/config" box </dev/null 2>/dev/null | sed -n 's/^hostname //p')" box.example.org
done

# --- Claude への指示 (CLAUDE.md と ~/.claude/rules、docs/claude.md) ---
topics_of() { cat "$work/$1/home/.claude/CLAUDE.md" "$work/$1/home/.claude/rules/"*.md 2>/dev/null | grep -oF -e PLaMo -e op-run -e '--assignee @me' | LC_ALL=C sort -u | paste -sd, -; }
equals "windows-main: Claude への指示に出る話題" "$(topics_of windows-main)" "PLaMo,op-run"
equals "linux-main: Claude への指示に出る話題" "$(topics_of linux-main)" "op-run"
equals "darwin-main: Claude への指示に出る話題" "$(topics_of darwin-main)" ""
equals "darwin-work: Claude への指示に出る話題" "$(topics_of darwin-work)" "--assignee @me"
# 話題の検査は CLAUDE.md と rules を区別しないので、環境で変わる文が CLAUDE.md に入ったことはここで捕まえる
check "CLAUDE.md はどの環境でも同じ" 'c="$work/linux-main/home/.claude/CLAUDE.md"; cmp -s "$c" "$work/windows-main/home/.claude/CLAUDE.md" && cmp -s "$c" "$work/linux-desktop/home/.claude/CLAUDE.md" && cmp -s "$c" "$work/darwin-main/home/.claude/CLAUDE.md" && cmp -s "$c" "$work/darwin-work/home/.claude/CLAUDE.md"'

# --- Windows ---
for file in .wslconfig OneDrive/Documents/PowerShell/Microsoft.PowerShell_profile.ps1 .claude/settings.json .claude/CLAUDE.md .vimrc .local/bin/op-run.ps1 .local/bin/op-run.cmd .local/bin/split-pdf .local/bin/split-pdf.cmd .local/bin/usage-log .local/bin/usage-log.cmd; do
  check "windows-main: $file がある" '[ -f "$work/windows-main/home/$file" ]'
done
check "windows-main: plamo-server.cmd がある" '[ -f "$work/windows-main/home/.local/bin/plamo-server.cmd" ]'
check "windows-main: plamo-server は 127.0.0.1 だけで待ち受け、CORS を localhost に絞る" 'grep -qF -- "--host 127.0.0.1 --port 8077 --cors-origins localhost --no-cors-credentials" "$work/windows-main/home/.local/bin/plamo-server.cmd"'
for file in .tmux.conf .ssh .config/environment.d .local/bin/op-run .zshrc .zprofile; do
  blocked "windows-main: $file がない" '[ -e "$work/windows-main/home/$file" ]'
done
equals "windows-main: gpg-agent.conf は既存の行を残し、キャッシュを WSL と同じにする" "$(cat "$work/windows-main/home/.gnupg/gpg-agent.conf")" 'pinentry-program C:\pinentry.exe
default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200'
check "windows-main: .vimrc が VS Code 用" 'cmp -s "$work/windows-main/home/.vimrc" "$root/home/.vimrc-files/vscode.vimrc"'
equals "windows-main: 実行するスクリプト" "$(scripts_of windows-main)" "10-mise-install.ps1 20-build-hooks.ps1 50-gh-extensions.ps1"

# --- WSL ではない PC (desktop) ---
data_of() { cm "$1" data --format json | jq -r "$2"; }
equals "linux-desktop: host" "$(data_of linux-desktop .host)" desktop
equals "linux-main: host" "$(data_of linux-main .host)" wsl
equals "windows-main: host と、WSL と同じ鍵" "$(data_of windows-main '.host + " " + .signingKey')" "windows 78324D99D34D3111"
# linux-main の review-loop の台帳は、上で置いたもの
equals "linux-desktop: 置かれるファイルは linux-main から WSLg の設定を除いたもの" "$(files_of linux-desktop)" \
  "$(files_of linux-main | tr ' ' '\n' | grep -vxE '\.config/environment\.d/wslg\.conf|\.local/state/review-loop/repo/branch/ledger\.md' | paste -sd ' ' -)"
equals "linux-desktop: 実行するスクリプトは linux-main と同じ" "$(scripts_of linux-desktop)" "$(scripts_of linux-main)"
check "linux-main: Windows 側の mise の設定を読まない" 'grep -q MISE_IGNORED_CONFIG_PATHS "$work/linux-main/home/.bash_profile"'
blocked "linux-desktop: /mnt/c を前提にしない" 'grep -q MISE_IGNORED_CONFIG_PATHS "$work/linux-desktop/home/.bash_profile"'
check "linux-desktop: コミット署名が有効" 'grep -q "gpgsign = true" "$work/linux-desktop/home/.gitconfig"'
blocked "linux-desktop: 鍵を作る前は signingkey を書かない" 'grep -q signingkey "$work/linux-desktop/home/.gitconfig"'
equals "linux-desktop: 鍵を作る前の signingKey は空" "$(data_of linux-desktop .signingKey)" ""
DOTFILES_SIGNING_KEY=1111222233334444 init_of linux-desktop >/dev/null 2>&1 && cm linux-desktop apply --exclude scripts,externals >/dev/null 2>&1
check "linux-desktop: 作った鍵が signingkey になる" 'grep -qx "	signingkey = 1111222233334444" "$work/linux-desktop/home/.gitconfig"'
check "linux-desktop: 環境変数なしで init し直せる" 'init_of linux-desktop'
equals "linux-desktop: 環境変数なしで init し直しても鍵と host が残る" "$(data_of linux-desktop '.signingKey + " " + .host')" "1111222233334444 desktop"
check "linux-main: DOTFILES_SIGNING_KEY を付けて init し直せる" 'DOTFILES_SIGNING_KEY=1111222233334444 init_of linux-main'
equals "linux-main: DOTFILES_SIGNING_KEY があっても、Windows と同じ鍵のまま" "$(data_of linux-main .signingKey)" 78324D99D34D3111
# カーネルを差し替えて、WSL とそれ以外の両方を、どの機械でも試す。host は設定に残るので、毎回作り直す
mkdir -p "$work/linux-detect/home" "$work/linux-detect/fakehome"
for kernel in 5.15.167.4-microsoft-standard-WSL2:wsl 6.8.0-49-generic:desktop; do
  rm -f "$work/linux-detect/chezmoi.toml"
  KERNEL="${kernel%%:*}" init_of linux-detect >/dev/null 2>&1
  equals "DOTFILES_HOST がなければ、カーネルから判定する (${kernel%%:*})" "$(data_of linux-detect .host)" "${kernel#*:}"
done
mkdir -p "$work/linux-bad/home" "$work/linux-bad/fakehome"
blocked "desktop に agent は作れない" 'DOTFILES_PROFILE=agent DOTFILES_HOST=desktop init_of linux-bad'
blocked "DOTFILES_HOST で mac は選べない (mac は OS で決まる)" 'DOTFILES_HOST=mac init_of linux-bad'

# --- mac ---
equals "darwin-main: work は false" "$(data_of darwin-main '.work | tojson')" false
equals "darwin-main: 置かれるファイルは linux-desktop から bash の設定と 1Password のものを除き、zsh の設定を足したもの" "$(files_of darwin-main)" \
  "$({ files_of linux-desktop | tr ' ' '\n' | grep -vxE '\.bashrc|\.bash_profile|\.local/bin/op-run|\.claude/rules/secrets\.md'; printf '%s\n' .zprofile .zshrc; } | sort | paste -sd ' ' -)"
equals "darwin-main: 実行するスクリプトは linux-desktop と同じ" "$(scripts_of darwin-main)" "$(scripts_of linux-desktop)"
# files_of は external を含まないので、Codex のスキルを置かないことはここで確かめる
equals "darwin-main: スキルは Claude のものだけ置く" "$(actual_skills darwin-main)" \
  "$(expected_skills darwin-main | tr ' ' '\n' | grep -v '^\.agents/' | paste -sd ' ' -)"
equals "darwin-main: 鍵を渡す前の signingKey は空" "$(data_of darwin-main .signingKey)" ""
equals "darwin-main: gpg-agent.conf に pinentry-mac を足し、SSH の設定はしない" "$(cat "$work/darwin-main/home/.gnupg/gpg-agent.conf")" 'pinentry-program /opt/homebrew/bin/pinentry-mac
default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200
disable-scdaemon'
equals "darwin-work: gpg-agent.conf は、2 行目以降にある既存の pinentry-program も残し、pinentry-mac を足さない" "$(cat "$work/darwin-work/home/.gnupg/gpg-agent.conf")" 'pinentry-program /Applications/IDE.app/pinentry.sh
default-cache-ttl 86400
max-cache-ttl 259200
default-cache-ttl-ssh 86400
max-cache-ttl-ssh 259200
disable-scdaemon'
check "darwin-main: GitHub の SSH の鍵を ssh-agent に読み込み、パスフレーズを Keychain に保存する" 'grep -qx "    AddKeysToAgent yes" "$work/darwin-main/home/.ssh/config" && grep -qx "    UseKeychain yes" "$work/darwin-main/home/.ssh/config"'
blocked "linux-main: SSH の設定に mac だけの行がない" 'grep -qE "UseKeychain|AddKeysToAgent" "$work/linux-main/home/.ssh/config"'
if command -v zsh >/dev/null; then
  zhome="$work/zsh-home"
  mkdir -p "$zhome"
  cp "$work/darwin-main/home/.zshrc" "$work/darwin-main/home/.zprofile" "$zhome/"
  printf 'export DOTFILES_LOCAL_LOADED=1\nalias ls=local-ls\n' >"$zhome/.zshrc.local"
  # 動かしている機械の mise やシェルの環境に左右されないように、環境を空にして動かす
  zsh_in() { env -i HOME="$zhome" PATH=/usr/bin:/bin "$(command -v zsh)" "$@" </dev/null 2>/dev/null; }
  equals "darwin-main: .zshrc が最後まで読めて、最後に ~/.zshrc.local を読む (ローカルの値が勝つ)" "$(zsh_in -i -c 'print -r -- $DOTFILES_LOCAL_LOADED ${aliases[ls]}')" "1 local-ls"
  equals "darwin-main: .zprofile が ~/.local/bin と mise を PATH の先頭に置く" "$(zsh_in -l -c 'print -r -- ${path[1,3]}')" \
    "$zhome/.local/bin $zhome/go/bin $zhome/.local/share/mise/shims"
  equals "darwin-main: ログインシェルを入れ子にしても、PATH の項目が重ならない" "$(zsh_in -l -c 'zsh -l -c '\''u=(${(u)path}); print -r -- $(( ${#path} - ${#u} ))'\''')" 0
elif [ -n "${CI:-}" ]; then
  fail "CI に zsh が無い (tests/ci/setup.sh で入れる)"
else
  printf 'SKIP zsh が無いので、mac の zsh の設定を動かす検査を飛ばす\n'
fi
DOTFILES_SIGNING_KEY=1111222233334444 init_of darwin-work >/dev/null 2>&1
check "darwin-work: 環境変数なしで init し直せる" 'init_of darwin-work'
equals "darwin-work: 環境変数なしで init し直しても鍵、host、work が残る" "$(data_of darwin-work '.signingKey + " " + .host + " " + (.work | tojson)')" "1111222233334444 mac true"
DOTFILES_WORK=0 init_of darwin-work >/dev/null 2>&1
equals "darwin-work: DOTFILES_WORK=0 で work が false に戻る" "$(data_of darwin-work '.work | tojson')" false
mkdir -p "$work/darwin-bad/home" "$work/darwin-bad/fakehome"
blocked "mac に agent は作れない" 'DOTFILES_PROFILE=agent init_of darwin-bad'
blocked "DOTFILES_WORK が 1 か 0 でなければ init で止まる" 'DOTFILES_WORK=yes init_of darwin-bad'
DOTFILES_HOST=desktop init_of darwin-bad >/dev/null 2>&1
equals "mac では DOTFILES_HOST を読まない" "$(data_of darwin-bad .host)" mac
mkdir -p "$work/darwin-moved/home" "$work/darwin-moved/fakehome"
printf '[data]\n    profile = "main"\n    host = "desktop"\n' >"$work/darwin-moved/chezmoi.toml"
init_of darwin-moved >/dev/null 2>&1
equals "mac では、設定に残った host も読まない" "$(data_of darwin-moved .host)" mac

# --- work ---
# work は mac に限らず、どの host でも同じに読む。Windows と WSL は bootstrap.ps1 と user.sh が
# DOTFILES_PROFILE だけを付けて init し直すので、設定に残ることが work を保つ唯一の経路になる
equals "linux-main と windows-main: work の既定は false" "$(data_of linux-main '.work | tojson') $(data_of windows-main '.work | tojson')" "false false"
for entry in linux-work-wsl:wsl linux-work-desktop:desktop windows-work:; do
  name="${entry%%:*}"
  mkdir -p "$work/$name/home" "$work/$name/fakehome"
  DOTFILES_HOST="${entry#*:}" DOTFILES_WORK=1 init_of "$name" >/dev/null 2>&1
  equals "$name: DOTFILES_WORK=1 で work が true" "$(data_of "$name" '.work | tojson')" true
  check "$name: PR運用の指示を置く" 'cm "$name" cat "$work/$name/home/.claude/rules/pr.md" | grep -qF -- "--assignee @me"'
  check "$name: 環境変数なしで init し直せる" 'init_of "$name"'
  equals "$name: 環境変数なしで init し直しても work が残る" "$(data_of "$name" '.work | tojson')" true
  DOTFILES_WORK=0 init_of "$name" >/dev/null 2>&1
  equals "$name: DOTFILES_WORK=0 で work が false に戻る" "$(data_of "$name" '.work | tojson')" false
done
# work ができる前の設定。init し直さずに apply する機械では、これがそのまま読まれる
mkdir -p "$work/linux-legacy/home" "$work/linux-legacy/fakehome"
printf '[data]\n    profile = "main"\n    host = "wsl"\n    name = "Maru32768"\n    email = "maru32768@gmail.com"\n    signingKey = "78324D99D34D3111"\n' >"$work/linux-legacy/chezmoi.toml"
check "work がない設定でも適用できる" 'cm linux-legacy apply --exclude scripts,externals'
blocked "work がない設定では PR運用の指示を置かない" '[ -e "$work/linux-legacy/home/.claude/rules/pr.md" ]'

# --- プロファイル ---
profile_of() { sed -n 's/^ *profile = "\(.*\)"$/\1/p' "$work/$1/chezmoi.toml"; }
check "linux-agent: 環境変数なしで init し直せる" 'init_of linux-agent'
equals "環境変数なしで init し直しても agent のまま" "$(profile_of linux-agent)" agent
mkdir -p "$work/linux-default/home" "$work/linux-default/fakehome"
init_of linux-default >/dev/null 2>&1
equals "新しい環境の既定は main" "$(profile_of linux-default)" main

# --- init_of と本物の init ---
# 動いている機械の OS なら差し替えが要らないので、本物の chezmoi init と同じ設定になることを、
# 新しく作るときと、設定がある状態で環境変数なしでやり直すときの両方で確かめる。
# 設定が残ることの検査はどれも init_of を通るので、やり直しの比較がそれを本物の init につなぐ。
# つなぐのは、Linux (CI) では profile、host、work で、mac では signingKey と work。
# Linux では host を wsl にするので、テンプレートは既存の設定の signingKey を読まない
real_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
fresh="$real_os-fresh" again="$real_os-again" first_profile=main
# mac には agent を作れない。Linux では、本物の init でも agent が残ることを確かめる
[ "$real_os" = linux ] && first_profile=agent
mkdir -p "$work/$fresh/home" "$work/$fresh/fakehome" "$work/$again/home" "$work/$again/fakehome"
DOTFILES_PROFILE=$first_profile DOTFILES_HOST=wsl DOTFILES_WORK=1 DOTFILES_SIGNING_KEY=1111222233334444 cm "$fresh" init </dev/null >/dev/null 2>&1 &&
  mv "$work/$fresh/chezmoi.toml" "$work/$fresh/real.toml"
DOTFILES_PROFILE=$first_profile DOTFILES_HOST=wsl DOTFILES_WORK=1 DOTFILES_SIGNING_KEY=1111222233334444 init_of "$fresh" >/dev/null 2>&1
check "init_of は本物の chezmoi init と同じ設定を作る ($real_os、新しく作る)" 'cmp -s "$work/$fresh/real.toml" "$work/$fresh/chezmoi.toml"'
cp "$work/$fresh/real.toml" "$work/$again/chezmoi.toml" && cm "$again" init </dev/null >/dev/null 2>&1 &&
  mv "$work/$again/chezmoi.toml" "$work/$again/real.toml" && cp "$work/$fresh/real.toml" "$work/$again/chezmoi.toml"
# 失敗すると写した前の設定が残り、正しいやり直しと同じ中身になるので、成否も見る
check "init_of で環境変数なしでやり直せる ($real_os)" 'init_of "$again"'
check "init_of は本物の chezmoi init と同じ設定を作る ($real_os、環境変数なしでやり直す)" 'cmp -s "$work/$again/real.toml" "$work/$again/chezmoi.toml"'
equals "本物の chezmoi init でも、やり直すと profile が残る ($real_os)" "$(sed -n 's/^ *profile = "\(.*\)"$/\1/p' "$work/$again/real.toml")" "$first_profile"

# --- テンプレートから作られるシェルスクリプト ---
for template in "$root"/home/*.sh.tmpl "$root"/home/dot_bashrc.tmpl "$root"/home/dot_bash_profile.tmpl; do
  rendered="$work/rendered-$(basename "$template")"
  for name in linux-main linux-agent linux-desktop; do
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
