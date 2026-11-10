#!/bin/bash
# 環境を作らずにできる検査をまとめて実行する。手元でも CI でも同じものが動く。
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
cd "$root" || exit 1

# CI 専用のツール。普段の環境には入れないので mise.lock には載せない
GITLEAKS_VERSION="8.30.1"
ACTIONLINT_VERSION="1.7.12"

failures=0
section() {
  printf '\n==> %s\n' "$1"
  shift
  if ! "$@"; then
    printf 'FAIL 上の検査\n'
    failures=$((failures + 1))
  fi
}

# 追跡前の新しいファイルも対象にし、削除済みのものは除く
repo_files() {
  git ls-files -co --exclude-standard "$@" | while IFS= read -r file; do
    [ -e "$file" ] && printf '%s\n' "$file"
  done
}

run_shellcheck() {
  repo_files '*.sh' 'home/private_dot_gnupg/modify_gpg-agent.conf' | xargs shellcheck -s bash
}

run_go() {
  (cd home/.hooks-src/block-signing-bypass && go vet ./... && go test ./...)
}

section "shellcheck" run_shellcheck
section "フックのテスト" run_go
section "bws-run のテスト" bash tests/ci/bws-run-test.sh
section "不変条件" bash tests/ci/invariants.sh
section "chezmoi のレンダリング" bash tests/ci/render.sh
section "秘密情報の検出 (履歴すべて)" mise exec "gitleaks@$GITLEAKS_VERSION" -- gitleaks git --redact --no-banner .
section "workflow の検査" mise exec "aqua:rhysd/actionlint@$ACTIONLINT_VERSION" -- actionlint

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の検査が失敗しました\n' "$failures"
  exit 1
fi
printf '\nすべての検査に通りました\n'
