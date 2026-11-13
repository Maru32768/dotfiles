#!/bin/bash
# split-pr-stackのスクリプト(home/dot_claude/skills/split-pr-stack/scripts)を、使い捨てのリポジトリで試す。
# publish.shは、PRを手元のJSONに記録する偽のghで試す。偽のghの--jqには、miseで取得したjqを使う
# checkに渡す文字列の中で変数を展開するので、SC2016とSC2034を抑える
# shellcheck disable=SC2016,SC2034
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$root/home/dot_claude/skills/split-pr-stack/scripts"
work="$(mktemp -d)"
# 落ちたときは、ログと記録を調べられるよう作業ディレクトリを残す
trap '[ "${failures:-1}" -eq 0 ] && rm -rf "$work" || printf "作業ディレクトリを残した: %s\n" "$work"' EXIT
JQ_VERSION="1.8.2"

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
# 利用者のquotepath=falseで、日本語のパスを改行で割る退行を見逃さないよう、gitの既定値に固定する
g config core.quotepath true

# BASEからFINALへ、層Aはモード、削除、空白や日本語のパス、バイナリ、シンボリックリンク、
# [id]/new.txtをglobとして読むと当たるd/new.txtを、層Bはリネームを持つ。shared.txtは両方の層が変える。
# ファイルのdfは層Aで消え、層Bでディレクトリになる。逆にディレクトリのfdは、中身が層Aで消え、層Bでファイルになる。
# Readme.mdは層Bで大文字と小文字だけを変える。
# OWNERSでは、同じ場所を指す2つのパスのうち、FINALにあるほうを先に書く。
# 層Cは、層AとCが変えるac.txtと、層BとCが変え、BASEには無いディレクトリにあるnew/bc.txtを仕上げる
printf 'old\n' > "$repo/old.txt"
printf 'base\n' > "$repo/shared.txt"
printf 'base\n' > "$repo/ac.txt"
printf 'echo\n' > "$repo/run.sh"
printf 'gone\n' > "$repo/gone.txt"
printf 'df\n' > "$repo/df"
mkdir -p "$repo/fd"
printf 'y\n' > "$repo/fd/y.txt"
printf 'readme\n' > "$repo/Readme.md"
g add -A && g commit -q -m base
base=$(g rev-parse HEAD)
mkdir -p "$repo/[id]" "$repo/d"
g mv old.txt '[id]/new.txt'
g rm -q gone.txt df fd/y.txt
mkdir -p "$repo/df"
printf 'x\n' > "$repo/df/x.txt"
printf 'fd\n' > "$repo/fd"
g mv Readme.md README.md
printf 'base\na\nb\n' > "$repo/shared.txt"
printf 'base\na\nc\n' > "$repo/ac.txt"
mkdir -p "$repo/new"
printf 'b\nc\n' > "$repo/new/bc.txt"
printf 'd\n' > "$repo/d/new.txt"
printf 'space\n' > "$repo/with space.txt"
printf '日本語\n' > "$repo/日本語.md"
printf '\000\001\377' > "$repo/bin.dat"
g add -A
g update-index --chmod=+x run.sh
g update-index --add --cacheinfo "120000,$(printf run.sh | g hash-object -w --stdin),link"
g commit -q -m final
g reset -q --hard
final=$(g rev-parse HEAD)

python3 -I - "$scripts/build_layers.py" "$work/build_layers.py" "$final" "$base" <<'EOF'
import sys

src, dst, final, base = sys.argv[1:]
config = f'''FINAL = "{final}"
BASE = "{base}"
ORDER = ["A", "B", "C"]
OWNERS = {{
    "ac.txt": ["A", "C"],
    "new/bc.txt": ["B", "C"],
    "run.sh": ["A"],
    "gone.txt": ["A"],
    "d/new.txt": ["A"],
    "with space.txt": ["A"],
    "日本語.md": ["A"],
    "bin.dat": ["A"],
    "link": ["A"],
    "shared.txt": ["A", "B"],
    "old.txt": ["B"],
    "df/x.txt": ["B"],
    "df": ["A"],
    "fd": ["B"],
    "fd/y.txt": ["A"],
    "README.md": ["B"],
    "Readme.md": ["B"],
    "[id]/new.txt": ["B"],
}}'''
transforms = '''def t_shared(t):
    if below("B"):
        t = cut(t, "b\\n")
    return t


def t_c(t):
    if below("C"):
        t = cut(t, "c\\n")
    return t


TRANSFORMS = {"shared.txt": t_shared, "ac.txt": t_c, "new/bc.txt": t_c}'''


