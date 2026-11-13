#!/bin/bash
# review-loopのevidence.sh(home/dot_claude/skills/review-loop/scripts)を、使い捨てのリポジトリで試す
# checkに渡す文字列の中で変数を展開するので、SC2016とSC2034を抑える
# shellcheck disable=SC2016,SC2034
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ev="$root/home/dot_claude/skills/review-loop/scripts/evidence.sh"
work="$(mktemp -d)"
# 落ちたときは、記録を調べられるよう作業ディレクトリを残す
trap '[ $? -eq 0 ] && rm -rf "$work" || printf "作業ディレクトリを残した: %s\n" "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }

repo="$work/repo"
g() { git -C "$repo" "$@"; }
git init -q -b main "$repo"
g config user.name test
g config user.email test@example.com
mkdir -p "$repo/sub"
printf 'add() { echo $(($1 + $2)); }\nmul() { echo $(($1 * $2)); }\n' > "$repo/app.sh"
printf 'cd "$(dirname "$0")" && . ./app.sh\n[ "$(add 2 3)" = 5 ]\n' > "$repo/test.sh"
printf 'here\n' > "$repo/sub/here.txt"
printf 'build/\n*.log\n' > "$repo/.gitignore"
g add -A && g commit -q -m base

# $1の記録を使い、作業ツリーのトップでevidence.shを動かす
e() { (cd "$repo" && bash "$ev" "$@"); }
# $1の列の、記録$2の最後の行の値
last() { tail -n 1 "$2" | cut -f "$1"; }
# 今の作業ツリーの指紋。runが記録する指紋を、別の記録から読む
fp() { e "$work/fp.tsv" run probe -- true >/dev/null 2>&1 && last 5 "$work/fp.tsv"; }

# --- run ---
log="$work/no/such/dir/evidence.tsv"
e "$log" run ok -- true
rc=$?
check "記録のファイルの親ディレクトリが無くても作る" '[ -f "$log" ]'
equals "成功するコマンドは終了コード0で、結果0の行を残す" "$rc $(last 2-4 "$log")" "0 run	ok	0"
e "$log" run bad -- sh -c 'exit 7'
rc=$?
equals "失敗するコマンドの終了コードを、そのまま返して記録する" "$rc $(last 4 "$log")" "7 7"
e "$log" run quote -- sh -c 'printf "%s\n" "$1" > "$2"' _ 'a "b"  c' "$work/quote.out"
equals "空白と引用符を含む引数を、そのまま渡す" "$(cat "$work/quote.out")" 'a "b"  c'
tabnl=$(printf 'c\td\ne')
e "$log" run argv -- true 'a b' "$tabnl" ''
equals "記録したコマンドは、シェルで読み戻すと同じ引数になる" "$(eval "printf '[%s]' $(last 6 "$log")")" "$(printf '[%s]' true 'a b' "$tabnl" '')"
# evidence.shの関数と同じ名前の、PATHにあるコマンド
mkdir -p "$work/bin"
printf '#!/bin/sh\nexit 7\n' > "$work/bin/build"
chmod +x "$work/bin/build"
PATH="$work/bin:$PATH" e "$log" run build -- build
rc=$?
equals "evidence.shの関数と同じ名前のコマンドは、PATHのコマンドを回す" "$rc $(last 4 "$log")" "7 7"
lines=$(wc -l < "$log")
check "タブを含むラベルは、実行も記録もせずに拒否する" '! e "$log" run "a	b" -- touch "$work/tab-ran" && [ ! -e "$work/tab-ran" ] && [ "$(wc -l < "$log")" = "$lines" ]'
check "作業ツリーの中の、無視されていない記録は拒否する" '! e "$repo/evidence.tsv" run x -- true && [ ! -e "$repo/evidence.tsv" ]'
check "作業ツリーの中でも、無視された記録は使える" 'e "$repo/build/evidence.tsv" run x -- true'

