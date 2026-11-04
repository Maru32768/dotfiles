#!/bin/bash
# apt リポジトリの追加と、開発に必要な基本パッケージのインストール。
# 対象外(意図的に除外): mysql-server, postgresql, haskell-stack, qemu-kvm/virt-manager,
# ngrok, hashicorp 系(terraform 等), VSCode/JetBrains 本体
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "apt を更新して前提パッケージを導入"
sudo apt update
sudo apt install -y software-properties-common ca-certificates curl gnupg lsb-release unzip

log "PPA / 外部リポジトリを追加"
sudo add-apt-repository -y ppa:git-core/ppa

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update

log "パッケージをインストール"
sudo apt install -y \
  build-essential git tmux jq \
  python-is-python3 python3-dev libncurses5-dev \
  docker.io docker-compose-plugin docker-buildx-plugin

sudo usermod -aG docker "$(whoami)" || true
log "docker グループへの追加はログインし直すまで反映されません"

if is_wsl; then
  has_cmd wslvar || sudo apt install -y wslu
fi
