#!/bin/bash
# split-pr-stackのスクリプト(home/dot_claude/skills/split-pr-stack/scripts)を、使い捨てのリポジトリで試す。
# publish.shは、PRを手元のJSONに記録する偽のghで試す。偽のghの--jqには、miseで取得したjqを使う
# checkに渡す文字列の中で変数を展開するので、SC2016とSC2034を抑える
# shellcheck disable=SC2016,SC2034
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scripts="$root/home/dot_claude/skills/split-pr-stack/scripts"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
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

# BASEからFINALへ、層Aはモード、削除、空白や日本語のパス、バイナリ、シンボリックリンク、
# [id]/new.txtをglobとして読むと当たるd/new.txtを、層Bはリネームを持つ。shared.txtは両方の層が変える。
# ファイルのdfは層Aで消え、層Bでディレクトリになる。Readme.mdは層Bで大文字と小文字だけを変える。
# OWNERSでは、同じ場所を指す2つのパスのうち、FINALにあるほうを先に書く
printf 'old\n' > "$repo/old.txt"
printf 'base\n' > "$repo/shared.txt"
printf 'echo\n' > "$repo/run.sh"
printf 'gone\n' > "$repo/gone.txt"
printf 'df\n' > "$repo/df"
printf 'readme\n' > "$repo/Readme.md"
g add -A && g commit -q -m base
base=$(g rev-parse HEAD)
mkdir -p "$repo/[id]" "$repo/d"
g mv old.txt '[id]/new.txt'
g rm -q gone.txt df
mkdir -p "$repo/df"
printf 'x\n' > "$repo/df/x.txt"
g mv Readme.md README.md
printf 'base\na\nb\n' > "$repo/shared.txt"
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
ORDER = ["A", "B"]
OWNERS = {{
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
    "README.md": ["B"],
    "Readme.md": ["B"],
    "[id]/new.txt": ["B"],
}}'''
transforms = '''def t_shared(t):
    if below("B"):
        t = cut(t, "b\\n")
    return t


