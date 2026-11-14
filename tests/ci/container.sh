#!/bin/bash
# 使い捨てのコンテナで環境を作り、doctor と再適用まで確かめる。作業ツリーの内容を使う。
# コンテナには systemd も WSL もないので、wsl.conf の効果や隔離は確かめられない (lab.ps1 で確かめる)。
# research の通信の制限だけは、コンテナが自分のネットワークの名前空間を持つので、読み込んで試す。
#
# 使い方: container.sh <main|agent|research>
# shellcheck disable=SC2016
set -uo pipefail

# home: ユーザーのファイルを作る chezmoi のプロファイル。research は agent のものを使う
# run_options: research の nft には CAP_NET_ADMIN が要る。効くのはこのコンテナの名前空間だけ
profile="${1:?使い方: container.sh <main|agent|research>}"
run_options=()
case "$profile" in
  main) user=maru home=main ;;
  agent) user=agent home=agent ;;
  research) user=research home=agent run_options=(--cap-add NET_ADMIN) ;;
  *) echo "不明なプロファイル: $profile" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
image="ubuntu:26.04"
name="dotfiles-ci-$profile-$$"

user_log="$(mktemp)"

cleanup() {
  docker rm -f "$name" >/dev/null 2>&1
  rm -f "$user_log"
}
trap cleanup EXIT

# 使い方: as_user <スクリプト> [引数...]
as_user() { docker exec -u "$user" -w "/home/$user" -e "HOME=/home/$user" "$name" bash -lc "$1" bash "${@:2}"; }
step() { printf '\n==> %s\n' "$1"; }
# 使い方: launcher_want <検査の名前> <[[ ]] の式>
launcher_want() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi; }

docker run -d "${run_options[@]}" --name "$name" "$image" sleep 7200 >/dev/null || exit 1

step "作業ツリーをコピー"
# 資格情報に触れないよう、マウントせずに追跡対象のファイルだけを渡す
(cd "$root" && git ls-files -co --exclude-standard | while IFS= read -r file; do
  [ -e "$file" ] && printf '%s\n' "$file"
done | tar -cf - -T -) | docker exec -i "$name" sh -c 'mkdir -p /tmp/src && tar -xf - -C /tmp/src && chmod -R a+rX /tmp/src' || exit 1

step "root.sh"
docker exec "$name" bash /tmp/src/provision/root.sh "$user" /tmp/src/packages/apt.txt "$profile" || exit 1

step "user.sh"
docker exec -u "$user" -w "/home/$user" -e "HOME=/home/$user" "$name" bash /tmp/src/provision/user.sh "$home" /tmp/src 2>&1 | tee "$user_log" || exit 1

failures=0
# 導入のスクリプトは構築を止めないので、ここで警告を拾う
if grep -q "警告がありました" "$user_log"; then
  echo "FAIL user.sh が警告を出した"
  failures=$((failures + 1))
fi
if [ "$profile" = main ]; then
  step "doctor.sh"
  # TODO (資格情報の登録) は失敗に数えない
  as_user 'bash ~/dotfiles/tests/doctor.sh --container' || failures=$((failures + 1))
else
  step "$profile の確認"
  as_user '
    set -u
    profile="$1"
    failed=0
    want() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi; }
    want "Claude Code が固定したバージョン" "[ \"\$(claude --version | cut -d\" \" -f1)\" = \"\$(cat /etc/claude-code/claude-version)\" ]"
    want "ホームのプロファイルが agent" "chezmoi data --format json | jq -e \".profile == \\\"agent\\\"\""
    want "隔離のプロファイルの印が $profile" "[ \"\$(cat /etc/claude-code/isolation-profile)\" = \"\$profile\" ]"
    want "署名の鍵を設定していない" "! git config --global user.signingkey"
    want ".claude の共通設定がない" "[ ! -e ~/.claude/settings.json ]"
    want "フックをビルドしていない" "[ ! -e ~/.claude/hooks/block-signing-bypass ]"
    want "管理設定が root 所有" "[ \"\$(stat -c %U /etc/claude-code/managed-settings.json)\" = root ]"
    want "管理設定で更新を止めている" "jq -e \".env.DISABLE_AUTOUPDATER == \\\"1\\\"\" /etc/claude-code/managed-settings.json"
    want "起動スクリプトが root 所有" "[ \"\$(stat -c %U /usr/local/bin/\$profile-claude)\" = root ]"
    exit "$failed"
  ' "$profile" || failures=$((failures + 1))
