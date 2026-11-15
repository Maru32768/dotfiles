#!/bin/bash
# op-run (home/dot_local/bin/executable_op-run) を、偽の gpg と op で試す。ネットワークも鍵も使わない。
# check に渡す文字列の中で変数を展開するので、SC2016 と SC2034 を抑える
# shellcheck disable=SC2016,SC2034
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/home/dot_local/bin/executable_op-run"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
blocked() { if eval "$2" >/dev/null 2>&1; then fail "$1"; else pass "$1"; fi; }

token="ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9-_$$"
mkdir -p "$work/bin" "$work/items"
printf 'encrypted' >"$work/token.gpg"

# 偽の gpg: 暗号化では、宛先が TESTKEY のときだけ、入力に enc: を付けて --output に書く。
# 復号ではトークン (FAKE_TOKEN があればそれ) を返す
cat >"$work/bin/gpg" <<EOF
#!/bin/bash
if [[ " \$* " == *" --encrypt "* ]]; then
  [[ " \$* " == *" --recipient TESTKEY "* ]] || exit 3
  { printf 'enc:'; cat; } >"\${*: -1}"
  exit 0
fi
[ "\${*: -1}" = "$work/token.gpg" ] || exit 2
printf '%s\n' "\${FAKE_TOKEN:-$token}"
EOF

