#!/bin/bash
# docs-redesignのlost.shとoutline.sh(home/dot_claude/skills/docs-redesign/scripts)を、使い捨ての文書で試す
# テストの入力にMarkdownのバッククォートを書く
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lost="$root/home/dot_claude/skills/docs-redesign/scripts/lost.sh"
outline="$root/home/dot_claude/skills/docs-redesign/scripts/outline.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }

cd "$work" || exit 1
fence='```'
cat > before.md <<EOF
# tool

\`tool init\`で始める。設定は\`~/.config/tool.toml\`に置く。[入れ方](docs/install.md#linux)と https://example.com/api を読む。

${fence}bash
tool init --force
    tool run   --jobs 4
}
${fence}

もう一度\`tool init\`を実行する。
EOF

# 記述を、別のファイル、インラインコード、字下げの違う行へ移す
cat > after.md <<EOF
# tool

始めるには次を実行する。詳しくは[入れ方](docs/install.md#linux)と https://example.com/api にある。

${fence}bash
tool init
tool run --jobs 4
${fence}
EOF
cat > after-guide.md <<EOF
設定は\`~/.config/tool.toml\`に置く。作り直すときは\`tool init --force\`を使う。
EOF

out="$(bash "$lost" before.md -- after.md after-guide.md)"
equals "別のファイルや別の書き方へ移した記述は挙げない" "$? $out" "0 "

# コードの行、インラインコード、リンク先、URLを1つずつ落とす
cat > after.md <<EOF
# tool

\`tool init\`で始める。

${fence}bash
tool run --jobs 4
${fence}
EOF
want="$(printf '1 span\tbefore.md:3\t~/.config/tool.toml\nlink\tbefore.md:3\tdocs/install.md#linux\nurl\tbefore.md:3\thttps://example.com/api\ncode\tbefore.md:6\ttool init --force')"
out="$(bash "$lost" before.md -- after.md)"
equals "落とした記述を、種類と元の場所を付けて1回ずつ挙げる" "$? $out" "$want"

# 行は無いが語はすべて残っている例と、語ごと消えた例
cat > before-words.md <<EOF
${fence}bash
tool build --target linux --release
tool deploy --region tokyo
${fence}
EOF
cat > after-words.md <<EOF
${fence}bash
tool build --release --target linux
${fence}
EOF
want="$(printf '1 line\tbefore-words.md:2\ttool build --target linux --release\ncode\tbefore-words.md:3\ttool deploy --region tokyo')"
out="$(bash "$lost" before-words.md -- after-words.md)"
equals "語がすべて残っているコードの行はlineに、語が消えた行はcodeにする" "$? $out" "$want"

# 1つ目のファイルはフェンスを閉じずに終わる。2つ目は~~~のフェンスで、中の行を落とす
printf '%s\n' "${fence}bash" 'tool start' > before-open.md
printf '%s\n' '~~~bash' 'tool deploy --region tokyo' '~~~' > before-tilde.md
printf '%s\n' "${fence}bash" 'tool start' "$fence" > after-fence.md
want="$(printf '1 code\tbefore-tilde.md:2\ttool deploy --region tokyo')"
out="$(bash "$lost" before-open.md before-tilde.md -- after-fence.md)"
equals "フェンスの状態と行番号は、ファイルごとに数え直す。~~~もフェンスとして読む" "$? $out" "$want"

# バッククォート4つのフェンスの中に、3つのフェンスを書いた例。外のフェンスが閉じた後は地の文に戻る
printf '%s\n' "${fence}\`markdown" "${fence}bash" 'tool deploy --prod' "$fence" "${fence}\`" '' '`tool after`を使う。' > before-nested.md
want="$(printf '1 code\tbefore-nested.md:3\ttool deploy --prod\nspan\tbefore-nested.md:7\ttool after')"
out="$(bash "$lost" before-nested.md -- after-fence.md)"
equals "フェンスの中のフェンスで、状態がずれない" "$? $out" "$want"

# 2行目は情報文字列があり、4行目は記号が違い、6行目は4つ字下げしている(箇条書きの中のコードブロックを、
# 例として書いたもの)。どれも外のフェンスを閉じない。8行目は、開いた行より長いフェンスで閉じる
printf '%s\n' "$fence" "${fence}bash" 'tool inner' '~~~' 'tool tilde' "    $fence" 'tool deep' "${fence}\`" '`tool after`を使う。' > before-deep.md
want="$(printf '1 code\tbefore-deep.md:3\ttool inner\ncode\tbefore-deep.md:5\ttool tilde\ncode\tbefore-deep.md:7\ttool deep\nspan\tbefore-deep.md:9\ttool after')"
out="$(bash "$lost" before-deep.md -- after-fence.md)"
equals "情報文字列のある行、違う記号の行、深く字下げした行では、フェンスを閉じない" "$? $out" "$want"

# 3行目は、開いた行より2つ深く字下げしたフェンスで閉じる
printf '%s\n' "$fence" 'tool start' "  $fence" '' "$fence" 'tool deploy --prod' "$fence" > before-shallow.md
want="$(printf '1 code\tbefore-shallow.md:6\ttool deploy --prod')"
out="$(bash "$lost" before-shallow.md -- after-fence.md)"
equals "開いた行より3つまで深く字下げしたフェンスで閉じる" "$? $out" "$want"

# 1行目はバッククォート2つで始まるが、フェンスではない。5行目のフェンスは、箇条書きの中で字下げしていて、
# 同じ字下げの7行目で閉じる
printf '%s\n' '``tool start``と書く。' '' '1. 入れる。' '' "      ${fence}bash" '      tool install --global' "      $fence" '`tool start`で始める。' > before-list.md
want="$(printf '1 code\tbefore-list.md:6\ttool install --global')"
out="$(bash "$lost" before-list.md -- after-fence.md)"
equals "字下げしたフェンスを読み、バッククォート2つの行をフェンスにしない" "$? $out" "$want"

# 1行目と5行目のフェンスは、箇条書きの記号と同じ行で開く。閉じる行(3行目、7行目)がフェンスを開くと、
# その先の地の文とコードブロックが入れ替わる。フェンスの中の箇条書きの行(11行目)は、フェンスを閉じない(閉じると、12行目が地の文になる)
printf '%s\n' "- ${fence}bash" '  tool one' "  $fence" '' "1. ${fence}sh" '   tool two' "   $fence" '`tool prose`を使う。' "$fence" 'tool three' "- $fence" 'tool four' "$fence" > before-marker.md
want="$(printf '1 code\tbefore-marker.md:2\ttool one\ncode\tbefore-marker.md:6\ttool two\nspan\tbefore-marker.md:8\ttool prose\ncode\tbefore-marker.md:10\ttool three\ncode\tbefore-marker.md:12\ttool four')"
out="$(bash "$lost" before-marker.md -- after-fence.md)"
equals "箇条書きの記号と同じ行で開くフェンスを読む" "$? $out" "$want"

# 1行目は、バッククォート3つで囲んだインラインコードで始まる段落。フェンスを開かない
printf '%s\n' "${fence}js${fence}は言語の名前。" '' "$fence" 'tool deploy --prod' "$fence" > before-inline3.md
want="$(printf '1 span\tbefore-inline3.md:1\tjs\ncode\tbefore-inline3.md:4\ttool deploy --prod')"
out="$(bash "$lost" before-inline3.md -- after-fence.md)"
equals "行頭のバッククォート3つのインラインコードを、フェンスにしない" "$? $out" "$want"
# 記号の種類(*、1)、入れ子の-)と、閉じる行を記号の後ろより深く字下げした例。記号の幅を字下げに足さないと、
# 閉じる行がフェンスを閉じず、次のフェンスと読み方が入れ替わる
printf '%s\n' "* ${fence}sh" '    tool asterisk' "    $fence" '' "$fence" 'tool bare one' "$fence" '' "1) ${fence}sh" '   tool paren' "   $fence" '' "$fence" 'tool bare two' "$fence" '' '- item' "  - ${fence}sh" '    tool nested' "    $fence" '' "$fence" 'tool bare three' "$fence" > before-marker2.md
want="$(printf '1 code\tbefore-marker2.md:2\ttool asterisk\ncode\tbefore-marker2.md:6\ttool bare one\ncode\tbefore-marker2.md:10\ttool paren\ncode\tbefore-marker2.md:14\ttool bare two\ncode\tbefore-marker2.md:19\ttool nested\ncode\tbefore-marker2.md:23\ttool bare three')"
out="$(bash "$lost" before-marker2.md -- after-fence.md)"
equals "箇条書きの記号の種類と幅を読み、閉じる行の字下げを記号の後ろから数える" "$? $out" "$want"

# 箇条書きの記号と同じ行で開いたフェンスは、記号の幅より浅い3行目で、箇条書きと一緒に終わる。3行目は
# 新しいフェンスを開く。8行目はバッククォート2つで始まるが、フェンスではない
printf '%s\n' "- ${fence}sh" '  tool one' "$fence" 'tool two --prod' "$fence" '' '`tool three`を使う。' '``で始まる行。' "$fence" 'tool four' "$fence" > before-shallow-marker.md
want="$(printf '1 code\tbefore-shallow-marker.md:2\ttool one\ncode\tbefore-shallow-marker.md:4\ttool two --prod\nspan\tbefore-shallow-marker.md:7\ttool three\npart\tbefore-shallow-marker.md:8\tで始まる行。\ncode\tbefore-shallow-marker.md:10\ttool four')"
out="$(bash "$lost" before-shallow-marker.md -- after-fence.md)"
equals "箇条書きの中のフェンスは、記号の幅より浅い行で終わる" "$? $out" "$want"

# 3行目は、記号の後ろより2つ深く字下げして閉じる。4行目は、同じ項目の続きの地の文。8行目は、フェンスの中の
# 空行で、フェンスを終わらせない。10行目は、次の項目で、前のフェンスを終わらせて新しいフェンスを開く
printf '%s\n' "* ${fence}sh" '    tool alpha' "    $fence" '  `tool bravo`を使う。' '' "- ${fence}sh" '  tool charlie' '' '  tool delta' "- ${fence}sh" '  tool echo' "  $fence" > before-marker3.md
want="$(printf '1 code\tbefore-marker3.md:2\ttool alpha\nspan\tbefore-marker3.md:4\ttool bravo\ncode\tbefore-marker3.md:7\ttool charlie\ncode\tbefore-marker3.md:9\ttool delta\ncode\tbefore-marker3.md:11\ttool echo')"
out="$(bash "$lost" before-marker3.md -- after-fence.md)"
equals "箇条書きのフェンスの後の続きの行、中の空行、次の項目のフェンスを読む" "$? $out" "$want"

# 地の文だけを残した後の版。閉じない`の並びがある行の、地の文の切れ端が挙がらないようにする
printf '%s\n' '次のように と を使う。' 'Use or to clean.' '記号の と と``と を書く。' '`x`と`y`を使う。' > after-prose.md

