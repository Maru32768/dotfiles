#!/bin/bash
# コメントや手順でしか守られていない約束を確かめる。
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root" || exit 1

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# Windows PowerShell 5.1 は BOM なしの UTF-8 を、cmd はコードページの違う文字を読み違える
non_ascii="$(git ls-files -co --exclude-standard '*.ps1' '*.ps1.tmpl' '*.cmd' | while IFS= read -r file; do
  [ -e "$file" ] && LC_ALL=C grep -lP '[^\x00-\x7F]' "$file"
done)"
if [ -z "$non_ascii" ]; then pass "PowerShell と cmd のスクリプトが ASCII だけ"; else fail "PowerShell と cmd のスクリプトが ASCII 以外を含む: $non_ascii"; fi

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
signing_key="$(sed -n 's/^ *signingKey = "\(.*\)"$/\1/p' home/.chezmoi.toml.tmpl)"
if [ "$(printf '%s\n' "$fingerprints" | wc -l)" -ne 1 ]; then
  fail "GPG のフィンガープリントが揃っていない: $(printf '%s ' "$fingerprints")"
elif [ "${fingerprints: -16}" != "$signing_key" ]; then
  fail "signingKey がフィンガープリントと合わない: $signing_key"
else
  pass "GPG の鍵の指定が揃っている"
fi

for file in home/.claude-settings.json provision/agent/managed-settings.json packages/winget.json; do
  if jq empty "$file" 2>/dev/null; then pass "JSON: $file"; else fail "JSON が壊れている: $file"; fi
done

# インストーラーに渡す値なので、正確なバージョンでなければならない
if grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' provision/agent/claude-version; then
  pass "agent の Claude Code のバージョン指定"
else
  fail "agent の Claude Code のバージョン指定が不正"
fi

[ "$failures" -eq 0 ]