# --- 指紋 ---
fp0=$(fp)
printf 'echo changed\n' >> "$repo/app.sh"
fp1=$(fp)
check "追跡しているファイルを変えると指紋が変わる" '[ "$fp1" != "$fp0" ]'
printf 'new\n' > "$repo/untracked.txt"
fp2=$(fp)
check "未追跡のファイルを足すと指紋が変わる" '[ "$fp2" != "$fp1" ]'
printf 'noise\n' > "$repo/ignored.log"
equals "無視されたファイルでは指紋が変わらない" "$(fp)" "$fp2"
status=$(g status --porcelain)
index=$(cksum < "$repo/.git/index")
e "$log" run touch -- true
equals "runは本物のindexを変えない" "$(cksum < "$repo/.git/index")" "$index"
equals "runはgit statusを変えない" "$(g status --porcelain)" "$status"
g add -A && g commit -q -m change
equals "同じ中身なら、コミットの後も指紋が同じ" "$(fp)" "$fp2"
equals "指紋はコミットのツリーと同じ" "$fp2" "$(g rev-parse 'HEAD^{tree}')"
printf 'echo tracked-but-ignored\n' > "$repo/kept.log"
g add -f kept.log && g commit -q -m kept
check "無視するパターンに当たっても、追跡しているファイルは指紋に入る" '[ "$(fp)" = "$(g rev-parse "HEAD^{tree}")" ]'

# --- check ---
clog="$work/check.tsv"
e "$clog" run lint -- true
equals "runの直後はOKで0" "$(e "$clog" check lint; echo "rc=$?")" "OK lint
rc=0"
printf 'x\n' >> "$repo/app.sh"
equals "ファイルを変えるとSTALEで1" "$(e "$clog" check lint; echo "rc=$?")" "STALE lint
rc=1"
g checkout -q -- app.sh
equals "中身を戻すとOKに戻る" "$(e "$clog" check lint; echo "rc=$?")" "OK lint
rc=0"
equals "行の無いラベルはMISSINGで1" "$(e "$clog" check lint nothere; echo "rc=$?")" "OK lint
MISSING nothere
rc=1"
e "$clog" run unit -- false
equals "最新の行が失敗ならFAILEDで1" "$(e "$clog" check unit; echo "rc=$?")" "FAILED unit
rc=1"
e "$clog" run unit -- true
equals "失敗の後に成功すれば、最新の行が勝ってOK" "$(e "$clog" check unit; echo "rc=$?")" "OK unit
rc=0"
nlog="$work/number.tsv"
e "$nlog" run 01 -- true
equals "数値に見えるラベルも、文字列として比べる" "$(e "$nlog" check 01 1 1.0; echo "rc=$?")" "OK 01
MISSING 1
MISSING 1.0
rc=1"

# --- table ---
tlog="$work/table.tsv"
e "$tlog" run old -- true
printf 'echo v2\n' >> "$repo/app.sh"
e "$tlog" run new -- true
e "$tlog" run lint -- sh -c 'false || exit 3'
equals "今の指紋の行だけを、パイプを逃がした表にする" "$(e "$tlog" table)" '| 検査 | 結果 | コマンド |
|---|---|---|
| new | 成功 | `true` |
| lint | 失敗(終了コード3) | `sh -c false\ \\|\\|\ exit\ 3` |'
g add -A && g commit -q -m v2