# バッククォート2つで囲んだインラインコードは、中に`を書ける。同じ行の後ろのインラインコードも読む
# 3行目は、1つの`で囲んだ中に、2つの`の並びを書いている
printf '%s\n' '``a`b``と`tool x`を使う。' '``tool y``と`` tool z ``を使う。`tool w`も使う。' '`x``y`を使う。' > before-double.md
want="$(printf '1 span\tbefore-double.md:1\ta`b\nspan\tbefore-double.md:1\ttool x\nspan\tbefore-double.md:2\ttool y\nspan\tbefore-double.md:2\ttool z\nspan\tbefore-double.md:2\ttool w\nspan\tbefore-double.md:3\tx``y')"
out="$(bash "$lost" before-double.md -- after-prose.md)"
equals "バッククォートの並びは、同じ数の並びで閉じる" "$? $out" "$want"

# 1〜2行目は、インラインコードが行の折り返しをまたぐ。つないでは読まず、行ごとの切れ端をpartとして挙げる。
# 2行目は、最初の`が前の行の続きを閉じるので、2つ目の`から対にする読み方でtool gcを読む
printf '%s\n' '次のように`tool run' '--jobs 4`と`tool gc`を使う。' > before-wrap.md
want="$(printf '1 part\tbefore-wrap.md:1\ttool run\npart\tbefore-wrap.md:2\t--jobs 4\npart\tbefore-wrap.md:2\ttool gc')"
out="$(bash "$lost" before-wrap.md -- after-prose.md)"
equals "折り返したインラインコードは、行ごとの切れ端を挙げる" "$? $out" "$want"

