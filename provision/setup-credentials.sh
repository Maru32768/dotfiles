#!/bin/bash
# 対話が必要な資格情報の設定。環境を作った後に、普段の端末から実行する。
# 使い方: setup-credentials.sh [エクスポートした GPG 秘密鍵ファイル]
#   WSL: ファイルを渡さなければ、Windows 側の gpg から取り込む。
#   desktop (WSL ではない PC): この PC 専用の署名鍵を作り、chezmoi の signingKey にする (docs/desktop.md)。
#   mac: desktop と同じく PC 専用の署名鍵を作る。SSH キーは macOS の ssh-agent と Keychain で扱う (docs/mac.md)。
set -euo pipefail

GPG_FPR="7AF93B4735CF2AAC930EF5CD78324D99D34D3111"
WINDOWS_GPG="/mnt/c/Program Files/Git/usr/bin/gpg.exe"
SSH_KEY="$HOME/.ssh/github"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GPG_TTY="$(tty)" && export GPG_TTY

export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
data="$(cd "$HOME" && chezmoi data --format json)"
host="$(jq -r '.host // "wsl"' <<<"$data")"

if [ "$host" = mac ]; then
  # 鍵の uid は GitHub で公開され、仕事の PC のホスト名は社内の名前のことがあるので、ホスト名を入れない
  label="$(jq -r 'if .work then "work-mac" else "mac" end' <<<"$data")"
  ssh_comment="$(jq -r .name <<<"$data") ($label)"
else
  label="$(hostname)"
  ssh_comment="$(id -un)@$(hostname)"
  SSH_AUTH_SOCK="$(gpgconf --list-dirs agent-ssh-socket)"
  export SSH_AUTH_SOCK
fi

if [ "$host" = desktop ] || [ "$host" = mac ]; then
  key="$(jq -r '.signingKey // ""' <<<"$data")"
  if [ -z "$key" ] || ! gpg --list-secret-keys "$key" >/dev/null 2>&1; then
    echo "==> この PC 専用の GPG 署名鍵を作ります (ポップアップでパスフレーズを聞かれます)"
    # GitHub はメールアドレスで鍵とコミットを結びつける。PC の名前はコメントに入れて、ほかの PC の鍵と見分ける
    uid="$(jq -r --arg label "$label" '"\(.name) (\($label)) <\(.email)>"' <<<"$data")"
    fpr="$(gpg --status-fd 1 --quick-generate-key "$uid" ed25519 sign never | awk '$2 == "KEY_CREATED" { print $4 }')"
    [ -n "$fpr" ] || { echo "鍵を作れませんでした" >&2; exit 1; }
    # op-run はトークンを署名の鍵あてに暗号化するので、暗号化の副鍵も要る。mac では op-run を使わない
    if [ "$host" = desktop ]; then
      gpg --quick-add-key "$fpr" cv25519 encr never
    fi
    key="${fpr: -16}"
    (cd "$HOME" && DOTFILES_SIGNING_KEY="$key" chezmoi init --no-tty && chezmoi apply --no-tty "$HOME/.gitconfig")
    echo "==> 次の公開鍵を https://github.com/settings/gpg/new に登録してください"
    gpg --armor --export "$key"
  fi
elif ! gpg --list-secret-keys "$GPG_FPR" >/dev/null 2>&1; then
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
  ssh-keygen -t ed25519 -f "$SSH_KEY" -C "$ssh_comment"
fi

if ! ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$SSH_KEY.pub" | awk '{print $2}')"; then
  if [ "$host" = mac ]; then
    echo "==> SSH キーを ssh-agent に登録し、パスフレーズを Keychain に保存します"
    ssh-add --apple-use-keychain "$SSH_KEY"
  else
    echo "==> SSH キーを gpg-agent に登録します (ポップアップでパスフレーズを聞かれます)"
    # SSH の要求には表示先の情報が付かないので、今の表示先を gpg-agent に伝える
    gpg-connect-agent updatestartuptty /bye >/dev/null
    ssh-add "$SSH_KEY"
  fi
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
