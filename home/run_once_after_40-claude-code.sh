#!/bin/bash
set -euo pipefail

# agent 環境では provision/root.sh が置いたバージョンに固定する (docs/agent.md)
pin=/etc/claude-code/claude-version
if [ -r "$pin" ]; then
  curl -fsSL https://claude.ai/install.sh | bash -s -- "$(cat "$pin")"
elif [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