printf '%s\n' '次のように`tool run --jobs 4`と`tool gc`を使う。' > after-unwrap.md
out="$(bash "$lost" before-wrap.md -- before-wrap.md)"
equals "折り返したまま残せば、挙げない" "$? $out" "0 "
out="$(bash "$lost" before-wrap.md -- after-unwrap.md)"
equals "折り返しをやめても、挙げない" "$? $out" "0 "

# 2行目は、閉じた後にまた開いて折り返す。`の並びがすべて対になるので、切れ端を調べない(--jobs 4とtool gcは見ない)。
# 5〜7行目は3行にまたがる。`の無い6行目は見ない
printf '%s\n' 'Use `tool run' '--jobs 4` or `tool gc' '--all` to clean.' '' '`tool a' 'b c' 'd`を使う。' > before-chain.md
want="$(printf '1 part\tbefore-chain.md:1\ttool run\npart\tbefore-chain.md:3\t--all\npart\tbefore-chain.md:5\ttool a\npart\tbefore-chain.md:7\td')"
out="$(bash "$lost" before-chain.md -- after-prose.md)"
equals "続けて折り返すインラインコードは、端の行の切れ端だけを挙げる" "$? $out" "$want"

out="$(bash "$lost" before-chain.md -- before-chain.md)"
equals "同じ文書を前と後に渡すと、切れ端も挙げない" "$? $out" "0 "

