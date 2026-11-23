#!/bin/bash
# Check out each layer branch in the split worktree and run its checks; one summary line per layer.
# usage: verify.sh <worktree> <log-dir>   (copy this file, then write the layer lines above the DONE line)
# Exits 1 when a layer fails to check out, fails its checks, or cannot be reset afterwards, and 2 without
# running anything when the worktree is not clean at the start. Keep <log-dir> outside the worktree.
WT=$1
LOG=$2
mkdir -p "$LOG"
: > "$LOG/summary.txt"
if [ -n "$(git -C "$WT" status --porcelain --untracked-files=normal)" ]; then
  echo "$WT has uncommitted changes, or holds the log directory; commit or discard them, and keep the logs outside" >&2
  exit 2
fi
failed=0

# Set to the JUnit XML directory (relative to the worktree) to count the test cases each layer ran.
JUNIT_DIR=${JUNIT_DIR:-}

layer() {
  local name=$1 branch=$2 dir=$3
  shift 3
  if ! git -C "$WT" checkout -q "$branch" > "$LOG/$name.log" 2>&1; then
    echo "$name $branch checkout-failed" >> "$LOG/summary.txt"
    failed=$((failed + 1))
    return
  fi
  if [ -n "$JUNIT_DIR" ]; then
    touch "$LOG/$name.start"
    # XML files must be strictly newer than the marker; mtime resolution is one second on some filesystems.
    sleep 1
  fi
  local start=$SECONDS
  (cd "$WT/$dir" && "$@") >> "$LOG/$name.log" 2>&1
  local rc=$?
  [ "$rc" -eq 0 ] || failed=$((failed + 1))
  local dirty tests=""
  dirty=$(git -C "$WT" status --porcelain --untracked-files=normal | tr '\n' ' ')
  if [ -n "$JUNIT_DIR" ]; then
    tests=$(find "$WT/$JUNIT_DIR" -name 'TEST-*.xml' -newer "$LOG/$name.start" \
      -exec grep -ho 'tests="[0-9]*" skipped="[0-9]*" failures="[0-9]*" errors="[0-9]*"' {} + 2>/dev/null \
      | awk -F'"' '{t+=$2; s+=$4; f+=$6; e+=$8} END {printf "tests=%d skipped=%d failures=%d errors=%d", t, s, f, e}')
  fi
  echo "$name $branch rc=$rc $((SECONDS - start))s $tests dirty=[$dirty]" >> "$LOG/summary.txt"
  if ! { git -C "$WT" reset -q --hard && git -C "$WT" clean -qffd; } >> "$LOG/$name.log" 2>&1; then
    echo "$name $branch cleanup-failed" >> "$LOG/summary.txt"
    failed=$((failed + 1))
  fi
}

# Example (Gradle; `:test` keeps the filter off subproject test tasks):
# JUNIT_DIR=backend/build/test-results/test
# layer A1 feat/101-foo backend ./gradlew --console=plain compileTestKotlin detekt :test --tests '*FooTest'
# layer A2 feat/102-bar backend ./gradlew --console=plain compileTestKotlin detekt test

echo "DONE failed=$failed" >> "$LOG/summary.txt"
[ "$failed" -eq 0 ]
