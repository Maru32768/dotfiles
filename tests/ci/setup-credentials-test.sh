#!/bin/bash
# provision/setup-credentials.sh を、偽の gpg、ssh-keygen、ssh-add、chezmoi などで試す。本物の鍵、
# エージェント、Keychain には触れない。偽の gpg、ssh、chezmoi、git などは、引数と DOTFILES_SIGNING_KEY と SSH_AUTH_SOCK を記録する。
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
# 使い方: has <名前> <記録のどれかの行の先頭と一致する文字列>
has() { if awk -v want="$2" 'index($0, want) == 1 { found = 1 } END { exit !found }' "$log"; then pass "$1"; else fail "$1 (無い: $2)"; fi; }
# 使い方: hasnt <名前> <記録のどこにも含まれない文字列>
hasnt() { if grep -qF -- "$2" "$log"; then fail "$1 (ある: $2)"; else pass "$1"; fi; }

bin="$work/bin"
mkdir -p "$bin"
# mise の shim は、偽の HOME と PATH の中ではどの版を使うか決められず、失敗するか自分を呼び続ける
PATH="$(printf %s "$PATH" | tr : '\n' | grep -v '/mise/shims$' | paste -sd: -)"
for tool in jq awk cat mkdir dirname grep sed rm mktemp basename tr head env; do
  path="$(command -v "$tool")" || { fail "$tool が無い"; exit 1; }
  ln -s "$path" "$bin/$tool"
done

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$bin/$1"; chmod +x "$bin/$1"; }
record='printf "%s|%s|KEY=%s|SOCK=%s\n" "$(basename "$0")" "$*" "${DOTFILES_SIGNING_KEY-unset}" "${SSH_AUTH_SOCK-unset}" >>"$FAKE_LOG"'
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
if [ "$1" = -lf ]; then [ -f "$2" ] || exit 255; echo "256 SHA256:FAKEFP c (ED25519)"; exit 0; fi
while [ $# -gt 0 ]; do case "$1" in -f) file="$2"; shift ;; -C) comment="$2"; shift ;; esac; shift; done
echo key >"$file"; echo "ssh-ed25519 AAAA $comment" >"$file.pub"'
stub ssh-add "$record"'
if [ "$1" = -l ]; then [ -n "$FAKE_AGENT" ] || exit 1; echo "$FAKE_AGENT"; fi
exit 0'
# GitHub は返事を標準エラーに出す
stub ssh "$record"'
echo "$FAKE_SSH" >&2'
stub git "$record"

# 使い方: scenario <名前> <host> [キー=値...]。キーと既定値は次のとおり
#   home=<名前>: 同じホームで続けて動かすと、前の実行で作った SSH キーが残る
#   work=false、signing_key= (chezmoi のデータ)、gpg_list=1 (gpg --list-secret-keys の終了コード)
#   agent= (ssh-add -l の出力。空なら agent に鍵が無い)、ssh=<認証に成功した返事> (ssh -T git@github.com の出力)
#   fails= (空でなければ、失敗で終わることを期待する)
# SSH_AUTH_SOCK は、mac の launchd の agent に見立てた値で始める
scenario() {
  local name="$1" host="$2" home="$1" work_pc=false signing_key="" gpg_list=1 agent="" fails="" kv rc
  local ssh_reply="Hi! You have successfully authenticated, but GitHub does not provide shell access."
  shift 2
  for kv in "$@"; do
    case "$kv" in
      home=*) home="${kv#*=}" ;;
      work=*) work_pc="${kv#*=}" ;;
      signing_key=*) signing_key="${kv#*=}" ;;
      gpg_list=*) gpg_list="${kv#*=}" ;;
      agent=*) agent="${kv#*=}" ;;
      ssh=*) ssh_reply="${kv#*=}" ;;
      fails=*) fails="${kv#*=}" ;;
      *) fail "$name: 知らない引数 $kv"; return ;;
    esac
  done
  home="$work/$home-home"
  log="$work/$name.log"
  : >"$log"
  mkdir -p "$home"
  env -i HOME="$home" PATH="$bin" LANG=en_US.UTF-8 SSH_AUTH_SOCK=/launchd/agent FAKE_LOG="$log" FAKE_GPG_LIST="$gpg_list" FAKE_AGENT="$agent" FAKE_SSH="$ssh_reply" \
    FAKE_DATA="{\"host\":\"$host\",\"name\":\"Maru32768\",\"email\":\"maru32768@gmail.com\",\"signingKey\":\"$signing_key\",\"work\":$work_pc}" \
    "$BASH" "$script" >"$work/$name.out" 2>&1
  rc=$?
  if [ -n "$fails" ]; then
    if [ "$rc" -ne 0 ]; then pass "$name: 失敗で終わる"; else fail "$name: 失敗で終わらない"; fi
  elif [ "$rc" -eq 0 ]; then
    pass "$name: 最後まで動く"
  else
    fail "$name: 終了コード $rc: $(tail -3 "$work/$name.out")"
  fi
}

