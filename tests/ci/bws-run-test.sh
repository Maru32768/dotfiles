#!/bin/bash
# bws-run (home/dot_local/bin/executable_bws-run) を、偽の gpg と bws で試す。ネットワークも鍵も使わない。
# check に渡す文字列の中で変数を展開するので、SC2016 と SC2034 を抑える
# shellcheck disable=SC2016,SC2034
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/home/dot_local/bin/executable_bws-run"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
blocked() { if eval "$2" >/dev/null 2>&1; then fail "$1"; else pass "$1"; fi; }

token="test-token-$$"
mkdir -p "$work/bin"
printf 'encrypted' >"$work/token.gpg"

# 偽の gpg: 復号するとトークンを返す
cat >"$work/bin/gpg" <<EOF
#!/bin/bash
[ "\${*: -1}" = "$work/token.gpg" ] || exit 2
printf '%s\n' "$token"
EOF

# 偽の bws: トークンが合わなければ失敗する。どの ID にも秘密情報を返し、求められた ID を記録する。
# FAKE_SECRETS と FAKE_PROJECTS で返す内容を変える
cat >"$work/bin/bws" <<EOF
#!/bin/bash
[ "\${BWS_ACCESS_TOKEN:-}" = "$token" ] || { echo "bad token" >&2; exit 1; }
case "\$1 \$2" in
  "project list") cat "\${FAKE_PROJECTS:-$work/projects.json}" ;;
  "secret list") printf '%s' "\$3" >"$work/requested-id"; cat "\${FAKE_SECRETS:-$work/secrets.json}" ;;
  *) exit 4 ;;
esac
EOF
chmod +x "$work/bin/gpg" "$work/bin/bws"

jq -n '[{id: "id-noodlemap", name: "noodlemap"}, {id: "id-lattice", name: "lattice"}]' >"$work/projects.json"
jq -n '[{id: "id-dup", name: "dup"}, {id: "id-dup2", name: "dup"}]' >"$work/projects-dup.json"
jq -n '[{key: "CLOUDFLARE_API_TOKEN", value: "cf value"}, {key: "MULTI", value: "line1\nline2 = x"}]' >"$work/secrets.json"
jq -n '[{key: "BAD-NAME", value: "x"}]' >"$work/secrets-bad.json"
jq -n '[{key: "A", value: "1"}, {key: "A", value: "2"}]' >"$work/secrets-dup.json"

run() { env PATH="$work/bin:$PATH" BWS_TOKEN_FILE="$work/token.gpg" "$@"; }

out="$(run bash "$script" noodlemap -- bash -c 'printf "%s|%s|%s" "$CLOUDFLARE_API_TOKEN" "$MULTI" "${BWS_ACCESS_TOKEN-unset}"')"
check "秘密情報がコマンドの環境変数に入る" '[ "$out" = "cf value|line1
line2 = x|unset" ]'
check "プロジェクト名から ID を引いて渡す" '[ "$(cat "$work/requested-id")" = id-noodlemap ]'
out="$(run env BWS_ACCESS_TOKEN=caller-token bash "$script" noodlemap env)"
check "-- を省いても動く" '[[ "$out" == *"CLOUDFLARE_API_TOKEN=cf value"* ]]'
blocked "トークンがコマンドに渡らない" '[[ "$out" == *"$token"* ]]'
blocked "呼び出し元の BWS_ACCESS_TOKEN もコマンドに渡らない" '[[ "$out" == *caller-token* ]]'

run bash "$script" noodlemap -- bash -c 'exit 7'
check "コマンドの終了コードを返す" '[ "$?" = 7 ]'

out="$(run bash "$script" --list noodlemap)"
check "--list は名前だけを出す" '[ "$out" = "CLOUDFLARE_API_TOKEN
MULTI" ]'

blocked "知らないプロジェクトは失敗する" 'run bash "$script" nope -- true'
marker="$work/ran"
blocked "同じ名前のプロジェクトが複数あれば失敗する" 'FAKE_PROJECTS="$work/projects-dup.json" run bash "$script" dup -- touch "$marker"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
rm -f "$marker"
blocked "環境変数にできない名前があれば失敗する" 'FAKE_SECRETS="$work/secrets-bad.json" run bash "$script" noodlemap -- touch "$marker"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
blocked "同じ名前の秘密情報が複数あれば失敗する" 'FAKE_SECRETS="$work/secrets-dup.json" run bash "$script" noodlemap -- true'
blocked "トークンのファイルがなければ失敗する" 'env PATH="$work/bin:$PATH" BWS_TOKEN_FILE="$work/missing.gpg" bash "$script" noodlemap -- true'
blocked "コマンドがなければ失敗する" 'run bash "$script" noodlemap --'

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
