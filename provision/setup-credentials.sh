#!/bin/bash
# 対話が必要な資格情報の設定。環境を作った後に、普段の端末から実行する。
# 使い方: setup-credentials.sh [エクスポートした GPG 秘密鍵ファイル]
#   ファイルを渡さなければ、Windows 側の gpg から取り込む。
set -euo pipefail

GPG_FPR="7AF93B4735CF2AAC930EF5CD78324D99D34D3111"
WINDOWS_GPG="/mnt/c/Program Files/Git/usr/bin/gpg.exe"
SSH_KEY="$HOME/.ssh/github"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GPG_TTY="$(tty)" && export GPG_TTY
SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
export SSH_AUTH_SOCK

if ! gpg --list-secret-keys "$GPG_FPR" >/dev/null 2>&1; then
  echo "==> GPG 署名鍵を取り込みます"
  if [ -n "${1:-}" ]; then
    bash "$here/gpg_import_key.sh" "$1"
  else
    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT
    "$WINDOWS_GPG" --armor --export-secret-keys "$GPG_FPR" >"$workdir/key.asc"
    bash "$here/gpg_import_key.sh" "$workdir/key.asc"
    rm -rf "$workdir"
    trap - EXIT
  fi
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "==> この環境専用の SSH キーを作ります"
  mkdir -p "$(dirname "$SSH_KEY")"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "$(id -un)@$(hostname)"
fi

if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"; then
  echo "==> SSH キーを gpg-agent に登録します (ポップアップでパスフレーズを聞かれます)"
  # SSH の要求には表示先の情報が付かないので、今の表示先を gpg-agent に伝える
  gpg-connect-agent updatestartuptty /bye >/dev/null
  ssh-add "$SSH_KEY"
fi

# GitHub は認証に成功しても終了コード 1 を返すので、出力で判定する
ssh_output="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)"
if [[ "$ssh_output" == *"successfully authenticated"* ]]; then
  echo "==> GitHub への SSH 接続を確認しました"
  git -C "$HOME/dotfiles" remote set-url origin git@github.com:Maru32768/dotfiles.git 2>/dev/null || true
else
  echo "==> 次の公開鍵を https://github.com/settings/ssh/new に登録して、もう一度実行してください"
  cat "$SSH_KEY.pub"
fi
