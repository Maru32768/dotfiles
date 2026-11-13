#!/bin/bash
# Record checks and mutation experiments against the content of the current git worktree, so a report claims
# only what passed on the tree it reports.
#
# usage: evidence.sh <evidence.tsv> run <label> -- <command...>
#        evidence.sh <evidence.tsv> mutate <patch> -- <command...>
#        evidence.sh <evidence.tsv> check <label>...
#        evidence.sh <evidence.tsv> table
#
# One line per record: <UTC time>\t<run|mutate>\t<label>\t<result>\t<fingerprint>\t<command>. The fingerprint is
# the tree id of the worktree as it is (tracked files and untracked files that are not ignored), so it is the same
# before and after committing the same content.
#
# run     Runs the command, records its exit code with the fingerprint from before it ran, and exits with that code.
# check   Prints OK, MISSING, FAILED or STALE for the latest run of each label. Exits 0 only when all are OK.
# table   Prints the latest runs on the current fingerprint as a Markdown table. Exits 1 when there are none.
# mutate  Needs a clean worktree. Runs the command unmutated (the baseline; skipped when the latest run of the same
#         command on this fingerprint passed), applies the patch, runs $MUTATE_BUILD with bash -c when it is set,
#         runs the command (under `timeout $MUTATE_TIMEOUT` when it is set), reverts with git apply -R, and checks
#         that the worktree is back where it started. The baseline also runs $MUTATE_BUILD and the timeout, and
#         $MUTATE_BUILD runs once more after the revert so no build output keeps the mutant.
#         Exits 0 Killed, 1 Survived, 3 Timeout, 4 Invalid (the baseline fails, the patch does not apply, or the
#         mutant does not build), and 5 when the worktree did not come back (nothing is recorded or cleaned up).
# Exits 2 without running anything on a usage error, a dirty worktree for mutate, or an <evidence.tsv> inside the
# worktree that is not ignored (every record would change the fingerprint).
set -uo pipefail

die() { printf 'evidence.sh: %s\n' "$1" >&2; exit 2; }
[ $# -ge 2 ] || die "usage: evidence.sh <evidence.tsv> run <label> -- <command...> | mutate <patch> -- <command...> | check <label>... | table"
file=$1 sub=$2
shift 2
top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git worktree"
index=$(git rev-parse --path-format=absolute --git-path index) || die "cannot find the index"

valid_label() {
  case $1 in '' | *$'\t'* | *$'\n'*) die "a label must be non-empty and have no tab or newline" ;; esac
}

guard_file() {
  local dir
  dir=$(dirname -- "$file")
  if [ "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" = "$top" ] &&
    ! git -C "$dir" check-ignore -q -- "$(basename -- "$file")"; then
    die "$file is inside the worktree and not ignored; keep it outside or ignore it"
  fi
}

# Starts from a copy of the real index so tracked files that match .gitignore stay in, and the stat cache keeps it fast.
fingerprint() {
  local tmp rc
  tmp=$(mktemp -d) || return
  [ ! -f "$index" ] || cp "$index" "$tmp/index"
  GIT_INDEX_FILE="$tmp/index" git -C "$top" -c advice.addEmbeddedRepo=false add -A &&
    GIT_INDEX_FILE="$tmp/index" git -C "$top" write-tree
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

clean() { [ -z "$(git -C "$top" status --porcelain --untracked-files=normal)" ]; }

record() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" "$cmd" >> "$file"
}

# Prints "<result>\t<fingerprint>\t<command>" of the latest run of the label, or nothing.
latest() {
  L=$1 awk -F'\t' '$2 == "run" && $3 == ENVIRON["L"] { r = $4 "\t" $5 "\t" $6 } END { if (r != "") print r }' "$src"
}

labels() { awk -F'\t' '$2 == "run" && $3 != "baseline" && !seen[$3]++ { print $3 }' "$src"; }