# --- mutate ---
# 変異のパッチは作業ツリーの外に置く。kill: テストが見る足し算を壊す。survive: テストが見ない掛け算を壊す。
# loop: 読み込んだだけで止まらなくなる。noapply: 当たらない
patch_of() {
  cp "$repo/app.sh" "$work/app.sh.orig"
  sed "$2" "$work/app.sh.orig" > "$repo/app.sh"
  g diff > "$work/$1.patch"
  g checkout -q -- app.sh
}
patch_of kill 's/\$1 + \$2/$1 - $2/'
patch_of survive 's/\$1 \* \$2/$1 + $2/'
patch_of loop '1i while :; do :; done'
sed 's/^-add/-nothing/' "$work/kill.patch" > "$work/noapply.patch"
mlog="$work/mutate.tsv"
count="$work/count"
fp0=$(fp)
same() { [ -z "$(g status --porcelain)" ] && [ "$(fp)" = "$fp0" ]; }
mutate() { e "$mlog" mutate "$work/$1.patch" -- sh -c 'echo run >> "$0"; sh test.sh' "$count"; }

mutate kill > /dev/null
rc=$?
equals "テストが落ちる変異はKilledで0" "$rc $(last 2-4 "$mlog")" "0 mutate	kill.patch	Killed"
check "Killedの後、作業ツリーがきれいで指紋も同じ" same
equals "初回は基準の実行と変異の実行で、2回回す" "$(wc -l < "$count")" "2"
check "基準の実行をbaselineとして記録する" 'grep -q "	run	baseline	0	$fp0	" "$mlog"'
mutate survive > /dev/null
rc=$?
equals "テストが気づかない変異はSurvivedで1" "$rc $(last 2-4 "$mlog")" "1 mutate	survive.patch	Survived"
check "Survivedの後、作業ツリーがきれいで指紋も同じ" same
equals "同じ指紋と同じコマンドの2回目は、基準の実行を省く" "$(wc -l < "$count")" "3"
rlog="$work/run-only.tsv"
e "$rlog" run same -- sh -c 'echo run >> "$0"; sh test.sh' "$count" > /dev/null
e "$rlog" mutate "$work/kill.patch" -- sh -c 'echo run >> "$0"; sh test.sh' "$count" > /dev/null
equals "同じコマンドのrunの行があっても、baselineの行が無ければ基準の実行を省かない" "$(wc -l < "$count")" "6"
mutate noapply > /dev/null 2>&1
rc=$?
equals "当たらないパッチはInvalidで4" "$rc $(last 2-4 "$mlog")" "4 mutate	noapply.patch	Invalid"
check "Invalidの後、作業ツリーがきれいで指紋も同じ" same
MUTATE_TIMEOUT=2 mutate loop > /dev/null 2>&1
rc=$?
equals "MUTATE_TIMEOUTを過ぎるとTimeoutで3" "$rc $(last 2-4 "$mlog")" "3 mutate	loop.patch	Timeout"
check "Timeoutの後、作業ツリーがきれいで指紋も同じ" same
equals "MUTATE_TIMEOUTが違えば、同じコマンドでも基準の実行をやり直す" "$(wc -l < "$count")" "8"

# 変異のときだけ、コマンドが$goのファイルを待つ。待っている間にTERMを送る
go="$work/go"
(cd "$repo" && exec bash "$ev" "$work/signal.tsv" mutate "$work/kill.patch" -- \
  sh -c 'if grep -q "1 - " app.sh; then : > "$0.started"; until [ -e "$0" ]; do sleep 0.1; done; fi; sh test.sh' "$go") > /dev/null 2>&1 &
pid=$!
for _ in $(seq 600); do [ -e "$go.started" ] && break; sleep 0.1; done
g diff --quiet
mutated=$?
kill -TERM "$pid"
: > "$go"
wait "$pid"
rc=$?
equals "変異の実行中にTERMを受けると、変異を戻してから130で終わる" "$mutated $rc" "1 130"
check "TERMで止めた後、作業ツリーがきれいで指紋も同じ" same
check "TERMで止めると、変異の結果を記録しない" '! grep -q "	mutate	" "$work/signal.tsv"'

