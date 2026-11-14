#!/bin/bash
# 構成を変える前の文書にあった技術的な記述が、変えた後の文書のどこにも無ければ挙げる。
# 見るのは、コードブロックの行、インラインコード、リンク先、URL。地の文に書いた事実は見ない。
#
#   lost.sh <前のファイル>... -- <後のファイル>...
#
# 1行に「種類<TAB>前のファイル:行<TAB>記述」を出す。種類はcode、span、link、url。
# 空白の違いは無視する。後のファイルのどこかに同じ文字列があれば、残っているとみなす。
# 同じ記述は、最初に見つけた場所で1回だけ出す。
# 終了コードは、挙げるものが無ければ0、あれば1。使い方の誤りと読めないファイルは2。
set -uo pipefail

die() { printf 'lost.sh: %s\n' "$1" >&2; exit 2; }

before=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do before+=("$1"); shift; done
[ $# -gt 0 ] || die "usage: lost.sh <前のファイル>... -- <後のファイル>..."
shift
[ ${#before[@]} -gt 0 ] && [ $# -gt 0 ] || die "usage: lost.sh <前のファイル>... -- <後のファイル>..."
for f in "${before[@]}" "$@"; do [ -r "$f" ] && [ ! -d "$f" ] || die "読めない: $f"; done

# 後のファイルは、引数の長さの上限に当たらないよう、1つのファイルにまとめてawkに読ませる
hay="$(mktemp)" || die "一時ファイルを作れない"
trap 'rm -f "$hay"' EXIT
cat -- "$@" > "$hay" || die "後のファイルを読めない"

awk -v hayfile="$hay" '
function norm(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
function probe(kind, tok) {
  tok = norm(tok)
  if (tok ~ /^[[:punct:] ]*$/ || seen[tok]++) return
  if (index(hay, tok) == 0) { printf "%s\t%s:%d\t%s\n", kind, FILENAME, FNR, tok; lost = 1 }
}
function each(kind, re, left, right,   s) {
  s = $0
  while (match(s, re)) {
    probe(kind, substr(s, RSTART + left, RLENGTH - left - right))
    s = substr(s, RSTART + RLENGTH)
  }
}
BEGIN { while ((getline line < hayfile) > 0) hay = hay "\n" norm(line) }
FNR == 1 { fence = 0 }
/^[ \t]*(```|~~~)/ { fence = !fence; next }
fence { probe("code", $0); next }
{
  each("span", "`[^`]+`", 1, 1)
  each("link", "\\]\\([^) \t]+", 2, 0)
  each("url", "https?://[^ \t)>\"`\\]]+", 0, 0)
}
END { exit lost }
' "${before[@]}"
