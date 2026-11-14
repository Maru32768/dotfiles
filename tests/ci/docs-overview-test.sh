#!/bin/bash
# docs-overviewのview.sh(home/dot_claude/skills/docs-overview/scripts)を、使い捨ての概観で試す。ブラウザでの
# 動き(図の描画、CSPでスクリプトが止まるか)は確かめない
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
view="$root/home/dot_claude/skills/docs-overview/scripts/view.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }
# $1の中の、最初の$2と、その後の最初の$3の間
between() { local s=${1#*"$2"}; printf '%s' "${s%%"$3"*}"; }
# <pre id="md">の中身を取り出し、3文字を戻す。&amp;は最後に戻す(先に戻すと、&amp;lt;が<になる)
body_of() { between "$1" '<pre id="md">' '</pre>' | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'; }
title_of() { between "$1" '<title>' '</title>'; }
# 終了コード2で、標準出力が空で、標準エラーに理由を出す
rejects() {
  local name=$1; shift
  bash "$view" "$@" >stdout.txt 2>stderr.txt </dev/null
  local code=$?
  equals "$name" "$code $(wc -c <stdout.txt | tr -d ' ') $([ -s stderr.txt ] && echo stderr)" "2 0 stderr"
}

cd "$work" || exit 1

rejects "引数が無ければ、終了コード2で止まる"
printf '# a\n' > a.md
rejects "引数が2つなら、終了コード2で止まる" a.md a.md
rejects "無いファイルは、終了コード2で止まる" no-such.md
mkdir -p a-dir
rejects "ディレクトリは、終了コード2で止まる" a-dir

# 入力の&amp;と&lt;は、戻した後もそのまま残る(エスケープの順を間違えると、<や&に化ける)
cat > round.md <<'EOF'
# 概観 & <計画>

A & B < C > D。&amp;と&lt;はそのまま書く。

</pre><p>外に出る</p>
</script><script>alert(1)</script>
<SCRIPT src=x></SCRIPT>

`<b>`と``a`b``を使う。


```mermaid
flowchart LR
  A["<入力>"] --> B{判定 & 分岐}
```
末尾の行
EOF
round="$(bash "$view" round.md </dev/null)"
equals "本文を取り出して戻すと、入力と同じになる" "$? $(body_of "$round")" "0 $(cat round.md)"
equals "<scriptで始まるタグは、marked、mermaid、インラインの順に3つだけ" \
  "$(printf '%s' "$round" | grep -io '<script[^>]*>' | sed -e 's/.*marked.*/marked/' -e 's/.*mermaid.*/mermaid/' | tr '\n' ' ')" \
  "marked mermaid <script> "
equals "外部のスタイルシートやフォントを読まない" "$(printf '%s' "$round" | grep -ciE '<link|@import|url\(')" "0"

equals "題は最初の「# 」の行の見出しで、エスケープする" "$(title_of "$round")" "概観 &amp; &lt;計画&gt;"
mkdir -p sub
printf '%s\n' '## 先の節' '#題ではない' 'x' '# 後の見出し' '# 2つ目' > sub/heading.md
equals "題は、最初の「# 」の行より前の##や#の行を使わない" "$(title_of "$(bash "$view" sub/heading.md </dev/null)")" "後の見出し"
printf '%s\n' '## 節だけ' 'x' > 'sub/no title & x.md'
equals "見出しが無ければ、ディレクトリを除いたファイルの名前をエスケープして題にする" \
  "$(title_of "$(bash "$view" 'sub/no title & x.md' </dev/null)")" "no title &amp; x.md"

printf '%s\r\n' '# 題' '' '本文' > crlf.md
out="$(bash "$view" crlf.md </dev/null)"
equals "CRLFの入力でも、出力にCRが無い" "$(printf '%s' "$out" | tr -cd '\r' | wc -c | tr -d ' ') $(title_of "$out")" "0 題"

# awkにそのまま渡すと、代入や標準入力として読み、本文が空になる
printf '%s\n' '名前に=がある' > 'x=1.md'
printf '%s\n' '名前が-で始まる' > '-n.md'
printf '%s\n' '名前が-だけ' > ./-
for name in x=1.md -n.md -; do
  out="$(bash "$view" "$name" </dev/null)"
  equals "ファイルの名前「$name」も、ファイルとして読む" "$? $(title_of "$out") $(body_of "$out")" \
    "0 $name $(cat "./$name")"
done
mkdir -p 'k=v'
printf '%s\n' '# 絶対パス' > 'k=v/o.md'
equals "=を含む絶対パスに、./を足さない" "$(title_of "$(bash "$view" "$work/k=v/o.md" </dev/null)")" "絶対パス"

hash="$(between "$round" '<script>' '</script>' | openssl dgst -sha256 -binary | openssl base64 -A)"
marked='https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js'
mermaid='https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js'
csp="$(printf '%s' "$round" | grep -o 'http-equiv="Content-Security-Policy" content="[^"]*"')"
want="http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'sha256-$hash' $marked $mermaid; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'\""
equals "CSPのsha256-の値は、インラインのスクリプトのハッシュと同じ" "$csp" "$want"
# 消毒とMermaidの設定が効くかは、ブラウザでしか確かめられない。確かめた版のハッシュをここに固定する。インラインの
# スクリプトを変えたら、references/background.mdの「表示用のHTML」の入力をブラウザで開いて確かめ直し、この値を直す
equals "インラインのスクリプトは、ブラウザで確かめた版と同じ" "$hash" 'QKTm0n8qJUJD48mskKbaaCTyeJ15YKm9BdBaGVXJSL4='
head="$(between "$round" '<head>' '</head>')"
equals "CSPの<meta>は<head>の中にあり、<head>にスクリプトが無い" \
  "$(printf '%s' "$head" | grep -c 'http-equiv="Content-Security-Policy"') $(printf '%s' "$head" | grep -ci '<script')" "1 0"
loads() { printf '%s' "$round" | grep -c -F "<script src=\"$1\" integrity=\"$2\" crossorigin=\"anonymous\"></script>"; }
equals "markedを、決めたURLとintegrityで読む" \
  "$(loads "$marked" 'sha512-xeUh+KxNyTufZOje++oQHstlMQ8/rpyzPuM+gjMFYK3z5ILJGE7l2NvYL+XfliKURMpBIKKp1XoPN/qswlSMFA==')" "1"
equals "mermaidを、決めたURLとintegrityで読む" \
  "$(loads "$mermaid" 'sha512-6a80OTZVmEJhqYJUmYd5z8yHUCDlYnj6q9XwB/gKOEyNQV/Q8u+XeSG59a2ZKFEHGTYzgfOQKYEBtrZV7vBr+Q==')" "1"

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件のテストが失敗しました\n' "$failures"
  exit 1
fi
