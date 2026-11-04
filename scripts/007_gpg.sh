#!/bin/bash
# WSL 側 gpg-agent のパスフレーズキャッシュ時間を設定し、署名用の鍵があるか確認する。
# 秘密鍵そのものは扱わない。取り込みは scripts/gpg_import_key.sh を手動で実行する (docs/gpg.md)。
#
# gpg-agent.conf は symlink にせず、該当行だけを書き換える。
# JetBrains IDE が同じファイルに pinentry-program を書き込むため。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GNUPG_DIR="${GNUPGHOME:-$HOME/.gnupg}"
AGENT_CONF="$GNUPG_DIR/gpg-agent.conf"
CACHE_TTL_SECONDS="${GPG_CACHE_TTL_SECONDS:-28800}" # 8時間

set_agent_option() {
  local key="$1" value="$2"
  if grep -q "^$key " "$AGENT_CONF"; then
    sed -i "s/^$key .*/$key $value/" "$AGENT_CONF"
  else
    echo "$key $value" >>"$AGENT_CONF"
  fi
}

if ! has_cmd gpg; then
  warn "gpg が見つからないためスキップします"
  exit 0
fi

mkdir -p "$GNUPG_DIR"
chmod 700 "$GNUPG_DIR"
touch "$AGENT_CONF"

before="$(cat "$AGENT_CONF")"
set_agent_option default-cache-ttl "$CACHE_TTL_SECONDS"
set_agent_option max-cache-ttl "$CACHE_TTL_SECONDS"

if [ "$before" != "$(cat "$AGENT_CONF")" ]; then
  log "gpg-agent のキャッシュ時間を ${CACHE_TTL_SECONDS} 秒に設定しました"
  # 再読み込みするとキャッシュ済みのパスフレーズは消える
  gpg-connect-agent reloadagent /bye >/dev/null || warn "gpg-agent を再読み込みできませんでした"
fi

if ! gpg --list-secret-keys "$GPG_SIGNING_FPR" >/dev/null 2>&1; then
  warn "署名用の秘密鍵がありません。docs/gpg.md の手順で取り込んでください"
fi
