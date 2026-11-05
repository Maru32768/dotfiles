#!/bin/bash
# root で 1 回実行する: OS パッケージ、ユーザー、wsl.conf。
# 使い方: root.sh <ユーザー名> <packages/apt.txt のパス>
set -euo pipefail

user="$1"
apt_list="$2"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
grep -vE '^(#|$)' "$apt_list" | xargs apt-get install -y -q --no-install-recommends

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