e "$mlog" mutate "$work/kill.patch" -- sh -c 'cat app.sh >> "$0"; exit 1' "$work/seen" > /dev/null 2>&1
rc=$?
equals "基準の実行が失敗するとInvalidで4" "$rc $(last 2-4 "$mlog")" "4 mutate	kill.patch	Invalid"
equals "基準の実行が失敗すると、パッチを当てずに止まる" "$(cat "$work/seen")" "$(cat "$repo/app.sh")"
check "基準の実行が失敗した後、作業ツリーがきれいで指紋も同じ" same
lines=$(wc -l < "$mlog")
e "$mlog" mutate "$work/kill.patch" -- sh -c 'touch junk.txt; exit 1' > /dev/null 2>&1
rc=$?
check "基準の実行が失敗してファイルを残すと、5で終わり何も記録しない" '[ "$rc" = 5 ] && [ "$(wc -l < "$mlog")" = "$lines" ]'
rm -f "$repo/junk.txt"
MUTATE_BUILD='touch junk.txt; exit 1' e "$mlog" mutate "$work/kill.patch" -- sh test.sh > /dev/null 2>&1
rc=$?
check "基準の実行のビルドが失敗してファイルを残すと、5で終わり何も記録しない" '[ "$rc" = 5 ] && [ "$(wc -l < "$mlog")" = "$lines" ]'
rm -f "$repo/junk.txt"

# 変異だけがビルドに失敗するビルド
MUTATE_BUILD='! grep -q "1 - " app.sh' mutate kill > /dev/null 2>&1
rc=$?
equals "MUTATE_BUILDが失敗するとInvalidで4" "$rc $(last 2-4 "$mlog")" "4 mutate	kill.patch	Invalid"
check "ビルドの失敗の後、作業ツリーがきれいで指紋も同じ" same
equals "MUTATE_BUILDが違えば、同じコマンドでも基準の実行をやり直す" "$(wc -l < "$count")" "9"
# テストがビルドの成果物(無視されたbuild/)を読むとき、変異ごとにビルドし直してから回す
MUTATE_BUILD='mkdir -p build && cp app.sh build/app.sh' \
  e "$mlog" mutate "$work/kill.patch" -- sh -c '. build/app.sh; [ "$(add 2 3)" = 5 ]' > /dev/null 2>&1
equals "MUTATE_BUILDでビルドした変異をテストが検出する" "$(last 2-4 "$mlog")" "mutate	kill.patch	Killed"
check "戻した後にビルドし直し、成果物に変異を残さない" 'cmp -s "$repo/build/app.sh" "$repo/app.sh"'
PATH="$work/bin:$PATH" e "$mlog" mutate "$work/kill.patch" -- build > /dev/null 2>&1
rc=$?
equals "mutateも、evidence.shの関数と同じ名前のPATHのコマンドを回す" "$rc $(last 2-4 "$mlog")" "4 mutate	kill.patch	Invalid"
# 変異のときだけ、コマンドが$1の終了コードで終わる
exits() { e "$mlog" mutate "$work/kill.patch" -- sh -c 'grep -q "1 - " app.sh && exit "$0"; sh test.sh' "$1" > /dev/null 2>&1; echo "$? $(last 4 "$mlog")"; }
equals "変異の実行が126で終わる(コマンドを実行できない)とInvalidで4" "$(exits 126)" "4 Invalid"
equals "変異の実行が127で終わる(コマンドが無い)とInvalidで4" "$(exits 127)" "4 Invalid"
equals "変異の実行が128以上で終わる(クラッシュ)とKilledで0" "$(exits 134)" "0 Killed"

