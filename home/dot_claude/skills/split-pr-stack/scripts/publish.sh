#!/bin/bash
# Push the base branch and the layer branches, open the base PR (draft) and the stacked child PRs,
# fill the cross-references, check every PR, and close the original PR. Run only after the user approves.
# After a failure, fix the cause and rerun with the same config: a branch that already has an open PR
# into its base keeps that PR.
#
# usage: publish.sh <config.sh>
#
# config.sh defines:
#   WT            worktree holding all the branches
#   REPO          owner/name
#   BASE_BRANCH   the integration branch (already has one empty commit)
#   BASE_TARGET   the branch the base PR targets (main, or the PR the stack sits on)
#   BASE_TITLE    title of the base PR
#   LAYERS_TSV    one line per layer, bottom first: <layer>\t<branch>\t<prereq layers, comma-separated, or ->
#   BODY_DIR      <layer>.md for each child, BASE.md, and optionally CLOSE.md
#   VERIFY_DIR    <layer>.md: the 動作確認 bullets substituted for {{VERIFY}}
#   CHILD_DRAFT   "true" to open the child PRs as drafts
#   ORIGINAL_PR   number of the PR being replaced, or empty
#   ASSIGNEE      login set as the assignee of every PR (default: @me)
#   OUT           directory for the rendered bodies and numbers.txt
#
# Child bodies use {{BASE}} {{BELOW}} {{VERIFY}} {{PREREQ}} {{NEXT}}; BASE.md uses {{PR:<layer>}};
# CLOSE.md uses {{BASE}}.
set -euo pipefail
# shellcheck source=/dev/null
source "$1"
mkdir -p "$OUT"
ASSIGNEE=${ASSIGNEE:-@me}
: > "$OUT/numbers.txt"

render() {
  python3 -I - "$@" <<'PY'
import sys
src, dst, *pairs = sys.argv[1:]
text = open(src, encoding="utf-8").read()
for pair in pairs:
    key, value = pair.split("=", 1)
    if value.startswith("@"):
        value = open(value[1:], encoding="utf-8").read().strip()
    text = text.replace("{{%s}}" % key, value)
open(dst, "w", encoding="utf-8").write(text)
PY
}

pr_of() { awk -v l="$1" '$1 == l {print $2}' "$OUT/numbers.txt"; }

# usage: open_pr <base> <head> <gh pr create options...>; prints the URL of the open PR.
open_pr() {
  local base=$1 head=$2 url
  shift 2
  url=$(gh pr list --repo "$REPO" --state open --base "$base" --head "$head" --json url --jq '.[0].url // empty') || return
  [ -n "$url" ] || url=$(gh pr create --repo "$REPO" --assignee "$ASSIGNEE" --base "$base" --head "$head" "$@") || return
  echo "$url"
}

layers=()
branches=("$BASE_BRANCH")
while IFS=$'\t' read -r layer branch prereq; do
  [ -z "$layer" ] && continue
  layers+=("$layer")
  branches+=("$branch")
done < "$LAYERS_TSV"
branch_of() { awk -F'\t' -v l="$1" '$1 == l {print $2}' "$LAYERS_TSV"; }
prereq_of() { awk -F'\t' -v l="$1" '$1 == l {print $3}' "$LAYERS_TSV"; }

git -C "$WT" push --atomic -u origin "${branches[@]}"

draft=()
[ "${CHILD_DRAFT:-false}" = "true" ] && draft=(--draft)

base_url=$(open_pr "$BASE_TARGET" "$BASE_BRANCH" --draft --title "$BASE_TITLE" --body-file "$BODY_DIR/BASE.md")
base_pr=${base_url##*/}
echo "BASE $base_pr $base_url" | tee -a "$OUT/numbers.txt"

below_branch=$BASE_BRANCH
below_ref="なし（ベースに向いている）"
for layer in "${layers[@]}"; do
  branch=$(branch_of "$layer")
  prereq=$(prereq_of "$layer")
  if [ -z "$prereq" ] || [ "$prereq" = "-" ]; then
    prereq_ref="なし（ほかの子 PR とは独立に読める）"
  else
    prereq_ref=""
    IFS=',' read -r -a deps <<< "$prereq"
    for d in "${deps[@]}"; do
      n=$(pr_of "$d")
      [ -n "$n" ] || { echo "$layer: prerequisite $d has no PR yet (must be below it)" >&2; exit 1; }
      prereq_ref="${prereq_ref:+$prereq_ref、}#$n"
    done
  fi
  render "$BODY_DIR/$layer.md" "$OUT/$layer.md" "BASE=#$base_pr" "BELOW=$below_ref" \
    "VERIFY=@$VERIFY_DIR/$layer.md" "PREREQ=$prereq_ref"
  title=$(git -C "$WT" log -1 --format=%s "$branch")
  url=$(open_pr "$below_branch" "$branch" ${draft[@]+"${draft[@]}"} --title "$title" --body-file "$OUT/$layer.md")
  num=${url##*/}
  echo "$layer $num $url" | tee -a "$OUT/numbers.txt"
  below_branch=$branch
  below_ref="#$num"
done

# Bots append to the bodies right after creation, so fill the late references into the live bodies.
count=${#layers[@]}
for i in "${!layers[@]}"; do
  num=$(pr_of "${layers[$i]}")
  if [ $((i + 1)) -lt "$count" ]; then next="#$(pr_of "${layers[$((i + 1))]}")"; else next="なし（スタックの一番上）"; fi
  gh pr view "$num" --repo "$REPO" --json body --jq .body > "$OUT/live_$num.md"
  render "$OUT/live_$num.md" "$OUT/live_$num.md" "NEXT=$next"
  gh pr edit "$num" --repo "$REPO" --body-file "$OUT/live_$num.md" > /dev/null
done

pairs=()
for layer in "${layers[@]}"; do pairs+=("PR:$layer=#$(pr_of "$layer")"); done
gh pr view "$base_pr" --repo "$REPO" --json body --jq .body > "$OUT/live_base.md"
render "$OUT/live_base.md" "$OUT/live_base.md" "${pairs[@]}"
gh pr edit "$base_pr" --repo "$REPO" --body-file "$OUT/live_base.md" > /dev/null

unresolved=0
while read -r _ num _; do
  line=$(gh pr view "$num" --repo "$REPO" --json number,baseRefName,headRefName,isDraft,changedFiles,assignees,body \
    --jq '"#\(.number) draft=\(.isDraft) \(.headRefName) -> \(.baseRefName) files=\(.changedFiles) assignees=\([.assignees[].login] | join(",")) unresolved=\(.body | test("[{][{][A-Z]+(:[^{}]*)?[}][}]"))"' < /dev/null)
  echo "$line"
  if [[ $line == *unresolved=true ]]; then unresolved=$((unresolved + 1)); fi
done < "$OUT/numbers.txt"
if [ "$unresolved" -gt 0 ]; then
  echo "$unresolved PR bodies still have {{...}}; fix them on GitHub, then rerun to close the original PR" >&2
  exit 1
fi

if [ -n "${ORIGINAL_PR:-}" ]; then
  state=$(gh pr view "$ORIGINAL_PR" --repo "$REPO" --json state --jq .state)
  if [ "$state" = OPEN ]; then
    render "$BODY_DIR/CLOSE.md" "$OUT/CLOSE.md" "BASE=#$base_pr"
    gh pr close "$ORIGINAL_PR" --repo "$REPO" --comment "$(cat "$OUT/CLOSE.md")"
  fi
fi
echo PUBLISHED