# 記号として書いた`は、次の行にも、次のファイルにも響かない。2つ目のファイルの4行目と5行目は、閉じない``の
# 後ろにインラインコードがある
printf '%s\n' '記号の`を書く。' > before-stray-1.md
printf '%s\n' '`tool one`と`tool two`を使う。' '記号の`を書く。' '`tool xx`と`tool yy`を使う。' '記号の``と`tool v`を書く。' '`tool u`と``と`tool w`を書く。' > before-stray-2.md
want="$(printf '1 span\tbefore-stray-2.md:1\ttool one\nspan\tbefore-stray-2.md:1\ttool two\nspan\tbefore-stray-2.md:3\ttool xx\nspan\tbefore-stray-2.md:3\ttool yy\npart\tbefore-stray-2.md:4\ttool v\npart\tbefore-stray-2.md:5\ttool u\npart\tbefore-stray-2.md:5\ttool w')"
out="$(bash "$lost" before-stray-1.md before-stray-2.md -- after-prose.md)"
equals "記号として書いたバッククォートは、ほかの行のインラインコードに響かない" "$? $out" "$want"

want="$(printf '1 part\tbefore-stray-1.md:1\t記号の\npart\tbefore-stray-1.md:1\tを書く。')"
out="$(bash "$lost" before-stray-1.md -- after-fence.md)"
equals "記号として書いたバッククォートの前後の地の文も、無ければpartとして挙げる" "$? $out" "$want"

# 1行目の記述は、後の版では、前か後ろに英数字、_、-が続く別の語の一部になっている
# 2行目の記述は、後ろに.、:、/と英数字が続く。3行目は、文の終わりの.、行の番号でない:、末尾の/の前にある
printf '%s\n' '`-f`を付ける。`PORT`と`HOME`と`--yes`と`PATH`と`-version`と`DIR`と`8080`と`--jobs 4`を設定する。`tool start`で始める。' '`.env`と`npm run build`と[API](https://example.com/api)。' '`README.md`と`localhost`と`docs`を見る。' > before-part.md
printf '%s\n' '`--force`を付ける。`PORTS`と`XHOME`と`--yes-all`と`PATH_INFO`と`--version`と`TMP_DIR`と`18080`と`--jobs 42`を見る。`sudo tool start --now`で始める。' '`.env.example`と`npm run build:prod`と[API](https://example.com/api/v2)。' 'See README.md. Open localhost: it works. The docs/ directory.' > after-part.md
want="$(printf '1 span\tbefore-part.md:1\t-f\nspan\tbefore-part.md:1\tPORT\nspan\tbefore-part.md:1\tHOME\nspan\tbefore-part.md:1\t--yes\nspan\tbefore-part.md:1\tPATH\nspan\tbefore-part.md:1\t-version\nspan\tbefore-part.md:1\tDIR\nspan\tbefore-part.md:1\t8080\nspan\tbefore-part.md:1\t--jobs 4\nspan\tbefore-part.md:2\t.env\nspan\tbefore-part.md:2\tnpm run build\nlink\tbefore-part.md:2\thttps://example.com/api')"
out="$(bash "$lost" before-part.md -- after-part.md)"
equals "別の語の一部になっている一致は、残っているとみなさない" "$? $out" "$want"

