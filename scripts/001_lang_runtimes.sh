#!/bin/bash
# 言語ランタイム管理ツール本体のインストール。
# node/java/sbt/terraform 等の具体バージョンはここでは入れない
# (mise でプロジェクトごとに入れる運用のため)。
# Node は Volta ではなく mise に一本化、Java/sbt も SDKMAN ではなく mise に一本化する方針。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! has_cmd rustc; then
  log "rustup をインストール"
  curl https://sh.rustup.rs -sSf -o /tmp/rustup.rs
  sh /tmp/rustup.rs -y
  rm -f /tmp/rustup.rs
fi

if ! has_cmd go; then
  log "Go をインストール"
  GO_VERSION="$(curl -fsSL https://go.dev/VERSION?m=text | head -1)"
  curl -L "https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
fi

if ! has_cmd deno; then
  log "Deno をインストール"
  curl -fsSL https://deno.land/install.sh | sh
fi

if [ ! -x "$HOME/.bun/bin/bun" ]; then
  log "Bun をインストール"
  curl -fsSL https://bun.sh/install | bash
fi

if [ ! -x "$HOME/.local/bin/mise" ]; then
  log "mise をインストール"
  curl https://mise.run | sh
fi

if ! has_cmd uv; then
  log "uv (Python) をインストール"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
