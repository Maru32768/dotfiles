#!/bin/bash
# root で 1 回実行する: OS パッケージ、ユーザー、wsl.conf。
# 使い方: root.sh <ユーザー名> <packages/apt.txt のパス> [プロファイル]
set -euo pipefail

user="$1"
apt_list="$2"
profile="${3:-main}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
grep -vE '^(#|$)' "$apt_list" | xargs apt-get install -y -q --no-install-recommends

if [ "$profile" = agent ]; then
  # sudo なし。uid も普段のユーザー (1000) と分ける。共有された場所のファイルの所有者と重ならないように
  if ! id "$user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --uid 2000 "$user"
  fi
  # Claude はここで動かす。ホームで動かすと、サンドボックスの中からホーム全体に書けてしまう
  install -d -o "$user" -g "$user" "/home/$user/work"

  install -d -o root -g root -m 755 /etc/claude-code
  install -o root -g root -m 644 "$here/agent/managed-settings.json" /etc/claude-code/managed-settings.json
  install -o root -g root -m 644 "$here/agent/claude-version" /etc/claude-code/claude-version
  install -o root -g root -m 755 "$here/agent/isolate-mounts.sh" /usr/local/sbin/agent-isolate-mounts
  install -o root -g root -m 755 "$here/agent/agent-claude.sh" /usr/local/bin/agent-claude

  # /etc/resolv.conf は /mnt/wsl を指す symlink で、WSL が起動のたびに作り直す。
  # /mnt/wsl を外すので、WSL に生成させず実ファイルにする
  # (コンテナでは実ファイルがバインドマウントされていて、消せないし変える必要もない)
  if [ -L /etc/resolv.conf ]; then
    resolv="$(cat /etc/resolv.conf)"
    rm -f /etc/resolv.conf
    printf '%s\n' "$resolv" >/etc/resolv.conf
  fi

  cat >/etc/wsl.conf <<EOF
[boot]
systemd=true
command=/usr/local/sbin/agent-isolate-mounts

[network]
generateResolvConf=false

[user]
default=$user

[automount]
enabled=false
mountFsTab=false

[interop]
enabled=false
appendWindowsPath=false
EOF
else
  if ! id "$user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --groups sudo "$user"
  fi

  cat >/etc/wsl.conf <<EOF
[boot]
systemd=true

[user]
default=$user

[automount]
options="metadata"
EOF
fi