# 後の版の同じ行に、別の語の一部の一致(--forceの-f)と、そうでない一致がある。空白とタブの数の違いは無視する
printf '%s\n' '`-f`を付ける。`tool	run  --all`を使う。' > before-same.md
printf '%s\n' '`--force -f`と`tool run --all`' > after-same.md
out="$(bash "$lost" before-same.md -- after-same.md)"
equals "同じ行の後ろにある一致と、空白の数だけ違う記述は、残っているとみなす" "$? $out" "0 "

# URLの末尾の記号は、URLに含めない。<>、""、``、[]で囲んだURLも、中だけを読む。ASCIIでない文字はURLに
# 含める。2行目は、パスに日本語を含むURLで、後の版には同じ前半の別のURLがある。5行目は、URLの直後に空白を
# 置かずに日本語を続けたので、2つ目のURLまでを1つのURLとして読む
printf '%s\n' 'See https://a.example/docs. Or https://b.example/x, **https://c.example/y**.' '用語は https://d.example/wiki/日本 を見る。' '<https://e.example/z>と<a href="https://f.example/w">と`https://g.example/v`と[https://h.example/u]' '消すのは https://lost.example/p です。' '公式はhttps://i.example/docsと、ミラーはhttps://j.example/mirrorにある。' > before-url.md
printf '%s\n' 'https://a.example/docs https://b.example/x https://c.example/y https://d.example/wiki/東京 https://e.example/z https://f.example/w https://g.example/v https://h.example/u' '公式はhttps://i.example/docs にある。' > after-url.md
want="$(printf '1 url\tbefore-url.md:2\thttps://d.example/wiki/日本\nurl\tbefore-url.md:4\thttps://lost.example/p\nurl\tbefore-url.md:5\thttps://i.example/docsと、ミラーはhttps://j.example/mirrorにある。')"
out="$(bash "$lost" before-url.md -- after-url.md)"
equals "URLの末尾の記号を除いて比べ、ASCIIでない文字はURLに含める" "$? $out" "$want"

# 記号だけのインラインコードとリンク先も調べる。空のインラインコード、記号だけのコードの行(3〜4行目)、
# 記号だけの切れ端(7行目の-)は挙げない
printf '%s\n' '区切りは`:`、ルートは`/`、親は`..`、空は` `。ファイル名の前に`--`を書く。[先頭へ](#)と[上へ](../)。' "$fence" '}' '---' "$fence" '' '- `tool keep' > before-punct.md
printf '%s\n' 'ルートは`/usr`、親は`../lib`。`--force`と`a:b`と[別](#top)と[下](../x)。`tool keep`' > after-punct.md
want="$(printf '1 span\tbefore-punct.md:1\t:\nspan\tbefore-punct.md:1\t/\nspan\tbefore-punct.md:1\t..\nspan\tbefore-punct.md:1\t--\nlink\tbefore-punct.md:1\t#\nlink\tbefore-punct.md:1\t../')"
out="$(bash "$lost" before-punct.md -- after-punct.md)"
equals "記号だけのインラインコードとリンク先も、無ければ挙げる" "$? $out" "$want"
out="$(bash "$lost" before-punct.md -- before-punct.md)"
equals "記号だけの記述も、同じファイルと比べれば挙げない" "$? $out" "0 "
# 閉じない`の並びがある行でも、記号だけのインラインコードは調べる。記号だけの切れ端(1行目の行頭の- と、2行目の
# 末尾の.)は挙げない。3行目の記号だけのリンク先は、前の行の切れ端と関係なく挙げる
printf '%s\n' '- `/`と`--`。記号の`を書く。' '`/x`と`.' '[先頭へ](#)' > before-punct-part.md
printf '%s\n' 'と。記号のを書く。' > after-punct-part.md
want="$(printf '1 part\tbefore-punct-part.md:1\t/\npart\tbefore-punct-part.md:1\t--\npart\tbefore-punct-part.md:2\t/x\nlink\tbefore-punct-part.md:3\t#')"
out="$(bash "$lost" before-punct-part.md -- after-punct-part.md)"
equals "閉じない並びのある行でも、記号だけのインラインコードは挙げる" "$? $out" "$want"

