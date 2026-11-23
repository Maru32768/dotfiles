#!/bin/bash
# 文書の見出し(#で始まる行)を、「ファイル:行: 見出し」の形で並べる。フェンスで囲んだコードブロックの中の#は
# 拾わない。
#
#   outline.sh <ファイル>...
#
# フェンスの読み方は、lost.shと同じにしてある。箇条書きの記号と同じ行で開くフェンス(- ```sh)を読み、
# 後ろに`がある`の並び(```js```)はフェンスにしない。閉じるのは、開いたときと同じ記号が同じ数以上あり、
# 後ろに何も無く、開いた行より4つ以上深く字下げしていない行だけ(中に別のフェンスを書ける)。箇条書きの
# 記号と同じ行で開いたフェンスは、記号の幅より浅く字下げした行で終わる。
# 字下げだけで書いたコードブロックと、引用(>)の中のフェンスは、コードブロックとして読まない。
set -uo pipefail

[ $# -gt 0 ] || { printf 'usage: outline.sh <ファイル>...\n' >&2; exit 2; }
files=()
for f in "$@"; do
  [ -r "$f" ] && [ ! -d "$f" ] || { printf 'outline.sh: 読めない: %s\n' "$f" >&2; exit 2; }
  # awkは「名前=値」の形の引数を変数への代入として、-を標準入力として読む
  case "$f" in /* | ?:* | ./*) files+=("$f") ;; *=* | -) files+=("./$f") ;; *) files+=("$f") ;; esac
done

LC_ALL=C awk '
# lost.shのfence_lenと同じ。行頭の`か~の数を返し、記号をfmark、後ろに何も無いかをfbare、字下げの幅をfind、
# 箇条書きの記号の幅をfleadに入れる
function fence_len(s,   c, n, lead) {
  if (!fence && match(s, /^[ \t]*([-*+]|[0-9]+[.)])[ \t]+/)) { lead = RLENGTH; s = substr(s, RLENGTH + 1) }
  find = lead + match(s, /[^ \t]/) - 1
  sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s)
  c = substr(s, 1, 1)
  if (c != "`" && c != "~") return 0
  for (n = 1; substr(s, n + 1, 1) == c; n++) ;
  if (c == "`" && index(substr(s, n + 1), "`")) return 0
  fmark = c; fbare = (n == length(s)); flead = lead + 0
  return n >= 3 ? n : 0
}
FNR == 1 { fence = 0 }
{ n = fence_len($0) }
fence && fcol && /[^ \t\r]/ && match($0, /[^ \t]/) - 1 < fcol { fence = 0; n = fence_len($0) }
!fence && n { fence = n; fopen = fmark; fin = find; fcol = flead; next }
fence && n >= fence && fmark == fopen && fbare && find <= fin + 3 { fence = 0; next }
fence { next }
/^#/ { print FILENAME ":" FNR ": " $0 }
' "${files[@]}"
