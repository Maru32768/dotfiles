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

# 隔離するプロファイル。agent と research は同じ隔離の上に立ち、管理設定と起動スクリプトが違う (docs/research.md)。
# uid は普段のユーザー (1000) とも互いとも分ける。共有された場所のファイルの所有者と重ならないように。
# research の通信の制限は uid 2100 に効くので、ほかで 2100 を使わない (provision/research/firewall.sh)
declare -A isolated_uid=([agent]=2000 [research]=2100)
# wsl.conf の [boot] command。起動のたびに root で動く
declare -A boot_command=([agent]=/usr/local/sbin/agent-isolate-mounts [research]=/usr/local/sbin/research-boot)

if [ -n "${isolated_uid[$profile]:-}" ]; then
  # sudo なし
  if ! id "$user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash --uid "${isolated_uid[$profile]}" "$user"
  fi
  # Claude はここで動かす。ホームで動かすと、サンドボックスの中からホーム全体に書けてしまう
  install -d -o "$user" -g "$user" "/home/$user/work"

  install -d -o root -g root -m 755 /etc/claude-code
  install -o root -g root -m 644 "$here/$profile/managed-settings.json" /etc/claude-code/managed-settings.json
  # 固定する Claude Code のバージョンと、共有のマウントの外し方は agent と同じ
  install -o root -g root -m 644 "$here/agent/claude-version" /etc/claude-code/claude-version
  install -o root -g root -m 755 "$here/agent/isolate-mounts.sh" /usr/local/sbin/agent-isolate-mounts
  install -o root -g root -m 755 "$here/$profile/$profile-claude.sh" "/usr/local/bin/$profile-claude"
  # verify-isolation.sh はこれを読んで、プロファイルごとの期待で調べる
  printf '%s\n' "$profile" >/etc/claude-code/isolation-profile
  chmod 644 /etc/claude-code/isolation-profile

  if [ "$profile" = research ]; then
    # nftables.service が読む既定の /etc/nftables.conf は flush ruleset で始まる。ネットワークの名前空間は
    # 全インスタンスで共有なので、動けばほかのインスタンス (Docker など) のルールまで消える。入れる前に止めておく
    mkdir -p /etc/systemd/system
    ln -sf /dev/null /etc/systemd/system/nftables.service
    apt-get install -y -q --no-install-recommends nftables
    install -o root -g root -m 755 "$here/research/firewall.sh" /usr/local/sbin/research-firewall
    install -o root -g root -m 755 "$here/research/boot.sh" /usr/local/sbin/research-boot
  fi

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
command=${boot_command[$profile]}

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