# 鍵の uid は GitHub で公開されるので、mac ではホスト名もユーザー名も入れない
scenario mac mac
has "mac: uid は名前 (mac) とメールアドレス" "gpg|--status-fd 1 --quick-generate-key Maru32768 (mac) <maru32768@gmail.com> ed25519 sign never|"
hasnt "mac: ホスト名をどこにも渡さない" "secret-host"
hasnt "mac: ユーザー名をどこにも渡さない" "secret-user"
hasnt "mac: 暗号化の副鍵を作らない" "--quick-add-key"
has "mac: 作った鍵を chezmoi の signingKey に渡す" "chezmoi|init --no-tty|KEY=89ABCDEF89ABCDEF|"
has "mac: 作った鍵を .gitconfig に書く" "chezmoi|apply --no-tty $work/mac-home/.gitconfig|"
has "mac: SSH キーのコメントは名前 (mac)" "ssh-keygen|-t ed25519 -f $work/mac-home/.ssh/github -C Maru32768 (mac)|"
has "mac: SSH キーを launchd の agent に入れ、パスフレーズを Keychain に保存する" "ssh-add|--apple-use-keychain $work/mac-home/.ssh/github|KEY=unset|SOCK=/launchd/agent"
hasnt "mac: gpg-agent を SSH に使わない" "gpg-connect-agent"
hasnt "mac: SSH_AUTH_SOCK を gpg-agent に向けない" "SOCK=/fake/gpg-agent.ssh"
has "mac: 作った鍵の公開鍵を表示する" "gpg|--armor --export 89ABCDEF89ABCDEF|"
has "mac: GitHub への接続を確かめ、初めてのときはホストの鍵を受け入れる" "ssh|-o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com|"
has "mac: GitHub に接続できたら、dotfiles の取得先を SSH にする" "git|-C $work/mac-home/dotfiles remote set-url origin git@github.com:Maru32768/dotfiles.git|"

# 公開鍵を GitHub に登録してから、もう一度動かす (docs/mac.md)。鍵も SSH キーも作り直さない
scenario mac-rerun mac home=mac signing_key=89ABCDEF89ABCDEF gpg_list=0 agent="256 SHA256:FAKEFP Maru32768 (mac) (ED25519)"
has "mac (2 回目): signingKey の鍵があるかを見る" "gpg|--list-secret-keys 89ABCDEF89ABCDEF|"
hasnt "mac (2 回目): 鍵を作らない" "--quick-generate-key"
hasnt "mac (2 回目): chezmoi を設定し直さない" "chezmoi|init"
hasnt "mac (2 回目): SSH キーを作らない" "ssh-keygen|-t"
hasnt "mac (2 回目): agent にある SSH キーを入れ直さない" "ssh-add|--apple-use-keychain"
has "mac (2 回目): GitHub に接続できたら、dotfiles の取得先を SSH にする" "git|-C $work/mac-home/dotfiles remote set-url"

# 仕事の Mac のように、agent にほかの鍵だけがあるときは、GitHub の鍵を入れる
scenario mac-other-key mac home=mac signing_key=89ABCDEF89ABCDEF gpg_list=0 agent="256 SHA256:OTHERFP work (ED25519)"
has "mac (ほかの鍵だけの agent): SSH キーを agent に入れる" "ssh-add|--apple-use-keychain $work/mac-home/.ssh/github|"