# 偽の op: トークンが合わなければ失敗する。vault の ID ごとのディレクトリにアイテムを置き、
# 求められた vault の ID を記録する。FAKE_VAULTS で vault の一覧を変える。
# 本物の op は標準入力からも対象を読むので、端末でない標準入力は読み捨てる
cat >"$work/bin/op" <<EOF
#!/bin/bash
[ -t 0 ] || cat >/dev/null
[ "\${OP_SERVICE_ACCOUNT_TOKEN:-}" = "$token" ] || { echo "bad token" >&2; exit 1; }
case "\$1 \$2" in
  "vault list") cat "\${FAKE_VAULTS:-$work/vaults.json}" ;;
  "item list")
    printf '%s' "\$4" >"$work/requested-vault"
    jq -s 'map({id, title})' "$work/items/\$4"/*.json ;;
  "item get") [ "\$3" != broken ] || exit 1; cat "$work/items/\$5/\$3.json" ;;
  *) exit 4 ;;
esac
EOF
chmod +x "$work/bin/gpg" "$work/bin/op"

jq -n '[{id: "v-noodlemap", name: "noodlemap"}, {id: "v-lattice", name: "lattice"}, {id: "v-bad", name: "bad"},
  {id: "v-dupkey", name: "dupkey"}, {id: "v-none", name: "none"}, {id: "v-two", name: "two"},
  {id: "v-broken", name: "broken"}, {id: "v-emptytitle", name: "emptytitle"}, {id: "v-nltitle", name: "nltitle"}]' >"$work/vaults.json"
jq -n '[{id: "v-dup", name: "dup"}, {id: "v-dup2", name: "dup"}]' >"$work/vaults-dup.json"

# 使い方: item <vault の ID> <アイテムの ID> <タイトル> [秘匿フィールドの値...]
item() {
  local vault="$1" id="$2" title="$3"
  shift 3
  mkdir -p "$work/items/$vault"
  jq -n --arg id "$id" --arg title "$title" '{id: $id, title: $title,
    fields: ([{id: "username", type: "STRING", value: "someone"}] + [$ARGS.positional[] | {type: "CONCEALED", value: .}])}' \
    --args "$@" >"$work/items/$vault/$id.json"
}
item v-noodlemap i1 CLOUDFLARE_API_TOKEN "cf value"
item v-noodlemap i2 MULTI "line1
line2 = x"
item v-noodlemap i3 EMPTY_EXTRA "kept" ""
item v-bad i1 BAD=NAME x
item v-dupkey i1 A 1
item v-dupkey i2 A 2
item v-none i1 NOTHING
item v-two i1 TWO a b
item v-broken i1 GOOD g
item v-broken broken BROKEN b
item v-emptytitle i1 "" "SEKRIT-EMPTY"
item v-nltitle i1 "FOO
" "SEKRIT-NL"
# 検査がどれか 1 つではなくすべてのアイテムを見ることを確かめるため、正しいアイテムも置く
for vault in v-bad v-two v-emptytitle v-nltitle; do item "$vault" i0 GOOD g; done

run() { env PATH="$work/bin:$PATH" OP_RUN_TOKEN_FILE="$work/token.gpg" "$@"; }

out="$(run bash "$script" noodlemap -- bash -c 'printf "%s|%s|%s|%s" "$CLOUDFLARE_API_TOKEN" "$MULTI" "$EMPTY_EXTRA" "${OP_SERVICE_ACCOUNT_TOKEN-unset}"')"
check "秘匿フィールドの値がコマンドの環境変数に入る (空の秘匿フィールドは数えない)" '[ "$out" = "cf value|line1
line2 = x|kept|unset" ]'
check "vault 名から ID を引いて渡す" '[ "$(cat "$work/requested-vault")" = v-noodlemap ]'
out="$(run env OP_SERVICE_ACCOUNT_TOKEN=caller-token bash "$script" noodlemap env)"
check "-- を省いても動く" '[[ "$out" == *"CLOUDFLARE_API_TOKEN=cf value"* ]]'
blocked "トークンがコマンドに渡らない" '[[ "$out" == *"$token"* ]]'
blocked "呼び出し元の OP_SERVICE_ACCOUNT_TOKEN もコマンドに渡らない" '[[ "$out" == *caller-token* ]]'
blocked "アイテムのほかのフィールドは渡さない" '[[ "$out" == *someone* ]]'

run bash "$script" noodlemap -- bash -c 'exit 7'
check "コマンドの終了コードを返す" '[ "$?" = 7 ]'

out="$(printf 'piped input\n' | run bash "$script" noodlemap -- cat)"
check "標準入力は op でなくコマンドに渡る" '[ "$out" = "piped input" ]'

out="$(run bash "$script" --list noodlemap)"
check "--list は名前だけを出す" '[ "$out" = "CLOUDFLARE_API_TOKEN
EMPTY_EXTRA
MULTI" ]'

marker="$work/ran"
blocked "知らない vault は失敗する" 'run bash "$script" nope -- touch "$marker"'
blocked "vault 名は大文字と小文字を区別して比べる" 'run bash "$script" NOODLEMAP -- touch "$marker"'
check "同じ名前の vault が複数あれば、そう伝えて失敗する" '! FAKE_VAULTS="$work/vaults-dup.json" run bash "$script" dup -- touch "$marker" 2>"$work/err" && grep -q "vault dup が 2 個ある" "$work/err"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
blocked "環境変数にできない名前があれば失敗する" 'run bash "$script" bad -- touch "$marker"'
for vault in emptytitle nltitle; do
  check "タイトルが $vault でも、名前の検査で止まり、値を出さない" '! run bash "$script" $vault -- touch "$marker" 2>"$work/err" && grep -q "環境変数にできない名前がある" "$work/err" && ! grep -q SEKRIT "$work/err"'
done
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
blocked "同じ名前のアイテムが複数あれば失敗する" 'run bash "$script" dupkey -- touch "$marker"'
blocked "秘匿フィールドのないアイテムがあれば失敗する" 'run bash "$script" none -- touch "$marker"'
check "秘匿フィールドが 2 つあるアイテムがあれば、そう伝えて失敗する" '! run bash "$script" two -- touch "$marker" 2>"$work/err" && grep -q "ちょうど 1 つではない.*TWO" "$work/err"'
blocked "アイテムを取得できなければ失敗する" 'run bash "$script" broken -- touch "$marker"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
blocked "トークンのファイルがなければ失敗する" 'env PATH="$work/bin:$PATH" OP_RUN_TOKEN_FILE="$work/missing.gpg" bash "$script" noodlemap -- touch "$marker"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'
blocked "コマンドがなければ失敗する" 'run bash "$script" noodlemap --'
check "保存したトークンの形式が違えば、そう伝えて失敗する" '! FAKE_TOKEN="$token$token" run bash "$script" noodlemap -- touch "$marker" 2>"$work/err" && grep -q "トークンの形式が違う" "$work/err"'
blocked "そのときコマンドは実行しない" '[ -e "$marker" ]'

# --set-token は端末から読むので、script で疑似端末を用意する
set_token() { printf '%s\n' "$1" | env PATH="$work/bin:$PATH" OP_RUN_GPG_RECIPIENT=TESTKEY OP_RUN_TOKEN_FILE="$work/new/token.gpg" script -qec "bash '$script' --set-token" /dev/null; }
blocked "--set-token は 2 回貼り付けたトークンを保存しない" 'set_token "$token$token" && [ -e "$work/new/token.gpg" ]'
blocked "--set-token は ops_ で始まらないトークンを保存しない" 'set_token "0.11111111-2222-3333-4444-555555555555.secret:a2V5==" && [ -e "$work/new/token.gpg" ]'
check "--set-token は前後の空白を除き、署名の鍵に暗号化して保存する" 'set_token " $token " && [ "$(cat "$work/new/token.gpg")" = "enc:$token" ]'

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