def swap(lines, marker, body):
    start = next(i for i, ln in enumerate(lines) if ln.startswith(marker))
    end = next(i for i in range(start + 1, len(lines)) if lines[i].startswith("# ----"))
    return lines[: start + 1] + body.split("\n") + lines[end:]


lines = open(src, encoding="utf-8").read().split("\n")
lines = swap(swap(lines, "# ---- CONFIG", config), "# ---- TRANSFORMS", transforms)
open(dst, "w", encoding="utf-8", newline="").write("\n".join(lines))
EOF

g switch -q -c stack/base "$base"
g commit -q --allow-empty -m "ベース"
for layer in A B C; do
  g switch -q -c "stack/$layer"
  check "層${layer}を書き出せる" 'python3 -I "$work/build_layers.py" "$repo" "$layer"'
  check "層${layer}を書き出すと、indexと作業ツリーが揃い、addせずにコミットできる" 'g diff --quiet'
  g commit -q --allow-empty -m "$layer"
done

equals "先端のツリーが元のブランチと一致する" "$(g rev-parse 'stack/C^{tree}')" "$(g rev-parse "$final^{tree}")"
check "リネームの元のパスは、リネームする層まで残る" 'g cat-file -e stack/A:old.txt && ! g cat-file -e stack/B:old.txt'
check "リネームの先のパスは、リネームする層で現れる" '! g cat-file -e "stack/A:[id]/new.txt" && g cat-file -e "stack/B:[id]/new.txt"'
check "パスをglobとして読まない" 'g cat-file -e stack/A:d/new.txt'
check "消したファイルは、消す層で消える" '! g cat-file -e stack/A:gone.txt'
check "ディレクトリになるファイルの場所に、上の層の中身を入れない" '! g cat-file -e stack/A:df && ! g cat-file -e stack/A:df/x.txt && g cat-file -e stack/B:df/x.txt'
check "ファイルになるディレクトリは、中身を消した層で消え、ファイルを足す層でファイルになる" '! g cat-file -e stack/A:fd && ! g cat-file -e stack/A:fd/y.txt && [ "$(g cat-file -t stack/B:fd)" = blob ]'
check "大文字と小文字だけを変えるリネームで、どちらかを消しすぎない" 'g cat-file -e stack/A:Readme.md && g cat-file -e stack/B:README.md && ! g cat-file -e stack/B:Readme.md'
check "空白と日本語を含むパスを扱える" 'g cat-file -e "stack/A:with space.txt" && g cat-file -e "stack/A:日本語.md"'
equals "共有ファイルは、上の層の部分を除いて書く" "$(g show stack/A:shared.txt)" "base
a"
check "共有ファイルは、最初の持ち主より下の層ではBASEのまま" '! g cat-file -e stack/A:new/bc.txt'
equals "共有ファイルは、最初と最後の持ち主の間の層でも、上の層の部分を除いて書く" "$(g show stack/B:ac.txt)" "base
a"
equals "BASEに無いディレクトリの共有ファイルも、間の層で書ける" "$(g show stack/B:new/bc.txt)" "b"
equals "モードの変更を再現する" "$(g ls-tree stack/A run.sh | cut -c1-6)" "100755"
equals "シンボリックリンクを再現する" "$(g ls-tree stack/A link | cut -c1-6)" "120000"
equals "バイナリのファイルを再現する" "$(g rev-parse stack/A:bin.dat)" "$(g rev-parse "$final:bin.dat")"