# 非ASCIIの記号だけの行。gawkは、UTF-8のロケールで動かすと、この行を記号だけの行として飛ばす
printf '%s\n' "$fence" '→' "$fence" > before-arrow.md
want="$(printf '1 code\tbefore-arrow.md:2\t→')"
out="$(LC_ALL=C.UTF-8 bash "$lost" before-arrow.md -- after-fence.md 2>/dev/null)"
equals "非ASCIIの記号だけの行は、ロケールに関係なく挙げる" "$? $out" "$want"

printf '%s\n' '[入れ方][i]と<a href="docs/setup.html">設定</a>を読む[^1]。' '' '[i]: docs/install.md' '[^1]: 脚注の文' > before-ref.md
want="$(printf '1 link\tbefore-ref.md:1\tdocs/setup.html\nlink\tbefore-ref.md:3\tdocs/install.md')"
out="$(bash "$lost" before-ref.md -- after-fence.md)"
equals "hrefと、参照形式のリンクの定義も、リンク先として挙げる" "$? $out" "$want"

# 後の1つ目のファイルは改行で終わらない。2つ目の1行目とつなげると、消した行が残っているように見える
printf '%s\n' "${fence}bash" 'tool --flagzzz' "$fence" > 'name=1.md'
printf 'tool' > after-noeol.md
printf ' --flagzzz\n' > after-next.md
want="$(printf '1 line\t./name=1.md:2\ttool --flagzzz')"
out="$(bash "$lost" 'name=1.md' -- after-noeol.md after-next.md </dev/null)"
equals "名前に=があるファイルも読み、後のファイルどうしをつなげない" "$? $out" "$want"

mkdir -p 'tmp\tdir'
out="$(TMPDIR="$work/tmp\\tdir" bash "$lost" before.md -- before.md 2>&1)"
equals "一時ファイルのパスに\\があっても、後のファイルを読める" "$? $out" "0 "

printf '%s\n' '`tool gone`を使う。' '' 'もう一度`tool gone`を使う。' > before-twice.md
want="$(printf '1 span\tbefore-twice.md:1\ttool gone')"
out="$(bash "$lost" before-twice.md -- after-fence.md)"
equals "同じ記述が2回あっても、最初の場所で1回だけ挙げる" "$? $out" "$want"

# 後のファイルの2行にまたがる文字列は、残っているとみなさない。2文字の語は、codeとlineの判定に使わない
printf '%s\n' '`toolinit`を使う。' "${fence}bash" 'ls -la /etc' 'toolinit ls' "$fence" > before-match.md
printf '%s\n' 'tool' 'init' 'ls etc' > after-match.md
want="$(printf '1 span\tbefore-match.md:1\ttoolinit\nline\tbefore-match.md:3\tls -la /etc\ncode\tbefore-match.md:4\ttoolinit ls')"
out="$(bash "$lost" before-match.md -- after-match.md)"
equals "行をまたぐ一致は数えず、3文字に満たない語は見ない" "$? $out" "$want"

printf '%s\n' "${fence}bash" 'cd ..' "$fence" > before-short.md
want="$(printf '1 code\tbefore-short.md:2\tcd ..')"
out="$(bash "$lost" before-short.md -- after-match.md)"
equals "3文字以上の語が1つも無い行は、lineにしない" "$? $out" "$want"

# 閉じるフェンスの後の行は、地の文として読む(CRを除かないと、フェンスが閉じない)
printf '%s\r\n' "${fence}bash" 'tool run --jobs 4' "$fence" '`tool init`を使う。' > before-crlf.md
out="$(bash "$lost" before-crlf.md -- after.md)"
equals "改行がCRLFの行も、LFの行と同じとみなす" "$? $out" "0 "

: > empty.md
out="$(bash "$lost" empty.md before.md -- after.md | wc -l)"
equals "前のファイルに空のファイルがあっても、次のファイルを読む" "$out" "4"