fi

if [ "$profile" = research ]; then
  step "research の通信の制限"
  as_root_want() {
    if docker exec "$name" sh -c "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; failures=$((failures + 1)); fi
  }
  as_root_want "wsl.conf の起動のコマンドが research-boot" 'grep -qx "command=/usr/local/sbin/research-boot" /etc/wsl.conf'
  as_root_want "nftables.service を止めている" '[ "$(readlink /etc/systemd/system/nftables.service)" = /dev/null ]'
  # ネットワークの名前空間は全インスタンスで共有なので、ほかのテーブルを消してはいけない
  as_root_want "ルールを 2 回読み込んでも、テーブルは 1 つで、ほかのテーブルは残る" 'nft add table inet other_instance && /usr/local/sbin/research-boot && /usr/local/sbin/research-boot && [ "$(nft list tables | grep -c research_isolation)" = 1 ] && nft list table inet other_instance >/dev/null && nft delete table inet other_instance'
  as_root_want "読み込んだルールのハッシュを /run に残す" '[ "$(cat /run/research-firewall.sha256)" = "$(/usr/local/sbin/research-firewall --print | sha256sum | cut -d " " -f 1)" ]'
  # 所有者のないパケットを拒否のルールに落とさないよう、出力のフックでは uid 2100 に一致したときだけ jump する
  # ルールの行をすべて取り出し、jump の 1 行だけであることを確かめる (2 回読み込んだ直後なので、重複も見つかる)
  as_root_want "出力のフックは uid 2100 のパケットだけを research のチェーンへ送る" '[ "$(nft list chain inet research_isolation output | grep -vE "^[[:space:]]*(table |chain |type |\}|$)" | sed "s/^[[:space:]]*//")" = "meta skuid 2100 jump research" ]'
  # 拒否された connect() は No route to host で失敗する (verify-isolation.sh の判定と同じ)。root は uid が違うので対照になる
  probe='
    rejected() { [[ "$(LC_ALL=C timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>&1)" == *"No route to host"* ]]; }
    failed=0
    want() { if eval "$2" >/dev/null 2>&1; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi; }
    # 範囲の先頭と末尾の両方を試し、範囲を狭める変更も見つける
    for target in 169.254.169.254:80 169.254.0.1:80 192.168.0.1:80 192.168.255.1:80 10.0.0.1:80 10.255.0.1:80 172.16.0.1:80 172.31.255.1:80 100.64.0.1:80 100.127.255.1:80; do
      if [ "$(id -u)" = 2100 ]; then
        want "research: $target を拒否する (No route to host)" "rejected ${target%:*} ${target##*:}"
      else
        want "$(id -un): $target は拒否しない" "! rejected ${target%:*} ${target##*:}"
      fi
    done
    want "$(id -un): 名前解決できる" "getent hosts example.com"
    want "$(id -un): 公開の Web に届く" "curl -sS --max-time 10 -o /dev/null https://example.com"
    exit "$failed"
  '
  as_user "$probe" || failures=$((failures + 1))
  docker exec "$name" bash -c "$probe" || failures=$((failures + 1))
  # root 以外のほかの uid (dev の 1000 や agent の 2000 に当たるもの) も拒否しない
  docker exec -u 65534 "$name" bash -c "$probe" || failures=$((failures + 1))

  step "research-claude は資格情報がちょうど 1 つのときだけ進む"
  # コンテナでは後の隔離の検査 (bwrap など) も失敗するので、終了コードではなく出力で判定する。
  # 断るときは隔離の検査より前に止まるので、検査の FAIL の行が出ていないことも確かめる
  # 使い方: launcher_output [docker exec のオプション...]
  launcher_output() { docker exec -u research -w /home/research/work -e HOME=/home/research "$@" "$name" /usr/local/bin/research-claude --version 2>&1; }
  output="$(launcher_output -e ANTHROPIC_API_KEY=dummy -e CLAUDE_CODE_OAUTH_TOKEN=dummy)"
  launcher_want "両方あれば、隔離の検査の前に止まる" '[[ "$output" == *"両方があります"* && "$output" != *"FAIL "* ]]'
  output="$(launcher_output)"
  launcher_want "どちらもなければ、隔離の検査の前に止まる" '[[ "$output" == *"ANTHROPIC_API_KEY がありません"* && "$output" != *"FAIL "* ]]'
  # 対照: 1 つだけなら資格情報の検査を通り、隔離の検査まで進む。コンテナでは検査が FAIL を出し、
  # 通った場合は Claude がバージョンを出す。どちらも出なければ、検査を飛ばしたか途中で止まった
  # shellcheck disable=SC2034 # launcher_want の eval で読む
  output="$(launcher_output -e ANTHROPIC_API_KEY=dummy)"
  launcher_want "API キーだけなら、資格情報の検査を通って隔離の検査まで進む" '[[ "$output" != *"両方があります"* && "$output" != *"がありません"* && ( "$output" == *"FAIL "* || "$output" == *"(Claude Code)"* ) ]]'