# $1に、OWNERSの文字列を$2から$3へ、$4から$5へ置き換えたbuild_layers.pyを作る
misowned() {
  python3 -I - "$work/build_layers.py" "$@" <<'EOF'
import sys

src, dst, *pairs = sys.argv[1:]
t = open(src, encoding="utf-8").read()
for old, new in zip(pairs[::2], pairs[1::2]):
    assert t.count(old) == 1, old
    t = t.replace(old, new)
open(dst, "w", encoding="utf-8", newline="").write(t)
EOF
}
g switch -q --detach stack/base
# dfを消すのを層Bに、df/x.txtを足すのを層Aにすると、層Aにはファイルのdfとディレクトリのdfが両方要る
misowned "$work/bad_df.py" '"df/x.txt": ["B"]' '"df/x.txt": ["A"]' '"df": ["A"]' '"df": ["B"]'
check "同じ層にファイルとディレクトリの両方が要る割り当てでは、何も変えずに止まる" '! python3 -I "$work/bad_df.py" "$repo" A 2>/dev/null && [ -z "$(g status --porcelain)" ]'
# README.mdを足すのを層Aにすると、層AにはReadme.mdとREADME.mdが両方要る。大文字と小文字を区別しない
# ファイルシステムでは1つになるので、Linuxでもignorecaseをtrueにして試す
misowned "$work/bad_case.py" '"README.md": ["B"]' '"README.md": ["A"]'
icase=$(g config --type=bool --default=false core.ignorecase)
g config core.ignorecase true
check "ignorecaseのもとで、大文字と小文字だけが違う2つのパスが同じ層に要る割り当てでは、何も変えずに止まる" '! python3 -I "$work/bad_case.py" "$repo" A 2>/dev/null && [ -z "$(g status --porcelain)" ]'
g config core.ignorecase "$icase"
g reset -q --hard && g clean -qffd

# verify.shは、層の行をDONEの行の前に入れて回す。run.shは層AとBで中身が同じなので、
# 層Aのビルドが残した変更は、戻さなければ層Bに持ち越される
verify() {
  LAYERS="$1" awk '/^echo .*DONE/ { print ENVIRON["LAYERS"] } { print }' "$scripts/verify.sh" > "$work/verify.sh"
  bash "$work/verify.sh" "$repo" "$2"
}
verify 'layer A1 stack/A . sh -c "echo dirt >> run.sh; touch junk"
layer B1 stack/B . sh -c "test ! -e junk && git diff --quiet"
layer B2 stack/B . sh -c "touch junk2; false"
layer B3 stack/B . sh -c "test ! -e junk2"
layer X1 stack/missing . true' "$work/vlog1" 2> "$work/vlog1.err"
rc=$?
summary="$work/vlog1/summary.txt"
check "失敗した層があると0以外で終わる" '[ "$rc" -ne 0 ]'
check "ビルドが残した変更をdirtyに出す" 'grep -q "^A1 stack/A rc=0 .*dirty=\[.*run.sh.*junk" "$summary"'
check "ビルドが残した変更を次の層に持ち越さない" 'grep -q "^B1 stack/B rc=0 " "$summary"'
check "検査の失敗をrcに出す" 'grep -q "^B2 stack/B rc=1 " "$summary"'
check "失敗した層が残したものも次の層に持ち越さない" 'grep -q "^B3 stack/B rc=0 " "$summary"'
check "ブランチの無い層も失敗に数える" 'grep -q "^X1 stack/missing checkout-failed" "$summary" && grep -q "^DONE failed=2$" "$summary"'
check "checkoutの失敗の原因を層のログに残す" 'grep -q "stack/missing" "$work/vlog1/X1.log"'
check "すべての層が通れば0で終わる" 'verify "layer B1 stack/B . true" "$work/vlog2"'
touch "$repo/junk"
check "作業ツリーに未コミットの変更があると始めず、前回の結果も残さない" '! verify "layer B1 stack/B . true" "$work/vlog2" 2>/dev/null && [ ! -s "$work/vlog2/summary.txt" ]'
rm -f "$repo/junk"
check "ログのディレクトリがworktreeの中で無視されていなければ始めない" '! verify "layer B1 stack/B . true" "$repo/vlog" 2>/dev/null'
rm -rf "$repo/vlog"
g config status.showUntrackedFiles no
touch "$repo/junk"
check "status.showUntrackedFilesがnoでも、未追跡のファイルを見つけて始めない" '! verify "layer B1 stack/B . true" "$work/vlog4" 2>/dev/null && [ -e "$repo/junk" ]'
rm -f "$repo/junk"
check "status.showUntrackedFilesがnoでも、ビルドが残した未追跡のファイルをdirtyに出す" 'verify "layer U1 stack/B . touch junk3" "$work/vlog5" && grep -q "^U1 stack/B rc=0 .*dirty=\[?? junk3" "$work/vlog5/summary.txt"'
g config status.showUntrackedFiles normal
verify 'layer L1 stack/B . touch .git/index.lock' "$work/vlog6" 2>/dev/null
rc=$?
rm -f "$repo/.git/index.lock"
check "後片づけに失敗した層を失敗に数える" '[ "$rc" -ne 0 ] && grep -q "^L1 stack/B cleanup-failed" "$work/vlog6/summary.txt" && grep -q "^DONE failed=1$" "$work/vlog6/summary.txt"'
check "後片づけの失敗の原因を層のログに残す" 'grep -q "index.lock" "$work/vlog6/L1.log"'
check "ビルドが作った入れ子のリポジトリも次の層に持ち越さない" 'verify "layer N1 stack/B . git init -q sub
layer N2 stack/B . test ! -e sub" "$work/vlog7" && grep -q "^N2 stack/B rc=0 " "$work/vlog7/summary.txt"'

