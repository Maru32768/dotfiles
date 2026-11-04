#!/bin/bash
# 追加の CLI ツール。go / mise 等のランタイムが入っている前提 (001_lang_runtimes.sh の後に実行)。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# 自分の PATH に go/bin, cargo/bin 等を通す (このスクリプト実行中だけ有効)
export PATH="/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"

if has_cmd go; then
  has_cmd ghq || { log "ghq をインストール"; go install github.com/x-motemen/ghq@latest; }
  has_cmd goimports || { log "goimports をインストール"; go install golang.org/x/tools/cmd/goimports@latest; }
else
  warn "go が見つからないため ghq/goimports をスキップします"
fi

if ! has_cmd aws; then
  log "AWS CLI v2 をインストール"
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/awscliv2.zip /tmp/aws
fi

if [ ! -x "$HOME/.local/bin/yt-dlp" ]; then
  log "yt-dlp をインストール"
  mkdir -p "$HOME/.local/bin"
  curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o "$HOME/.local/bin/yt-dlp"
  chmod +x "$HOME/.local/bin/yt-dlp"
fi

if ! has_cmd claude; then
  log "Claude Code CLI をインストール"
  curl -fsSL https://claude.ai/install.sh | bash
fi

if has_cmd npm; then
  npm ls -g @openai/codex --depth=0 >/dev/null 2>&1 || { log "Codex CLI をインストール"; npm install -g @openai/codex; }
else
  warn "npm が見つからないため Codex CLI をスキップします (先に mise で node を入れてください: mise use -g node@lts)"
fi