bash "$lost" before.md >/dev/null 2>&1
equals "--が無ければ、終了コード2で止まる" "$?" "2"
bash "$lost" before.md -- >/dev/null 2>&1
equals "後のファイルが無ければ、終了コード2で止まる" "$?" "2"
bash "$lost" before.md -- no-such.md >/dev/null 2>&1
equals "読めないファイルがあれば、終了コード2で止まる" "$?" "2"
mkdir -p a-dir
bash "$lost" a-dir -- after.md >/dev/null 2>&1
equals "前のファイルにディレクトリを渡すと、終了コード2で止まる" "$?" "2"
bash "$lost" -- after.md >/dev/null 2>&1 </dev/null
equals "前のファイルが無ければ、終了コード2で止まる" "$?" "2"
# -という名前のファイルを置く。awkにそのまま渡すと、ファイルではなく標準入力を読む
printf '%s\n' '`tool gone`を使う。' > ./-
want="$(printf '1 span\t./-:1\ttool gone')"
out="$(bash "$lost" - -- after-fence.md </dev/null)"
equals "前のファイルの-は、標準入力ではなくファイルとして読む" "$? $out" "$want"
out="$(bash "$lost" before-twice.md -- - </dev/null)"
equals "後のファイルの-も、標準入力ではなくファイルとして読む" "$? $out" "0 "

# outline.sh。lost.shと同じフェンスの読み方で、中の#を拾わない。2〜6行目は、バッククォート4つのフェンスの中に
# 3つのフェンスがある。8〜13行目は、~~~のフェンスの中に、バッククォートのフェンスの行と、後ろに文字が続く
# ~~~の行がある。15〜17行目は、長いフェンスで閉じる。20行目は、4つ深く字下げしたフェンスの行で、外の
# フェンスを閉じない。24〜35行目は、箇条書きの記号と同じ行で開くフェンス(-、*、1))で、26行目は
# フェンスを終わらせない空行。38行目は、記号の幅より浅い行で、箇条書きのフェンスを終わらせる見出し。39行目は、
# バッククォート3つのインラインコードで始まる段落。43行目は、次の項目で、前のフェンスを終わらせて新しい
# フェンスを開く。48行目は、フェンスの中の箇条書きの行で、フェンスを閉じない
printf '%s\n' '# title' "$fence\`markdown" "${fence}sh" '# c1' "$fence" "$fence\`" '## section' '~~~' "$fence" '# c2' '~~~sh' '# c3' '~~~' '### sub' "$fence" '# c4' "$fence\`" '#### long' "$fence" "    $fence" '# c5' "$fence" '##### deep' "- ${fence}sh" '  # c6' '' "  $fence" '###### dash' "* ${fence}sh" '    # c7' "    $fence" '# asterisk' "1) ${fence}sh" '   # c8' "   $fence" '# paren' "- ${fence}sh" '# shallow' "${fence}js${fence} is inline." '# inline' "- ${fence}sh" '  x' "- ${fence}sh" '  y' "  $fence" '# reread' "$fence" "- $fence" '# c9' "$fence" '# marker in fence' > outline.md
printf '%s\n' "$fence" '# open at the end' > outline-open.md
printf '%s\r\n' '# crlf' "${fence}sh" '# c8' "$fence" '## crlf2' > outline-crlf.md
printf '%s\n' '# named' > 'x=1.md'
want="$(printf '0 outline.md:1: # title\noutline.md:7: ## section\noutline.md:14: ### sub\noutline.md:18: #### long\noutline.md:23: ##### deep\noutline.md:28: ###### dash\noutline.md:32: # asterisk\noutline.md:36: # paren\noutline.md:38: # shallow\noutline.md:40: # inline\noutline.md:46: # reread\noutline.md:51: # marker in fence\noutline-crlf.md:1: # crlf\noutline-crlf.md:5: ## crlf2\n./x=1.md:1: # named')"
out="$(bash "$outline" outline.md outline-open.md outline-crlf.md x=1.md | tr -d '\r')"
equals "見出しの一覧は、フェンスの中の#を拾わない。フェンスの状態は、ファイルごとに数え直す" "$? $out" "$want"
bash "$outline" >/dev/null 2>&1 </dev/null
equals "見出しの一覧は、ファイルが無ければ終了コード2で止まる" "$?" "2"
bash "$outline" a-dir >/dev/null 2>&1 </dev/null
equals "見出しの一覧は、ディレクトリを渡すと終了コード2で止まる" "$?" "2"


if [ "$failures" -gt 0 ]; then
  printf '\n%s 件のテストが失敗しました\n' "$failures"
  exit 1
fi
