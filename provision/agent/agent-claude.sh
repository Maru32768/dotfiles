#!/bin/bash
# agent 環境で Claude を起動する。Windows から lab.ps1 run で呼ばれる。
# 隔離の検査に通らなければ起動しない。
# --setting-sources user: リポジトリの設定 (フックや apiKeyHelper はサンドボックスの外で動く) を読まない。
# --permission-mode acceptEdits: 作業ディレクトリの中の編集だけを確認なしにする。Bash はサンドボックスの中なら確認なしで動く。
set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
# 隔離を確かめたバージョンのまま動かす。更新はインスタンスを作り直して行う (docs/agent.md)
export DISABLE_AUTOUPDATER=1

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "CLAUDE_CODE_OAUTH_TOKEN がありません。Windows から lab.ps1 run で起動してください" >&2
  exit 1
fi

# サンドボックスは作業ディレクトリへの書き込みを許すので、ホームで動かすと ~/.local/bin まで書き換えられる
if [ "$PWD" = "$HOME" ]; then
  echo "ホームでは起動しません。~/work の下で起動してください" >&2
  exit 1
fi

bash "$HOME/dotfiles/tests/verify-isolation.sh" --quiet

# 管理設定の sandbox.filesystem.allowWrite の先。なければサンドボックスの中から作れない
mkdir -p "$HOME/.npm" "$HOME/go/pkg"

exec claude --permission-mode acceptEdits --setting-sources user "$@"
