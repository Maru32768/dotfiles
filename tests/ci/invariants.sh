#!/bin/bash
# コメントや手順でしか守られていない約束を確かめる。
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 1

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# Windows PowerShell 5.1 は BOM なしの UTF-8 を、cmd はコードページの違う文字を読み違える
# mac の grep には -P が無いので、ASCII を消して何か残るかを見る
has_non_ascii() { [ -n "$(LC_ALL=C tr -d '\000-\177' | head -c 1)" ]; }
# tr が失敗すると何も残らず、どのファイルも ASCII だけに見えるので、先に試す
if printf 'caf\303\251' | has_non_ascii; then
  non_ascii="$(git ls-files -co --exclude-standard '*.ps1' '*.ps1.tmpl' '*.cmd' | while IFS= read -r file; do
    [ -e "$file" ] && has_non_ascii <"$file" && printf '%s\n' "$file"
  done)"
  if [ -z "$non_ascii" ]; then pass "PowerShell と cmd のスクリプトが ASCII だけ"; else fail "PowerShell と cmd のスクリプトが ASCII 以外を含む: $non_ascii"; fi
else
  fail "ASCII の検査が、ASCII でない文字を見つけられない"
fi

# mac の /bin/bash (3.2) は、UTF-8 のロケールで、変数の直後の日本語のバイトを名前の一部として読み、
# set -u で止まる。${} で囲む。shellcheck は見つけない
bash_scripts() {
  git ls-files -co --exclude-standard | while IFS= read -r file; do
    [ -f "$file" ] || continue
    case "$file" in *.sh | *.sh.tmpl) ;; *) head -n 1 "$file" | grep -q '^#!.*bash' || continue ;; esac
    printf '%s\n' "$file"
  done
}
bare_vars="$(bash_scripts | while IFS= read -r file; do
  perl -ne 'print "$ARGV:$.\n" if /^[^#]*\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]/' "$file"
done)"
if [ -z "$bare_vars" ]; then pass "bash のスクリプトで、変数の直後に ASCII でない文字が無い"; else fail "bash のスクリプトで、変数の直後に ASCII でない文字がある (\${} で囲む): $bare_vars"; fi

# 表記は v の有無が違う (docs/tools.md)
mise_linux="$(sed -n 's/^MISE_VERSION="v\(.*\)"$/\1/p' provision/user.sh)"
mise_windows="$(sed -n "s/^\$MiseVersion = '\(.*\)'.*$/\1/p" bootstrap.ps1 | tr -d '\r')"
if [ -n "$mise_linux" ] && [ "$mise_linux" = "$mise_windows" ]; then
  pass "mise 本体のバージョンが揃っている ($mise_linux)"
else
  fail "mise 本体のバージョンが違う: provision/user.sh=$mise_linux bootstrap.ps1=$mise_windows"
fi

# フィンガープリントはスクリプトごとに持っている。chezmoi の外でも動く必要があるため
fingerprints="$(grep -hoE '[0-9A-F]{40}' tests/doctor.sh tests/doctor.ps1 provision/setup-credentials.sh provision/gpg_import_key.sh docs/gpg.md | sort -u)"
# desktop は PC ごとの鍵なので、比べるのは Windows と WSL の鍵 ($mainSigningKey) だけ
signing_key="$(sed -n 's/^.*[$]mainSigningKey := "\([0-9A-F]*\)".*$/\1/p' home/.chezmoi.toml.tmpl)"
if [ "$(printf '%s\n' "$fingerprints" | wc -l)" -ne 1 ]; then
  fail "GPG のフィンガープリントが揃っていない: $(printf '%s ' "$fingerprints")"
elif [ "${fingerprints: -16}" != "$signing_key" ]; then
  fail "signingKey がフィンガープリントと合わない: $signing_key"
else
  pass "GPG の鍵の指定が揃っている"
fi

for file in home/.claude-settings.json provision/agent/managed-settings.json provision/research/managed-settings.json packages/winget.json; do
  if jq empty "$file" 2>/dev/null; then pass "JSON: $file"; else fail "JSON が壊れている: $file"; fi
done

# research の管理設定は agent のものと、Web のツール、Bash の通信先と書き込み先、隠す環境変数だけが違う。
# agent に足した拒否ルールなどを research に足し忘れないように
shared_settings='del(.sandbox.network.allowedDomains, .sandbox.filesystem.allowWrite, .sandbox.credentials.envVars)
  | .permissions.allow -= ["WebFetch", "WebSearch"] | .permissions.deny -= ["WebFetch", "WebSearch"]'
# jq が失敗すると両方とも空になって一致してしまうので、終了コードも見る
if agent_shared="$(jq -S "$shared_settings" provision/agent/managed-settings.json)" &&
  research_shared="$(jq -S "$shared_settings" provision/research/managed-settings.json)" &&
  [ "$agent_shared" = "$research_shared" ]; then
  pass "research の管理設定が、決めた違いのほかは agent と同じ"
else
  fail "research の管理設定が、決めた違いのほかでも agent と違う (tests/ci/invariants.sh の shared_settings)"
fi

# インストーラーに渡す値なので、正確なバージョンでなければならない
if grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' provision/agent/claude-version; then
  pass "agent の Claude Code のバージョン指定"
else
  fail "agent の Claude Code のバージョン指定が不正"
fi

[ "$failures" -eq 0 ]
