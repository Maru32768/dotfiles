#!/bin/bash
# docs-redesignのlost.sh(home/dot_claude/skills/docs-redesign/scripts)を、使い捨ての文書で試す
# テストの入力にMarkdownのバッククォートを書く
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
lost="$root/home/dot_claude/skills/docs-redesign/scripts/lost.sh"
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

printf '%s\n' '`tool gone`を使う。' '' 'もう一度`tool gone`を使う。' > before-twice.md
want="$(printf '1 span\tbefore-twice.md:1\ttool gone')"
out="$(bash "$lost" before-twice.md -- after-fence.md)"
equals "同じ記述が2回あっても、最初の場所で1回だけ挙げる" "$? $out" "$want"

# 後のファイルの2行にまたがる文字列は、残っているとみなさない。2文字の語は、codeとlineの判定に使わない
printf '%s\n' '`toolinit`を使う。' "${fence}bash" 'ls -la /etc' "$fence" > before-match.md
printf '%s\n' 'tool' 'init' 'ls etc' > after-match.md
want="$(printf '1 span\tbefore-match.md:1\ttoolinit\nline\tbefore-match.md:3\tls -la /etc')"
out="$(bash "$lost" before-match.md -- after-match.md)"
equals "行をまたぐ一致は数えず、3文字に満たない語は見ない" "$? $out" "$want"

printf '%s\r\n' "${fence}bash" 'tool run --jobs 4' "$fence" > before-crlf.md
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

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件のテストが失敗しました\n' "$failures"
  exit 1
fi
