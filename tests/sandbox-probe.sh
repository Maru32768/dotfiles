#!/bin/bash
# Claude のサンドボックスの中で実行され、外に届くかを試す。verify-isolation.sh から呼ばれる。
# 結果を <出力先> に「REACHED 名前」または「BLOCKED 名前」の形式で書く。
# 届かないのが正しいものが基本で、届くのが正しいものはプロファイルごとに verify-isolation.sh の表で決める。
# info- は開発で使えるかの参考。
# 使い方: sandbox-probe.sh <出力先> <nonce> <ポート (カンマ区切り)> <ゲートウェイ>
set -uo pipefail

out="$1"
nonce="$2"
ports="$3"
gateway="$4"

try() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1 </dev/null; then
    echo "REACHED $name"
  else
    echo "BLOCKED $name"
  fi
}

write_file() { touch "$1" && rm -f "$1"; }
https_get() { curl -sS --max-time 10 -o /dev/null "$@"; }
tcp_connect() { timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2"; }
unix_connect() { [ -S "$1" ] && timeout 3 socat -u OPEN:/dev/null "UNIX-CONNECT:$1"; }
sees_host_init() { [ "$(cat /proc/1/comm)" = systemd ]; }
token_in_env() { [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || [ -n "${ANTHROPIC_API_KEY:-}" ] || [[ "$(env)" == *sk-ant-* ]]; }

# 親から引き継いだファイルディスクリプタにトークンが残っていないこと
token_in_fd() {
  local fd
  for fd in /proc/self/fd/*; do
    case "${fd##*/}" in 0 | 1 | 2) continue ;; esac
    [ -r "$fd" ] || continue
    [[ "$(timeout 1 head -c 256 "$fd" 2>/dev/null | tr -d '\0')" == *sk-ant-* ]] && return 0
  done
  return 1
}

# 開発の作業ができること
git_commit() {
  local repo="$PWD/probe-repo"
  rm -rf "$repo"
  git init -q "$repo" && echo probe >"$repo/file" &&
    git -C "$repo" add file && git -C "$repo" commit -qm probe
}
go_build() {
  local module="$PWD/probe-go"
  mkdir -p "$module" && printf 'module probe\n\ngo 1.20\n' >"$module/go.mod" &&
    printf 'package main\n\nfunc main() {}\n' >"$module/main.go" &&
    (cd "$module" && go build -o /dev/null .)
}
go_get() {
  local module="$PWD/probe-go-get"
  mkdir -p "$module" && printf 'module probe\n\ngo 1.20\n' >"$module/go.mod" &&
    (cd "$module" && timeout 60 go get github.com/pkg/errors@v0.9.1)
}
npm_install() {
  local project="$PWD/probe-npm"
  mkdir -p "$project" && (cd "$project" && npm init -y && npm install --no-audit --no-fund is-odd)
}
write_package_json() { touch package.json && printf '{}\n' >>package.json; }

token_in_proc() {
  local environ
  for environ in /proc/[0-9]*/environ; do
    grep -qaE '(CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)=' "$environ" 2>/dev/null && return 0
  done
  return 1
}

{
  echo "nonce $nonce"

  try sees-host-init sees_host_init
  try write-home write_file "$HOME/.sandbox-probe"
  try write-claude-bin write_file "$HOME/.local/bin/.sandbox-probe"

  try token-env token_in_env
  try token-proc token_in_proc
  try token-fd token_in_fd

  try net-allowed https_get https://github.com
  try net-proxied https_get https://example.com
  try net-direct https_get --noproxy '*' https://example.com
  try net-direct-ip https_get --noproxy '*' --insecure https://1.1.1.1
  try net-anthropic https_get https://api.anthropic.com/

  try work-write write_file "$PWD/.probe-write"
  try work-git-commit git_commit
  try work-git-https timeout 20 git ls-remote https://github.com/Maru32768/dotfiles.git HEAD
  try info-go-build go_build
  try info-go-get go_get
  try info-npm-install npm_install
  try info-write-package-json write_package_json

  # ネットワークはほかのインスタンスや Windows と共有しているので、サンドボックスが頼り
  IFS=, read -ra port_list <<<"$ports"
  for port in "${port_list[@]}"; do
    try "local-port-$port" tcp_connect 127.0.0.1 "$port"
  done
  [ -n "$gateway" ] && try windows-smb tcp_connect "$gateway" 445

  try x11-socket unix_connect /tmp/.X11-unix/X0
  try docker-backend unix_connect /mnt/wsl/docker-desktop/shared-sockets/host-services/backend.sock
} >"$out"