parse_command() {
  [ "${1:-}" = "--" ] && [ $# -ge 2 ] || die "$sub needs -- <command...>"
  shift
  command=("$@")
  cmd=${*//[$'\t\r\n']/ }
}

run_cmd() {
  local label=$1 before after rc
  valid_label "$label"
  shift
  parse_command "$@"
  mkdir -p "$(dirname -- "$file")" || die "cannot create the directory of $file"
  guard_file
  before=$(fingerprint) || die "cannot compute the fingerprint"
  "${command[@]}"
  rc=$?
  record run "$label" "$rc" "$before"
  after=$(fingerprint)
  if [ "$after" != "$before" ]; then
    printf 'evidence.sh: warning: %s changed the worktree; the record keeps the fingerprint from before it ran\n' "$label" >&2
  fi
  exit "$rc"
}

check_cmd() {
  local now label row result fp state status=0
  for label; do valid_label "$label"; done
  guard_file
  now=$(fingerprint) || die "cannot compute the fingerprint"
  for label; do
    row=$(latest "$label")
    IFS=$'\t' read -r result fp _ <<< "$row"
    if [ -z "$row" ]; then state=MISSING
    elif [ "$result" != 0 ]; then state=FAILED
    elif [ "$fp" != "$now" ]; then state=STALE
    else state=OK
    fi
    printf '%s %s\n' "$state" "$label"
    [ "$state" = OK ] || status=1
  done
  exit "$status"
}

table_cmd() {
  local now label result fp command rows=0
  guard_file
  now=$(fingerprint) || die "cannot compute the fingerprint"
  while IFS= read -r label; do
    IFS=$'\t' read -r result fp command <<< "$(latest "$label")"
    [ "$fp" = "$now" ] || continue
    [ "$rows" -gt 0 ] || printf '| 検査 | 結果 | コマンド |\n|---|---|---|\n'
    rows=$((rows + 1))
    if [ "$result" = 0 ]; then result=成功; else result="失敗(終了コード $result)"; fi
    printf "| %s | %s | \`%s\` |\n" "${label//|/\\|}" "$result" "${command//|/\\|}"
  done < <(labels)
  [ "$rows" -gt 0 ] || { printf 'evidence.sh: no runs on the current worktree in %s\n' "$file" >&2; exit 1; }
}

build() { [ -z "${MUTATE_BUILD:-}" ] || bash -c "$MUTATE_BUILD"; }

target() {
  if [ -n "${MUTATE_TIMEOUT:-}" ]; then timeout "$MUTATE_TIMEOUT" "${command[@]}"; else "${command[@]}"; fi
}

intact() {
  [ "$(fingerprint)" = "$before" ] && clean && return 0
  {
    printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
    printf '!!! evidence.sh: the worktree did not come back after %s\n' "$1"
    printf '!!! Nothing was cleaned up or recorded. Inspect it before you do anything else:\n'
    git -C "$top" status --short --untracked-files=normal
    printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
  } >&2
  exit 5
}

invalid() {
  printf 'evidence.sh: Invalid: %s\n' "$1" >&2
  record mutate "$name" Invalid "$before"
  exit 4
}

mutate_cmd() {
  local patch=$1 rc result
  name=$(basename -- "$patch")
  valid_label "$name"
  shift
  parse_command "$@"
  [ -f "$patch" ] || die "no such patch: $patch"
  # git apply skips paths outside the current directory, so it always runs from the top with an absolute path.
  patch="$(cd "$(dirname -- "$patch")" && pwd)/$name"
  mkdir -p "$(dirname -- "$file")" || die "cannot create the directory of $file"
  guard_file
  clean || die "the worktree has uncommitted changes or untracked files; commit them first so the revert can be checked"
  before=$(fingerprint) || die "cannot compute the fingerprint"
  if ! FP=$before CMD=$cmd awk -F'\t' '$2 == "run" && $5 == ENVIRON["FP"] && $6 == ENVIRON["CMD"] { r = $4 }
      END { exit r != "0" }' "$file" 2>/dev/null; then
    build || invalid "MUTATE_BUILD fails before mutating"
    target
    rc=$?
    [ "$rc" -eq 0 ] || invalid "the command fails before mutating (exit $rc)"
    record run baseline 0 "$before"
    intact "the baseline"
  fi
  git -C "$top" apply --check -- "$patch" || invalid "the patch does not apply"
  git -C "$top" apply -- "$patch" || { intact "a failed git apply"; invalid "git apply failed"; }
  if ! build; then
    result=Invalid
  else
    target
    rc=$?
    if [ "$rc" -eq 0 ]; then result=Survived
    elif [ "$rc" -eq 124 ] && [ -n "${MUTATE_TIMEOUT:-}" ]; then result=Timeout
    else result=Killed
    fi
  fi
  git -C "$top" apply -R -- "$patch"
  intact "reverting $name"
  build || printf 'evidence.sh: warning: MUTATE_BUILD fails after reverting; build outputs may still hold the mutant\n' >&2
  record mutate "$name" "$result" "$before"
  printf '%s %s\n' "$result" "$name"
  case $result in Killed) exit 0 ;; Survived) exit 1 ;; Timeout) exit 3 ;; *) exit 4 ;; esac
}

src=$file
[ -f "$src" ] || src=/dev/null
case $sub in
  run) [ $# -ge 1 ] || die "run needs <label>"; run_cmd "$@" ;;
  mutate) [ $# -ge 1 ] || die "mutate needs <patch>"; mutate_cmd "$@" ;;
  check) [ $# -ge 1 ] || die "check needs <label>..."; check_cmd "$@" ;;
  table) [ $# -eq 0 ] || die "table takes no arguments"; table_cmd ;;
  *) die "unknown subcommand: $sub" ;;
esac
