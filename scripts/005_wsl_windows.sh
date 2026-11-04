#!/bin/bash
# WSL <-> Windows 連携設定。WSL 上でのみ実行する。
# ssh / git 設定は Windows 側を正としてそこに集約し、WSL からはシンボリックリンクで参照する
# (Windows の Git / GPG から見えるようにするため)。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! is_wsl; then
  log "WSL 環境ではないためスキップします"
  exit 0
fi

has_cmd wslvar || sudo apt install -y wslu
WINHOME="$(wslpath "$(wslvar USERPROFILE)")"

# WSL 側に実体がある場合だけ Windows 側へ移行し、最終的に symlink にする。
# 既に symlink なら何もしない。WSL 側に実体が無く Windows 側にだけ実体がある
# (＝WSL を作り直しただけ) 場合はそのまま symlink するだけで済む。
migrate_to_windows() {
  local wsl_target="$1" win_path="$2"

  if [ -L "$wsl_target" ] && [ "$(readlink "$wsl_target")" = "$win_path" ]; then
    return 0
  fi

  if [ -e "$wsl_target" ] && [ ! -L "$wsl_target" ]; then
    if [ -e "$win_path" ]; then
      mv "$win_path" "${win_path}.bak.$(date +%s)"
    fi
    cp -r "$wsl_target" "$win_path"
    mv "$wsl_target" "${wsl_target}.bak.$(date +%s)"
  elif [ -L "$wsl_target" ]; then
    rm "$wsl_target"
  fi

  if [ ! -e "$win_path" ]; then
    warn "$win_path が存在しません。Windows 側で ssh key / git 設定を用意してから再実行してください"
    return 1
  fi

  ln -s "$win_path" "$wsl_target"
  log "linked $wsl_target -> $win_path"
}

migrate_to_windows "$HOME/.ssh" "$WINHOME/.ssh"
migrate_to_windows "$HOME/.config/git" "$WINHOME/.config/git"
migrate_to_windows "$HOME/.gitconfig" "$WINHOME/.gitconfig"

# IdeaVim (JetBrains 本体は Windows 側で動くため、dotfiles の内容を Windows 側へコピーする。
# symlink ではなく cp なのは、Windows 側アプリから WSL 側パスへの symlink 解決が
# 環境によって不安定なため)
log "$WINHOME/.ideavimrc に IdeaVim 設定をコピー"
cp "$DOTFILES_DIR/idea/.ideavimrc" "$WINHOME/.ideavimrc"

# 利便性のための symlink: winHome (Windowsユーザーフォルダ) と Desktop
link "$WINHOME" "$HOME/winHome"

# 実体の Desktop は /mnt/f/Desktop (Fドライブ)。まず / 直下に symlink し (sudo が必要)、
# ~/Desktop はその / 直下の symlink を参照する2段構成。
if [ -d /mnt/f/Desktop ]; then
  if [ -L /Desktop ]; then
    if [ "$(readlink /Desktop)" != "/mnt/f/Desktop" ]; then
      sudo ln -sfn /mnt/f/Desktop /Desktop
      log "/Desktop -> /mnt/f/Desktop に更新"
    fi
  elif [ -e /Desktop ]; then
    warn "/Desktop が symlink ではない実体として存在するためスキップします (手動で確認してください)"
  else
    sudo ln -s /mnt/f/Desktop /Desktop
    log "/Desktop -> /mnt/f/Desktop を作成"
  fi
  [ -L /Desktop ] && link "/Desktop" "$HOME/Desktop"
else
  warn "/mnt/f/Desktop が見つからないため Desktop の symlink 作成をスキップします"
fi

if ! grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
  log "/etc/wsl.conf に automount/systemd 設定を追加"
  sudo tee -a /etc/wsl.conf >/dev/null <<'EOF'

[automount]
options = "metadata"

[boot]
systemd = true
EOF
fi
