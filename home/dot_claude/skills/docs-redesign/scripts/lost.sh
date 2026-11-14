#!/bin/bash
# 構成を変える前の文書にあった技術的な記述が、変えた後の文書のどこにも無ければ挙げる。
# 見るのは、コードブロックの行、インラインコード、リンク先、URL。地の文に書いた事実は見ない。
# リンク先は、](行き先)、[名前]: 行き先、href="行き先"の形で書いたもの。
# 字下げだけで書いたコードブロック、引用(>)の中のフェンス、箇条書きの記号と同じ行で開くフェンスは、
# コードブロックとして読まない。
#
#   lost.sh <前のファイル>... -- <後のファイル>...
#
# 1行に「種類<TAB>前のファイル:行<TAB>記述」を出す。種類はcode、line、span、part、link、url。
# コードブロックの行が無いとき、その行の語(英数字と_が3文字以上続くもの)がすべて後のどこかに
# 残っていればline、語のどれかが無いか、語が1つも無い行はcodeにする。lineは、書き方を変えたか、
# 別の例に替えた行に多い。
# 行をまたいで折り返したインラインコードは、つないで読まない。閉じない`の並びがある行から読んだものを、
# partとして挙げる。折り返したインラインコードの切れ端か、記号として書いた`の前後の地の文になる。
# 空白の違いは無視する。後のファイルのどこかの1行に同じ文字列があれば、残っているとみなす。
# ただし、別の語の一部になっている一致は数えない(-fは--forceがあっても、.envは.env.exampleが
# あっても、残っているとみなさない)。
# 同じ記述は、最初に見つけた場所で1回だけ出す。
# 終了コードは、挙げるものが無ければ0、あれば1。使い方の誤りと読めないファイルは2。
set -uo pipefail

die() { printf 'lost.sh: %s\n' "$1" >&2; exit 2; }