# 偽のghはPRをJSONに記録する。GH_FAIL_HEADのブランチのPRは作れない
git init -q --bare "$work/origin.git"
g remote add origin "$work/origin.git"
JQ="$(mise exec "jq@$JQ_VERSION" -- sh -c 'command -v jq')"
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'EOF'
#!/bin/bash
exec python3 -I "$(dirname "$0")/gh.py" "$GH_STATE" "$JQ" "$@"
EOF
chmod +x "$work/bin/gh"
cat > "$work/bin/gh.py" <<'EOF'
import json
import os
import subprocess
import sys

path, jq, *args = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    prs = json.load(f)


def opt(name):
    return args[args.index(name) + 1] if name in args else None


def find(num):
    return next(p for p in prs if p["number"] == int(num))


def save():
    with open(path, "w", encoding="utf-8") as f:
        json.dump(prs, f, ensure_ascii=False)


def out(value):
    fields = opt("--json").split(",")
    data = [{k: p[k] for k in fields} for p in value] if isinstance(value, list) else {k: value[k] for k in fields}
    r = subprocess.run([jq, "-r", opt("--jq")], input=json.dumps(data).encode(), capture_output=True, check=True)
    sys.stdout.buffer.write(r.stdout.replace(b"\r\n", b"\n"))


def body():
    with open(opt("--body-file"), encoding="utf-8") as f:
        return f.read()


cmd = args[1]
if cmd == "create":
    base, head = opt("--base"), opt("--head")
    if head == os.environ.get("GH_FAIL_HEAD") or any(
        p["state"] == "OPEN" and p["baseRefName"] == base and p["headRefName"] == head and not p["isCrossRepository"]
        for p in prs
    ):
        sys.exit(f"cannot create a pull request for {head} into {base}")
    n = max(p["number"] for p in prs) + 1
    prs.append({"number": n, "url": f"https://github.com/o/r/pull/{n}", "baseRefName": base, "headRefName": head,
                "isDraft": "--draft" in args, "state": "OPEN", "changedFiles": 1, "isCrossRepository": False,
                "assignees": [{"login": opt("--assignee")}], "body": body(), "edits": 0})
    save()
    sys.stdout.buffer.write(f"https://github.com/o/r/pull/{n}\n".encode())
elif cmd == "list":
    out([p for p in prs if p["state"] == "OPEN" and p["baseRefName"] == opt("--base") and p["headRefName"] == opt("--head")])
