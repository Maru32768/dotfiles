#!/bin/bash
# このリポジトリを使って WSL(Ubuntu) の開発環境を再現するためのエントリーポイント。
# scripts/ 以下を番号順に実行する。
#
# 個別のカテゴリだけ再実行したい場合は該当スクリプトを直接実行すればよい (各スクリプトは冪等):
#   ./scripts/001_lang_runtimes.sh
#
# scripts/ 内の番号は 000, 001, 002... の連番。途中に挿入したくなったら以降の番号を
# ずらしてリネームする (3桁ゼロ埋めなので 999 まではソート順が壊れない)。
#
# 対象外(意図的に除外。必要なら手動で入れる): mysql-server, postgresql, haskell-stack,
# qemu-kvm/virt-manager, ngrok, hashicorp系(terraform等), VSCode/JetBrains本体のインストール、
# neovim, Volta, SDKMAN (いずれも使っていない/mise に一本化する方針のため未導入)、
# 各言語ランタイムの具体バージョン(node/java/terraform等 個別プロジェクトで mise により導入する想定)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

for script in scripts/[0-9][0-9][0-9]_*.sh; do
  echo
  echo "########## $script ##########"
  bash "$script"
done

echo
echo "install.sh が完了しました。新しいシェルを開くか 'exec bash -l' で反映してください。"
echo "docker グループの反映にはログインし直しが必要です。"