fi

if [ "$profile" != main ]; then
  step "$profile の起動スクリプトは ~/work の下でだけ進む"
  # wsl.exe は --cd に失敗しても / で続けるので、/ も含めて ~/work の外を断る。
  # 進むかどうかは、上と同じく出力で判定する (コンテナでは隔離の検査が FAIL を出す)。
  # 資格情報は、両方の起動スクリプトが受け付けるトークンにする
  docker exec -u "$user" "$name" sh -c "mkdir -p /home/$user/workx /home/$user/work/run && ln -sfn / /home/$user/work/out" || failures=$((failures + 1))
  # 使い方: run_in <作業ディレクトリ>
  # シェルで cd してから起動し、シンボリックリンクの見かけのパスを PWD に入れて渡す
  run_in() { docker exec -u "$user" -e "HOME=/home/$user" -e CLAUDE_CODE_OAUTH_TOKEN=dummy "$name" bash -c 'cd "$1" && exec "$2" --version' bash "$1" "/usr/local/bin/$profile-claude" 2>&1; }
  for dir in / "/home/$user" "/home/$user/workx" "/home/$user/work/out"; do
    # shellcheck disable=SC2034 # launcher_want の eval で読む
    output="$(run_in "$dir")"
    launcher_want "$dir では、隔離の検査の前に止まる" '[[ "$output" == *"~/work の下で起動してください"* && "$output" != *"FAIL "* && "$output" != *"(Claude Code)"* ]]'
  done
  for dir in "/home/$user/work" "/home/$user/work/run"; do
    # shellcheck disable=SC2034 # launcher_want の eval で読む
    output="$(run_in "$dir")"
    launcher_want "$dir では、隔離の検査まで進む" '[[ "$output" != *"~/work の下で起動してください"* && ( "$output" == *"FAIL "* || "$output" == *"(Claude Code)"* ) ]]'
  done
fi

step "もう一度適用しても差分が出ない"
as_user '
  chezmoi apply --no-tty || exit 1
  changes="$(chezmoi status)"
  [ -z "$changes" ] || { printf "%s\n" "$changes"; exit 1; }
  echo "PASS 差分なし"
' || failures=$((failures + 1))

if [ "$failures" -gt 0 ]; then
  printf '\n%s 件の検査が失敗しました\n' "$failures"
  exit 1
fi
printf '\nすべての検査に通りました\n'