lines=$(wc -l < "$mlog")
runs=$(wc -l < "$count")
untouched() { [ "$rc" = 2 ] && [ "$(wc -l < "$mlog")" = "$lines" ] && [ "$(wc -l < "$count")" = "$runs" ] && grep -q "1 + " "$repo/app.sh"; }
printf 'dirt\n' > "$repo/dirt.txt"
mutate kill > /dev/null 2>&1
rc=$?
check "未追跡のファイルがあると2で終わり、記録もせず、パッチも当てない" untouched
rm -f "$repo/dirt.txt"
printf '# dirt\n' >> "$repo/test.sh"
mutate kill > /dev/null 2>&1
rc=$?
check "未コミットの変更があると2で終わり、記録もせず、パッチも当てない" untouched
g checkout -q -- test.sh
# timeoutのほかは、evidence.shとテストのコマンドが使うものだけを置いたPATH
nobin="$work/nobin"
mkdir -p "$nobin"
for c in awk basename cp date dirname git mkdir mktemp rm sh; do
  printf '#!/bin/sh\nexec %q "$@"\n' "$(command -v "$c")" > "$nobin/$c"
  chmod +x "$nobin/$c"
done
(cd "$repo" && MUTATE_TIMEOUT=2 PATH="$nobin" "$BASH" "$ev" "$mlog" mutate "$work/kill.patch" -- sh -c 'echo run >> "$0"; sh test.sh' "$count") > /dev/null 2>&1
rc=$?
check "MUTATE_TIMEOUTがあってtimeoutのコマンドが無いと、2で終わり、記録もせず、パッチも当てない" untouched

# 中身が変われば、同じコマンドでも基準の実行をやり直す
printf 'there\n' >> "$repo/sub/here.txt"
g commit -q -am here
fp0=$(fp)
mutate kill > /dev/null
equals "指紋が変わると、同じコマンドでも基準の実行をやり直す" "$(wc -l < "$count")" "$((runs + 2))"
lines=$(wc -l < "$mlog")

# 変異のときだけ、コマンドが追跡しているファイルを書き換える。戻した後の作業ツリーが違うので、何も記録しない
e "$mlog" mutate "$work/kill.patch" -- sh -c 'grep -q "1 - " app.sh && echo x >> test.sh; sh test.sh' > /dev/null 2>&1
rc=$?
check "変異の実行がファイルを書き換えると5で終わり、変異の結果を記録しない" '[ "$rc" = 5 ] && [ "$(wc -l < "$mlog")" = "$((lines + 1))" ] && [ "$(last 3 "$mlog")" = baseline ]'
g checkout -q -- test.sh
lines=$(wc -l < "$mlog")
runs=$(wc -l < "$count")
e "$mlog" mutate "$work/kill.patch" -- sh -c 'echo run >> "$0"; echo x >> test.sh' "$count" > /dev/null 2>&1
rc=$?
check "基準の実行がファイルを書き換えると、5で終わり、変異を回さず、baselineの行も残さない" '[ "$rc" = 5 ] && [ "$(wc -l < "$count")" = "$((runs + 1))" ] && [ "$(wc -l < "$mlog")" = "$lines" ]'
g checkout -q -- test.sh

# --- サブディレクトリとlinked worktree ---
slog="$work/sub.tsv"
check "サブディレクトリから、その場所でコマンドを回す" '(cd "$repo/sub" && bash "$ev" "$slog" run here -- test -f here.txt)'
check "サブディレクトリからcheckできる" '(cd "$repo/sub" && bash "$ev" "$slog" check here) && e "$slog" check here'
check "サブディレクトリから、トップのファイルを変える変異を当てられる" '(cd "$repo/sub" && bash "$ev" "$work/subm.tsv" mutate "$work/kill.patch" -- sh ../test.sh) && same'
g worktree add -q "$work/wt" -b wt
wlog="$work/wt.tsv"
check "linked worktreeでrunとcheckが動く" '(cd "$work/wt" && bash "$ev" "$wlog" run w -- true && bash "$ev" "$wlog" check w)'
printf 'y\n' >> "$work/wt/app.sh"
check "linked worktreeの変更でSTALEになる" '! (cd "$work/wt" && bash "$ev" "$wlog" check w)'
check "linked worktreeの変更は、元の作業ツリーの指紋を変えない" same

if [ "$failures" -gt 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