TRANSFORMS = {"shared.txt": t_shared}'''


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
for layer in A B; do
  g switch -q -c "stack/$layer"
  check "層${layer}を書き出せる" 'python3 -I "$work/build_layers.py" "$repo" "$layer"'
  g add -A
  g commit -q --allow-empty -m "$layer"
done

equals "先端のツリーが元のブランチと一致する" "$(g rev-parse 'stack/B^{tree}')" "$(g rev-parse "$final^{tree}")"
check "リネームの元のパスは、リネームする層まで残る" 'g cat-file -e stack/A:old.txt && ! g cat-file -e stack/B:old.txt'
check "リネームの先のパスは、リネームする層で現れる" '! g cat-file -e "stack/A:[id]/new.txt" && g cat-file -e "stack/B:[id]/new.txt"'
check "パスをglobとして読まない" 'g cat-file -e stack/A:d/new.txt'
check "消したファイルは、消す層で消える" '! g cat-file -e stack/A:gone.txt'
check "ディレクトリになるファイルの場所に、上の層の中身を入れない" '! g cat-file -e stack/A:df && ! g cat-file -e stack/A:df/x.txt && g cat-file -e stack/B:df/x.txt'
check "大文字と小文字だけを変えるリネームで、どちらかを消しすぎない" 'g cat-file -e stack/A:Readme.md && g cat-file -e stack/B:README.md && ! g cat-file -e stack/B:Readme.md'
check "空白と日本語を含むパスを扱える" 'g cat-file -e "stack/A:with space.txt" && g cat-file -e "stack/A:日本語.md"'
equals "共有ファイルは、上の層の部分を除いて書く" "$(g show stack/A:shared.txt)" "base
a"
equals "モードの変更を再現する" "$(g ls-tree stack/A run.sh | cut -c1-6)" "100755"
equals "シンボリックリンクを再現する" "$(g ls-tree stack/A link | cut -c1-6)" "120000"
equals "バイナリのファイルを再現する" "$(g rev-parse stack/A:bin.dat)" "$(g rev-parse "$final:bin.dat")"

# verify.shは、層の行をDONEの行の前に入れて回す。run.shは層AとBで中身が同じなので、
# 層Aのビルドが残した変更は、戻さなければ層Bに持ち越される
verify() {
  LAYERS="$1" awk '/^echo .*DONE/ { print ENVIRON["LAYERS"] } { print }' "$scripts/verify.sh" > "$work/verify.sh"
  bash "$work/verify.sh" "$repo" "$2"
}
verify 'layer A1 stack/A . sh -c "echo dirt >> run.sh; touch junk"
layer B1 stack/B . sh -c "test ! -e junk && git diff --quiet"
layer B2 stack/B . false
layer X1 stack/missing . true' "$work/vlog1" 2> "$work/vlog1.err"
rc=$?
summary="$work/vlog1/summary.txt"
check "失敗した層があると0以外で終わる" '[ "$rc" -ne 0 ]'
check "ビルドが残した変更をdirtyに出す" 'grep -q "^A1 stack/A rc=0 .*dirty=\[.*run.sh.*junk" "$summary"'
check "ビルドが残した変更を次の層に持ち越さない" 'grep -q "^B1 stack/B rc=0 " "$summary"'
check "検査の失敗をrcに出す" 'grep -q "^B2 stack/B rc=1 " "$summary"'
check "ブランチの無い層も失敗に数える" 'grep -q "^X1 stack/missing checkout-failed" "$summary" && grep -q "^DONE failed=2$" "$summary"'
check "すべての層が通れば0で終わる" 'verify "layer B1 stack/B . true" "$work/vlog2"'
touch "$repo/junk"
check "作業ツリーに未コミットの変更があると始めない" '! verify "layer B1 stack/B . true" "$work/vlog3" && [ ! -e "$work/vlog3/summary.txt" ]'
rm -f "$repo/junk"

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
        p["state"] == "OPEN" and p["baseRefName"] == base and p["headRefName"] == head for p in prs
    ):
        sys.exit(f"cannot create a pull request for {head} into {base}")
    n = max(p["number"] for p in prs) + 1
    prs.append({"number": n, "url": f"https://github.com/o/r/pull/{n}", "baseRefName": base, "headRefName": head,
                "isDraft": "--draft" in args, "state": "OPEN", "changedFiles": 1,
                "assignees": [{"login": opt("--assignee")}], "body": body()})
    save()
    sys.stdout.buffer.write(f"https://github.com/o/r/pull/{n}\n".encode())
elif cmd == "list":
    out([p for p in prs if p["state"] == "OPEN" and p["baseRefName"] == opt("--base") and p["headRefName"] == opt("--head")])
elif cmd == "view":
    out(find(args[2]))
elif cmd == "edit":
    find(args[2])["body"] = body()
    save()
elif cmd == "close":
    find(args[2])["state"] = "CLOSED"
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
printf 'A\tstack/A\t-\nB\tstack/B\tA\n' > "$work/layers.tsv"

# $1は記録するJSON、$2は本文のディレクトリ、$3は閉じる元のPRの番号(既定は#1。記録にあるのは#1だけ)
publish() {
  printf '[{"number": 1, "baseRefName": "main", "headRefName": "feature", "state": "OPEN"}]' > "$1"
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

state="$work/state1.json"
GH_FAIL_HEAD=stack/B publish "$state" "$work/bodies" > "$work/publish1.log" 2>&1
rc=$?
check "子PRを作れないと0以外で止まり、元のPRを閉じない" '[ "$rc" -ne 0 ] && [ "$(q "$state" ".[0].state")" = OPEN ]'
check "子PRを作れないと、その先の本文を埋めない" '[ "$(q "$state" ".[] | select(.headRefName == \"stack/A\") | .body | test(\"next=[{][{]NEXT\")")" = true ]'
check "止まった後に同じ設定で実行し直せる" 'rerun "$state" > "$work/publish2.log" 2>&1'
equals "実行し直しても、PRを作り直さない" "$(q "$state" '[.[] | select(.state == "OPEN") | .headRefName] | sort | join(" ")')" "stack/A stack/B stack/base"
equals "実行し直すと、元のPRを閉じる" "$(q "$state" '.[0].state')" "CLOSED"
a=$(q "$state" '.[] | select(.headRefName == "stack/A") | .number')
b=$(q "$state" '.[] | select(.headRefName == "stack/B") | .number')
equals "子PRの本文に、直下と先に読むPRと次のPRが入る" "$(q "$state" '.[] | select(.headRefName != "feature") | .body | split("\n")[0]' | tr '\n' '|')" "#$a #$b|A below=なし（ベースに向いている） prereq=なし（ほかの子 PR とは独立に読める） next=#$b|B below=#$a prereq=#$a next=なし（スタックの一番上）|"

cp -r "$work/bodies" "$work/bodies-typo"
printf 'A {{TYPO}}\n' > "$work/bodies-typo/A.md"
state="$work/state2.json"
publish "$state" "$work/bodies-typo" > "$work/publish3.log" 2>&1
rc=$?
check "未置換のプレースホルダが残ると0以外で止まり、元のPRを閉じない" '[ "$rc" -ne 0 ] && [ "$(q "$state" ".[0].state")" = OPEN ]'

state="$work/state3.json"
publish "$state" "$work/bodies" 99 > "$work/publish4.log" 2>&1
rc=$?
check "元のPRの状態を読めないと0以外で止まる" '[ "$rc" -ne 0 ] && ! grep -q PUBLISHED "$work/publish4.log"'

if [ "$failures" -gt 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