elif cmd == "view":
    out(find(args[2]))
elif cmd == "edit":
    pr = find(args[2])
    pr["body"] = body()
    pr["edits"] += 1
    save()
elif cmd == "close":
    pr = find(args[2])
    pr["state"] = "CLOSED"
    pr.setdefault("comments", []).append(opt("--comment"))
    save()
else:
    sys.exit(f"fake gh: unsupported {args}")
EOF

mkdir -p "$work/bodies" "$work/verify-md"
printf '{{PR:A}} {{PR:B}}\nGitHub Actionsの式はプレースホルダではない: ${{ secrets.TOKEN }}\n' > "$work/bodies/BASE.md"
printf 'moved to {{BASE}}\n' > "$work/bodies/CLOSE.md"
for layer in A B; do
  printf '%s below={{BELOW}} prereq={{PREREQ}} next={{NEXT}}\n{{VERIFY}}\n' "$layer" > "$work/bodies/$layer.md"
  printf -- '- ok\n' > "$work/verify-md/$layer.md"
done
printf 'A\tstack/A\t-\nB\tstack/B\tA' > "$work/layers.tsv"

# $1は記録するJSON、$2は本文のディレクトリ、$3は閉じる元のPRの番号(既定は#1)。
# 記録には、元のPRの#1と、forkの同じ名前のブランチからmainへ開いた#2がある
publish() {
  printf '[%s, %s]' \
    '{"number": 1, "baseRefName": "main", "headRefName": "feature", "state": "OPEN", "isCrossRepository": false}' \
    '{"number": 2, "url": "https://github.com/fork/r/pull/2", "baseRefName": "main", "headRefName": "stack/base", "state": "OPEN", "isCrossRepository": true, "body": "fork {{PR:A}}", "edits": 0}' > "$1"
  cat > "$1.config" <<EOF
WT="$repo"
REPO=o/r
BASE_BRANCH=stack/base
BASE_TARGET=main
BASE_TITLE=base
LAYERS_TSV="$work/layers.tsv"
BODY_DIR="$2"
VERIFY_DIR="$work/verify-md"
CHILD_DRAFT=false
ORIGINAL_PR=${3:-1}
OUT="$1.out"
EOF
  rerun "$1"
}
rerun() { PATH="$work/bin:$PATH" GH_STATE="$1" JQ="$JQ" bash "$scripts/publish.sh" "$1.config"; }
q() { "$JQ" -r "$2" "$1" | tr -d '\r'; }
# 記録の中で、ブランチ$2のPRの本文にjqの式$3を当てる。botの追記や、GitHubでの手直しの代わり
edit_body() { "$JQ" -c --arg head "$2" '(.[] | select(.headRefName == $head) | .body) |= '"$3" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

state="$work/state1.json"
GH_FAIL_HEAD=stack/B publish "$state" "$work/bodies" > "$work/publish1.log" 2>&1
rc=$?
check "子PRを作れないと0以外で止まり、元のPRを閉じない" '[ "$rc" -ne 0 ] && [ "$(q "$state" ".[0].state")" = OPEN ]'
check "子PRを作れないと、その先の本文を埋めない" '[ "$(q "$state" ".[] | select(.headRefName == \"stack/A\") | .body | test(\"next=[{][{]NEXT\")")" = true ]'
edit_body "$state" stack/A '. + "<!-- bot -->"'
check "止まった後に同じ設定で実行し直せる" 'rerun "$state" > "$work/publish2.log" 2>&1'
check "止まっている間にbotが本文に足したものを残す" '[ "$(q "$state" ".[] | select(.headRefName == \"stack/A\") | .body | contains(\"<!-- bot -->\")")" = true ]'
equals "実行し直しても、PRを作り直さない" "$(q "$state" '[.[] | select(.state == "OPEN" and (.isCrossRepository | not)) | .headRefName] | sort | join(" ")')" "stack/A stack/B stack/base"
equals "実行し直すと、元のPRを閉じる" "$(q "$state" '.[0].state')" "CLOSED"
equals "forkの同じ名前のブランチのPRを使わない" "$(q "$state" '.[1] | "\(.body) \(.edits)"')" "fork {{PR:A}} 0"
a=$(q "$state" '.[] | select(.headRefName == "stack/A") | .number')
b=$(q "$state" '.[] | select(.headRefName == "stack/B") | .number')
equals "子PRの本文に、直下と先に読むPRと次のPRが入る" "$(q "$state" '.[2:][] | .body | split("\n")[0]' | tr '\n' '|')" "#$a #$b|A below=なし（ベースに向いている） prereq=なし（ほかの子 PR とは独立に読める） next=#$b|B below=#$a prereq=#$a next=なし（スタックの一番上）|"
edits=$(q "$state" '[.[].edits] | add')
check "もう一度実行し直しても、本文を書き直さない" 'rerun "$state" > "$work/publish2b.log" 2>&1 && [ "$(q "$state" "[.[].edits] | add")" = "$edits" ]'
equals "もう一度実行し直しても、元のPRを2度は閉じない" "$(q "$state" '.[0].comments | length')" "1"
base_num=$(q "$state" '.[] | select(.headRefName == "stack/base" and (.isCrossRepository | not)) | .number')
equals "元のPRを閉じるコメントに、ベースPRを書く" "$(q "$state" '.[0].comments[0]')" "moved to #$base_num"
equals "ベースPRはDraftで作る" "$(q "$state" '.[] | select(.headRefName == "stack/base" and (.isCrossRepository | not)) | .isDraft')" "true"

cp -r "$work/bodies" "$work/bodies-typo"
printf 'A {{TYPO}}\n' > "$work/bodies-typo/A.md"
printf '{{PR:A}} {{PR:Z}}\n' > "$work/bodies-typo/BASE.md"
state="$work/state2.json"
publish "$state" "$work/bodies-typo" > "$work/publish3.log" 2>&1
rc=$?
check "未置換のプレースホルダが残ると0以外で止まり、元のPRを閉じない" '[ "$rc" -ne 0 ] && [ "$(q "$state" ".[0].state")" = OPEN ]'
check "層の一覧に無い{{PR:<層>}}も未置換とみなす" 'grep -q "stack/base -> main .*unresolved=true" "$work/publish3.log"'
base_edits=$(q "$state" '.[] | select(.headRefName == "stack/base" and (.isCrossRepository | not)) | .edits')
check "埋められないプレースホルダが残ったまま実行し直しても、本文を書き直さない" '! rerun "$state" > "$work/publish3a.log" 2>&1 && [ "$(q "$state" ".[] | select(.headRefName == \"stack/base\" and (.isCrossRepository | not)) | .edits")" = "$base_edits" ]'
edit_body "$state" stack/A 'sub("[{][{]TYPO[}][}]"; "fixed")'
edit_body "$state" stack/base 'sub("[{][{]PR:Z[}][}]"; "#0")'
check "GitHubで本文を直してから実行し直すと、直した本文のまま元のPRを閉じる" 'rerun "$state" > "$work/publish3b.log" 2>&1 && [ "$(q "$state" ".[0].state")" = CLOSED ] && [ "$(q "$state" ".[] | select(.headRefName == \"stack/A\") | .body")" = "A fixed" ]'

cp -r "$work/bodies" "$work/bodies-close"
printf 'moved to {{BASE}} {{TYPO}}\n' > "$work/bodies-close/CLOSE.md"
state="$work/state4.json"
publish "$state" "$work/bodies-close" > "$work/publish5.log" 2>&1
rc=$?
check "閉じるときのコメントにプレースホルダが残ると0以外で止まり、元のPRを閉じない" '[ "$rc" -ne 0 ] && [ "$(q "$state" ".[0].state")" = OPEN ]'

state="$work/state3.json"
publish "$state" "$work/bodies" 99 > "$work/publish4.log" 2>&1
rc=$?
check "元のPRの状態を読めないと0以外で止まる" '[ "$rc" -ne 0 ] && ! grep -q PUBLISHED "$work/publish4.log"'

if [ "$failures" -gt 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
