#!/bin/bash
# バックアップした秘密鍵を WSL の gpg に取り込む。install.sh からは実行されない手動用スクリプト。
# 使い方: ./scripts/gpg_import_key.sh <エクスポートした秘密鍵ファイル>
#
# 取り込む前にフィンガープリントを確認し、別の鍵なら何も変更せずに終了する。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

key_file="${1:-}"
if [ -z "$key_file" ] || [ ! -f "$key_file" ]; then
  warn "使い方: $0 <エクスポートした秘密鍵ファイル>"
  exit 2
fi

fingerprint="$(gpg --show-keys --with-colons "$key_file" | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "$fingerprint" != "$GPG_SIGNING_FPR" ]; then
  warn "フィンガープリントが一致しません: ${fingerprint:-読み取れません} (期待値: $GPG_SIGNING_FPR)"
  exit 1
fi

# パスフレーズの入力に端末が必要
GPG_TTY="$(tty)" && export GPG_TTY

gpg --import "$key_file" || exit 1
echo "$GPG_SIGNING_FPR:6:" | gpg --import-ownertrust || exit 1

if ! gpg --list-secret-keys "$GPG_SIGNING_FPR" >/dev/null; then
  warn "取り込み後に秘密鍵を確認できませんでした"
  exit 1
fi
log "鍵を取り込みました。署名を確認: echo test | gpg -u $GPG_SIGNING_FPR --clearsign >/dev/null"
