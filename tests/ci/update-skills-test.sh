#!/bin/bash
# provision/update-skills.shを、使い捨ての作業ツリーと、ls-remoteに決めたコミットを返す偽のgitで試す
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }

old=1111111111111111111111111111111111111111
new=2222222222222222222222222222222222222222

mkdir -p "$work/bin" "$work/tree/provision" "$work/tree/home/.chezmoidata"
cp "$root/provision/update-skills.sh" "$work/tree/provision/"
cat >"$work/bin/git" <<'EOF'
#!/bin/bash
[ "$1" = ls-remote ] && [ "$3" = HEAD ] || { echo "fake git: unsupported $*" >&2; exit 1; }
awk -v url="$2" '"https://github.com/" $1 ".git" == url { print $2 "\tHEAD" }' "$HEADS"
EOF
chmod +x "$work/bin/git"
cat >"$work/heads" <<EOF
o/fresh $old
o/stale $new
o/market $new
o/same $old
o/branch $new
o/unpinned $new
EOF

skills="$work/tree/home/.chezmoidata/skills.toml"
settings="$work/tree/home/.claude-settings.json"
cat >"$skills.orig" <<EOF
[skills.fresh]
repo = "o/fresh"
path = ""
commit = "$old"
targets = ["claude"]

[skills.stale]
repo = "o/stale"
path = "skills/stale"
commit = "$old"
targets = ["claude", "codex"]
EOF
# sameはmarketと同じ古いコミットに固定した、最新のマーケットプレイス。giturlの1行の書き方はjqで書き直すと崩れる
cat >"$settings.orig" <<EOF
{
  "enabledPlugins": {
    "p@market": true
  },
  "extraKnownMarketplaces": {
    "same": {
      "source": {
        "source": "github",
        "repo": "o/same",
        "ref": "$old"
      },
      "autoUpdate": true
    },
    "market": {
      "source": {
        "source": "github",
        "repo": "o/market",
        "ref": "$old"
      },
      "autoUpdate": true
    },
    "branch": {
      "source": {
        "source": "github",
        "repo": "o/branch",
        "ref": "main"
      }
    },
    "unpinned": {
      "source": {
        "source": "github",
        "repo": "o/unpinned"
      }
    },
    "giturl": { "source": { "source": "git", "url": "https://github.com/o/giturl.git", "ref": "$old" } }
  }
}
EOF

reset() { cp "$skills.orig" "$skills" && cp "$settings.orig" "$settings"; }
run() { PATH="$work/bin:$PATH" HEADS="$work/heads" bash "$work/tree/provision/update-skills.sh" "$@" 2>&1; }
unchanged() { for f; do cmp -s "$f" "$f.orig" || return 1; done; }
check() { if "${@:2}"; then pass "$1"; else fail "$1"; fi; }
# 元のファイルから消えた行と足された行を、字下げも含めて"- 行"と"+ 行"で出す
changes() { diff "$1.orig" "$1" | sed -n 's/^< /- /p; s/^> /+ /p'; }
urls="stale: https://github.com/o/stale/compare/$old...$new
market: https://github.com/o/market/compare/$old...$new"
reminder="マーケットプレイスのプラグインは、反映した後にdocs/claude.mdの｢プラグイン｣の手順で入れ替えます"

reset
out="$(run --dry-run)"
equals "--dry-runは、古いスキルとマーケットプレイスのcompareのURLだけを出す" "$(grep ': https://' <<<"$out")" "$urls"
check "--dry-runはファイルを変えない" unchanged "$skills" "$settings"
equals "--dry-runは、プラグインの入れ替えを案内しない" "$(grep -cxF "$reminder" <<<"$out")" 0

reset
out="$(run market)"
equals "マーケットプレイスを上げると、プラグインの入れ替えを案内する" "$(tail -n1 <<<"$out")" "$reminder"
equals "マーケットプレイスを上げると、そのrefの行だけが変わる" "$(changes "$settings")" "-         \"ref\": \"$old\"
+         \"ref\": \"$new\""
equals "変わるのは、同じ古いコミットに固定したsameではなく、marketのref" "$(grep -A4 '"market": {' "$settings" | grep '"ref"' | tr -d ' ')" "\"ref\":\"$new\""
check "マーケットプレイスだけを上げると、スキルは変わらない" unchanged "$skills"

reset
out="$(run stale)"
equals "スキルだけを上げても、プラグインの入れ替えは案内しない" "$(grep -cxF "$reminder" <<<"$out")" 0
equals "スキルを上げると、そのcommitの行だけが変わる" "$(changes "$skills")" "- commit = \"$old\"
+ commit = \"$new\""
check "スキルだけを上げると、マーケットプレイスは変わらない" unchanged "$settings"

reset
out="$(run)"
equals "引数なしで成功する" "$?" 0
equals "書き換えるときも、古いもののcompareのURLを出す" "$(grep ': https://' <<<"$out")" "$urls"
equals "引数なしで、古いものをすべて上げる" "$(changes "$skills"; changes "$settings")" "- commit = \"$old\"
+ commit = \"$new\"
-         \"ref\": \"$old\"
+         \"ref\": \"$new\""
equals "上げた後にもう一度実行すると、すべて最新" "$(run)" "すべて最新です"

reset
for name in nope unpinned; do
  if run "$name" >/dev/null; then fail "固定していない名前($name)は失敗する"; else pass "固定していない名前($name)は失敗する"; fi
done
check "名前が無いときはファイルを変えない" unchanged "$skills" "$settings"

# キーが行の先頭に無いと、refの行を見つけられない
printf '{ "extraKnownMarketplaces": { "market": { "source": { "source": "github", "repo": "o/market", "ref": "%s" } } } }\n' "$old" >"$settings.orig"
reset
out="$(run market)"
equals "refの行を書き換えられないときは失敗する" "$?" 1
equals "失敗の理由は、refの行を書き換えられないこと" "$(grep -xF "書き換えられない: market" <<<"$out")" "書き換えられない: market"

: >"$skills.orig"
echo '{}' >"$settings.orig"
reset
equals "固定が1つも無いときは、すべて最新" "$(run)" "すべて最新です"

if [ "$failures" -gt 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
