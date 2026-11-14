#!/bin/bash
# docs-overviewのview.sh(home/dot_claude/skills/docs-overview/scripts)を、使い捨ての概観で試す。ブラウザでの
# 動き(図の描画、CSPでスクリプトが止まるか)は確かめない
# テストの入力にMarkdownのバッククォートを、期待する値にCSPの'を書く
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
view="$root/home/dot_claude/skills/docs-overview/scripts/view.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }
count() { grep -o -- "$1" | wc -l | tr -d ' '; }
# <pre id="md">の中身を取り出し、3文字を戻す。&amp;は最後に戻す(先に戻すと、&amp;lt;が<になる)
body_of() {
  local s=${1#*'<pre id="md">'}
  printf '%s' "${s%%'</pre>'*}" | sed -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'
}
title_of() { local s=${1#*<title>}; printf '%s' "${s%%</title>*}"; }
# 終了コード2で、標準出力が空で、標準エラーに理由を出す
rejects() {
  local name=$1; shift
  bash "$view" "$@" >stdout.txt 2>stderr.txt </dev/null
  local code=$?
  equals "$name" "$code $(wc -c <stdout.txt | tr -d ' ') $([ -s stderr.txt ] && echo stderr)" "2 0 stderr"
}

cd "$work" || exit 1
fence='```'

rejects "引数が無ければ、終了コード2で止まる"
printf '# a\n' > a.md
rejects "引数が2つなら、終了コード2で止まる" a.md a.md
rejects "無いファイルは、終了コード2で止まる" no-such.md
mkdir -p a-dir
rejects "ディレクトリは、終了コード2で止まる" a-dir

# 入力の&amp;と&lt;は、戻した後もそのまま残る(エスケープの順を間違えると、<や&に化ける)
cat > round.md <<EOF
# 概観 & <計画>

A & B < C > D。&amp;と&lt;はそのまま書く。

</pre><p>外に出る</p>
</script><script>alert(1)</script>
<SCRIPT src=x></SCRIPT>

\`<b>\`と\`\`a\`b\`\`を使う。


${fence}mermaid
flowchart LR
  A["<入力>"] --> B{判定 & 分岐}
${fence}
末尾の行
EOF
out="$(bash "$view" round.md </dev/null)"
code=$?
equals "本文を取り出して戻すと、入力と同じになる" "$code $(body_of "$out")" "0 $(cat round.md)"
equals "生の</pre>は、本文を閉じる1つだけ" "$(printf '%s' "$out" | count '</pre>')" "1"
equals "<scriptで始まるタグは、外部の2つとインラインの1つだけ" "$(printf '%s' "$out" | grep -io '<script' | wc -l | tr -d ' ')" "3"
equals "初めの表示は、未実行の検査" \
  "$(printf '%s' "$out" | grep -c -F '<p id="status">Mermaidの検査: 未実行(スクリプトが読み込めないときは、下にMarkdownのまま表示します)</p>')" "1"
equals "外部のスタイルシートやフォントを読まない" "$(printf '%s' "$out" | grep -ciE '<link|@import|url\(')" "0"

equals "題は最初の「# 」の行の見出しで、エスケープする" "$(title_of "$out")" "概観 &amp; &lt;計画&gt;"
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

out="$(printf 'STDIN-MARK\n' | bash "$view" a.md)"
equals "標準入力は読まない" "$(printf '%s' "$out" | count 'STDIN-MARK')" "0"

out="$(bash "$view" round.md </dev/null)"
s=${out#*<script>}
inline=${s%%</script>*}
hash="$(printf '%s' "$inline" | openssl dgst -sha256 -binary | openssl base64 -A)"
marked='https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js'
mermaid='https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js'
csp="$(printf '%s' "$out" | grep -o 'http-equiv="Content-Security-Policy" content="[^"]*"')"
want="http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'sha256-$hash' $marked $mermaid; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'\""
equals "CSPのsha256-の値は、インラインのスクリプトのハッシュと同じ" "$csp" "$want"
equals "インラインのスクリプトは1つだけ" "$(printf '%s' "$out" | count '<script>')" "1"
script_src="$(printf '%s' "$csp" | grep -o 'script-src[^;]*')"
equals "script-srcに'unsafe-inline'が無い" "$(printf '%s' "$script_src" | count "'unsafe-inline'")" "0"
loads() { printf '%s' "$out" | grep -c -F "<script src=\"$1\" integrity=\"$2\" crossorigin=\"anonymous\"></script>"; }
equals "markedを、決めたURLとintegrityで読む" \
  "$(loads "$marked" 'sha512-xeUh+KxNyTufZOje++oQHstlMQ8/rpyzPuM+gjMFYK3z5ILJGE7l2NvYL+XfliKURMpBIKKp1XoPN/qswlSMFA==')" "1"
equals "mermaidを、決めたURLとintegrityで読む" \
  "$(loads "$mermaid" 'sha512-6a80OTZVmEJhqYJUmYd5z8yHUCDlYnj6q9XwB/gKOEyNQV/Q8u+XeSG59a2ZKFEHGTYzgfOQKYEBtrZV7vBr+Q==')" "1"

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件のテストが失敗しました\n' "$failures"
  exit 1
fi
