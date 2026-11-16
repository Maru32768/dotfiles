#!/bin/bash
# provision/setup-credentials.sh を、偽の gpg、ssh-keygen、ssh-add、chezmoi などで試す。本物の鍵、
# エージェント、Keychain には触れない。偽のコマンドは、引数と SSH_AUTH_SOCK と DOTFILES_SIGNING_KEY を記録する。
# テストを動かしている bash で動かすので、mac の /bin/bash (3.2) で動かせば、その読み違いも見つかる
# 偽のコマンドの本文は、そのコマンドが動くときに展開するので、SC2016 を抑える
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/provision/setup-credentials.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
# 使い方: has <名前> <記録の 1 行と完全に一致する文字列>
has() { if grep -qxF -- "$2" "$log"; then pass "$1"; else fail "$1 (無い: $2)"; fi; }
# 使い方: hasnt <名前> <記録のどこにも含まれない文字列>
hasnt() { if grep -qF -- "$2" "$log"; then fail "$1 (ある: $2)"; else pass "$1"; fi; }

bin="$work/bin"
mkdir -p "$bin"
for tool in jq awk cat mkdir dirname grep sed rm mktemp basename tr head env; do
  path="$(command -v "$tool")" || { fail "$tool が無い"; exit 1; }
  ln -s "$path" "$bin/$tool"
done

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$bin/$1"; chmod +x "$bin/$1"; }
record='printf "%s|%s|SOCK=%s|KEY=%s\n" "$(basename "$0")" "$*" "${SSH_AUTH_SOCK-unset}" "${DOTFILES_SIGNING_KEY-unset}" >>"$FAKE_LOG"'
stub chezmoi "$record"'
[ "$1" = data ] && printf "%s\n" "$FAKE_DATA"
exit 0'
stub gpg "$record"'
case " $* " in
  *" --list-secret-keys "*) exit "$FAKE_GPG_LIST" ;;
  *" --quick-generate-key "*) echo "[GNUPG:] KEY_CREATED P 0123456789ABCDEF0123456789ABCDEF89ABCDEF" ;;
  *" --export "*) echo PUBKEY ;;
esac
exit 0'
stub gpgconf "$record"'
echo /fake/gpg-agent.ssh'
stub gpg-connect-agent "$record"
stub hostname 'echo secret-host'
stub id 'echo secret-user'
stub tty 'echo /dev/ttys999'
stub ssh-keygen "$record"'
if [ "$1" = -lf ]; then echo "256 SHA256:FAKEFP c (ED25519)"; exit 0; fi
while [ $# -gt 0 ]; do case "$1" in -f) file="$2"; shift ;; -C) comment="$2"; shift ;; esac; shift; done
echo key >"$file"; echo "ssh-ed25519 AAAA $comment" >"$file.pub"'
stub ssh-add "$record"'
[ "$1" = -l ] && exit 1
exit 0'
stub ssh 'echo "Hi! You have successfully authenticated"'
stub git "$record"

# 使い方: scenario <名前> <host> <work (true か false)> <gpg --list-secret-keys の終了コード>
# SSH_AUTH_SOCK は、mac の launchd の agent に見立てた値で始める
scenario() {
  local name="$1" host="$2" work_pc="$3" has_key="$4" rc
  log="$work/$name.log"
  : >"$log"
  mkdir -p "$work/$name-home"
  env -i HOME="$work/$name-home" PATH="$bin" LANG=en_US.UTF-8 SSH_AUTH_SOCK=/launchd/agent FAKE_LOG="$log" FAKE_GPG_LIST="$has_key" \
    FAKE_DATA="{\"host\":\"$host\",\"name\":\"Maru32768\",\"email\":\"maru32768@gmail.com\",\"signingKey\":\"\",\"work\":$work_pc}" \
    "$BASH" "$script" >"$work/$name.out" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then pass "$name: 最後まで動く"; else fail "$name: 終了コード $rc: $(tail -3 "$work/$name.out")"; fi
}

# 鍵の uid は GitHub で公開されるので、mac ではホスト名もユーザー名も入れない
scenario mac mac false 1
has "mac: uid は名前 (mac) とメールアドレス" "gpg|--status-fd 1 --quick-generate-key Maru32768 (mac) <maru32768@gmail.com> ed25519 sign never|SOCK=/launchd/agent|KEY=unset"
hasnt "mac: ホスト名をどこにも渡さない" "secret-host"
hasnt "mac: ユーザー名をどこにも渡さない" "secret-user"
hasnt "mac: 暗号化の副鍵を作らない" "--quick-add-key"
has "mac: 作った鍵を chezmoi の signingKey に渡す" "chezmoi|init --no-tty|SOCK=/launchd/agent|KEY=89ABCDEF89ABCDEF"
has "mac: SSH キーのコメントは名前 (mac)" "ssh-keygen|-t ed25519 -f $work/mac-home/.ssh/github -C Maru32768 (mac)|SOCK=/launchd/agent|KEY=unset"
has "mac: SSH キーを launchd の agent に入れ、パスフレーズを Keychain に保存する" "ssh-add|--apple-use-keychain $work/mac-home/.ssh/github|SOCK=/launchd/agent|KEY=unset"
hasnt "mac: gpg-agent を SSH に使わない" "gpg-connect-agent"
hasnt "mac: SSH_AUTH_SOCK を gpg-agent に向けない" "SOCK=/fake/gpg-agent.ssh"

scenario mac-work mac true 1
has "mac (work): uid は名前 (work-mac) とメールアドレス" "gpg|--status-fd 1 --quick-generate-key Maru32768 (work-mac) <maru32768@gmail.com> ed25519 sign never|SOCK=/launchd/agent|KEY=unset"
has "mac (work): SSH キーのコメントは名前 (work-mac)" "ssh-keygen|-t ed25519 -f $work/mac-work-home/.ssh/github -C Maru32768 (work-mac)|SOCK=/launchd/agent|KEY=unset"

scenario desktop desktop false 1
has "desktop: uid にホスト名を入れる" "gpg|--status-fd 1 --quick-generate-key Maru32768 (secret-host) <maru32768@gmail.com> ed25519 sign never|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "desktop: op-run のための暗号化の副鍵を作る" "gpg|--quick-add-key 0123456789ABCDEF0123456789ABCDEF89ABCDEF cv25519 encr never|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "desktop: SSH キーのコメントはユーザー名@ホスト名" "ssh-keygen|-t ed25519 -f $work/desktop-home/.ssh/github -C secret-user@secret-host|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "desktop: gpg-agent に表示先を伝える" "gpg-connect-agent|updatestartuptty /bye|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "desktop: SSH キーを gpg-agent に入れる" "ssh-add|$work/desktop-home/.ssh/github|SOCK=/fake/gpg-agent.ssh|KEY=unset"

scenario wsl wsl false 0
hasnt "wsl: 鍵を作らない" "--quick-generate-key"
has "wsl: Windows と同じ鍵があるかを見る" "gpg|--list-secret-keys 7AF93B4735CF2AAC930EF5CD78324D99D34D3111|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "wsl: SSH キーのコメントはユーザー名@ホスト名" "ssh-keygen|-t ed25519 -f $work/wsl-home/.ssh/github -C secret-user@secret-host|SOCK=/fake/gpg-agent.ssh|KEY=unset"
has "wsl: SSH キーを gpg-agent に入れる" "ssh-add|$work/wsl-home/.ssh/github|SOCK=/fake/gpg-agent.ssh|KEY=unset"

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