before=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
  # awkは「名前=値」の形の引数を変数への代入として、-を標準入力として読む
  case "$1" in /* | ?:* | ./*) before+=("$1") ;; *=* | -) before+=("./$1") ;; *) before+=("$1") ;; esac
  shift
done
[ $# -gt 0 ] || die "usage: lost.sh <前のファイル>... -- <後のファイル>..."
shift
[ ${#before[@]} -gt 0 ] && [ $# -gt 0 ] || die "usage: lost.sh <前のファイル>... -- <後のファイル>..."
for f in "${before[@]}" "$@"; do [ -r "$f" ] && [ ! -d "$f" ] || die "読めない: $f"; done

# 後のファイルは、引数の長さの上限に当たらないよう、1つのファイルにまとめてawkに読ませる
hay="$(mktemp)" || die "一時ファイルを作れない"
trap 'rm -f "$hay"' EXIT
# 末尾に改行の無いファイルが、次のファイルの1行目とつながらないよう、ファイルごとに改行を足す。
# catに-という名前を渡すと、--の後ろでも標準入力を読むので、リダイレクトで開く
for f in "$@"; do cat < "$f" || die "後のファイルを読めない: $f"; echo; done > "$hay"

# パスは環境変数で渡す。-vで渡すと、awkがパスの中の\を解釈する
HAY="$hay" awk '
function norm(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
# 後のファイルのどこかの行に、tokが別の語の一部としてではなく現れるか。前後が英数字、_、-の一致と、
# 後ろに.、:、/と英数字が続く一致は数えない(-fと--force、.envと.env.example、/apiと/api/v2)。
# tokの端が英数字、_、-でなければ、その側の隣は見ない(記号で終わる記述は、語の一部になりようがない)
function present(tok,   i, h, off, j, p, l, r) {
  if (index(hay, tok) == 0) return 0
  l = substr(tok, 1, 1) ~ /[A-Za-z0-9_-]/; r = substr(tok, length(tok)) ~ /[A-Za-z0-9_-]/
  for (i = 1; i <= nh; i++) {
    h = hl[i]; off = 0
    while ((j = index(substr(h, off + 1), tok)) > 0) {
      p = off + j
      if ((!l || p == 1 || substr(h, p - 1, 1) !~ /[A-Za-z0-9_-]/) && (!r || substr(h, p + length(tok), 2) !~ "^([A-Za-z0-9_-]|[.:/][A-Za-z0-9])")) return 1
      off = p
    }
  }
  return 0
}
function probe(kind, tok,   s, w) {
  tok = norm(tok)
  if (tok ~ /^[[:punct:] ]*$/ || seen[tok]++ || present(tok)) return
  if (kind == "code") {
    s = tok
    while (match(s, /[A-Za-z0-9_]+/)) {
      w = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
      if (length(w) < 3) continue
      if (index(hay, w) == 0) { kind = "code"; break }
      kind = "line"
    }
  }
  printf "%s\t%s:%d\t%s\n", kind, FILENAME, FNR, tok; lost = 1
}
# sの中のreに合う記述を順に調べ、最後の一致より後ろの残りを返す
function each(kind, s, re, left, right) {
  while (match(s, re)) {
    probe(kind, substr(s, RSTART + left, RLENGTH - left - right))
    s = substr(s, RSTART + RLENGTH)
  }
  return s
}
# sのインラインコードを順に、kindの種類で調べる(kindが空なら調べない)。`の並びは、同じ数の並びで閉じる
# (``a`b``は、a`bを囲む)。閉じない並びの数を返す
function spans(s, kind,   open, i, n, t, u, m, k, j) {
  while ((i = index(s, "`")) > 0) {
    for (n = 1; substr(s, i + n, 1) == "`"; n++) ;
    t = substr(s, i + n); u = t; j = 0
    while (!j && (m = index(u, "`")) > 0) {
      for (k = 1; substr(u, m + k, 1) == "`"; k++) ;
      if (k == n) j = length(t) - length(u) + m
      u = substr(u, m + k)
    }
    if (!j) { open++; s = t; continue }
    if (kind != "") probe(kind, substr(t, 1, j - 1))
    s = substr(t, j + n)
  }
  return open
}
# 行頭の`か~の数を返す。3つに満たなければ0。記号をfmarkに、後ろに何も無いかをfbareに、字下げの幅をfindに入れる
function fence_len(s,   c, n) {
  find = match(s, /[^ \t]/) - 1
  sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s)
  c = substr(s, 1, 1)
  if (c != "`" && c != "~") return 0
  for (n = 1; substr(s, n + 1, 1) == c; n++) ;
  fmark = c; fbare = (n == length(s))
  return n >= 3 ? n : 0
}
BEGIN { while ((getline line < ENVIRON["HAY"]) > 0) { hl[++nh] = norm(line); hay = hay "\n" hl[nh] } }
FNR == 1 { fence = 0 }
{ n = fence_len($0) }
# 閉じるのは、開いたときと同じ記号が同じ数以上あり、後ろに何も無く、開いた行より4つ以上深く字下げして
# いない行だけ(中に別のフェンスを書ける)
!fence && n { fence = n; fopen = fmark; fin = find; next }
fence && n >= fence && fmark == fopen && fbare && find <= fin + 3 { fence = 0; next }
fence { probe("code", $0); next }
{
  # 閉じない`の並びがある行は、インラインコードが行をまたいで折り返しているか、`を記号として書いている。
  # 行をまたいでは読まず、この行だけで調べる。どの並びが対になるかが決まらないので、最初の並びから
  # 対にする読み方と、2つ目の並びから対にする読み方の両方を調べ、最初の並びより前と、最後の並びより
  # 後ろの切れ端も調べる。この行から読んだものは、partとして挙げる
  kind = spans($0, "") ? "part" : "span"
  spans($0, kind)
  if (kind == "part") {
    i = index($0, "`"); probe(kind, substr($0, 1, i - 1))
    s = substr($0, i); sub(/^`+/, "", s); spans(s, kind)
    s = $0; sub(/^.*`/, "", s); probe(kind, s)
  }
  each("link", $0, "\\]\\([^) \t]+", 2, 0)
  each("link", $0, "href=\"[^\"]+", 6, 0)
  # 参照形式のリンクの定義([名前]: 行き先)。脚注([^1]: ...)は除く
  if (match($0, /^[ \t]*\[[^]^][^]]*\]:[ \t]*[^ \t]+/)) {
    s = substr($0, RSTART, RLENGTH); sub(/^[ \t]*\[[^]]*\]:[ \t]*/, "", s); probe("link", s)
  }
  each("url", $0, "https?://[^] \t)>\"`]+", 0, 0)
}
END { exit lost }
' "${before[@]}"