# 公開鍵が読めないと agent の鍵と照らせないので、入れたことにせずに止まる
mkdir -p "$work/mac-no-pub-home/.ssh" && echo key >"$work/mac-no-pub-home/.ssh/github"
scenario mac-no-pub mac signing_key=89ABCDEF89ABCDEF gpg_list=0 agent="256 SHA256:OTHERFP work (ED25519)" fails=1
hasnt "mac (公開鍵が無い): GitHub への接続まで進まない" "git|"

# signingKey の鍵を失くしたら、作り直す (docs/desktop.md)
scenario mac-key-lost mac signing_key=DEADBEEFDEADBEEF gpg_list=1
has "mac (鍵を失くした): 鍵を作り直す" "gpg|--status-fd 1 --quick-generate-key Maru32768 (mac) <maru32768@gmail.com> ed25519 sign never|"
has "mac (鍵を失くした): 作り直した鍵を chezmoi の signingKey に渡す" "chezmoi|init --no-tty|KEY=89ABCDEF89ABCDEF|"
has "mac (鍵を失くした): 作り直した鍵を .gitconfig に書く" "chezmoi|apply --no-tty $work/mac-key-lost-home/.gitconfig|"

# GitHub に公開鍵をまだ登録していなければ、dotfiles の取得先を変えない
scenario mac-unregistered mac ssh="git@github.com: Permission denied (publickey)."
hasnt "mac (GitHub に未登録): dotfiles の取得先を変えない" "git|"

scenario mac-work mac work=true
has "mac (work): uid は名前 (work-mac) とメールアドレス" "gpg|--status-fd 1 --quick-generate-key Maru32768 (work-mac) <maru32768@gmail.com> ed25519 sign never|"
has "mac (work): SSH キーのコメントは名前 (work-mac)" "ssh-keygen|-t ed25519 -f $work/mac-work-home/.ssh/github -C Maru32768 (work-mac)|"

scenario desktop desktop
has "desktop: uid にホスト名を入れる" "gpg|--status-fd 1 --quick-generate-key Maru32768 (secret-host) <maru32768@gmail.com> ed25519 sign never|"
has "desktop: op-run のための暗号化の副鍵を作る" "gpg|--quick-add-key 0123456789ABCDEF0123456789ABCDEF89ABCDEF cv25519 encr never|"
has "desktop: 作った鍵を chezmoi の signingKey に渡す" "chezmoi|init --no-tty|KEY=89ABCDEF89ABCDEF|"
has "desktop: SSH キーのコメントはユーザー名@ホスト名" "ssh-keygen|-t ed25519 -f $work/desktop-home/.ssh/github -C secret-user@secret-host|"
has "desktop: gpg-agent に表示先を伝える" "gpg-connect-agent|updatestartuptty /bye|KEY=unset|SOCK=/fake/gpg-agent.ssh"
has "desktop: SSH キーを gpg-agent に入れる" "ssh-add|$work/desktop-home/.ssh/github|KEY=unset|SOCK=/fake/gpg-agent.ssh"

scenario desktop-work desktop work=true
has "desktop (work): 仕事の PC でも暗号化の副鍵を作る" "gpg|--quick-add-key 0123456789ABCDEF0123456789ABCDEF89ABCDEF cv25519 encr never|"

scenario wsl wsl gpg_list=0
hasnt "wsl: 鍵を作らない" "--quick-generate-key"
has "wsl: Windows と同じ鍵があるかを見る" "gpg|--list-secret-keys 7AF93B4735CF2AAC930EF5CD78324D99D34D3111|"
has "wsl: SSH キーのコメントはユーザー名@ホスト名" "ssh-keygen|-t ed25519 -f $work/wsl-home/.ssh/github -C secret-user@secret-host|"
has "wsl: gpg-agent に表示先を伝える" "gpg-connect-agent|updatestartuptty /bye|KEY=unset|SOCK=/fake/gpg-agent.ssh"
has "wsl: SSH キーを gpg-agent に入れる" "ssh-add|$work/wsl-home/.ssh/github|KEY=unset|SOCK=/fake/gpg-agent.ssh"

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の問題があります\n' "$failures"
  exit 1
fi
