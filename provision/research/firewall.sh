#!/bin/bash
# research ユーザー (uid 2100) の通信から、LAN、Windows、クラウドのメタデータの宛先を拒否する。
# 起動のたびに root で実行される (provision/research/boot.sh)。
#
# WSL のインスタンスはネットワークの名前空間を 1 つ共有するので、このルールはすべてのインスタンスに効く。
# そのため送り元の uid で絞る。uid 2100 は research だけが使う (provision/root.sh)。
# テーブルは wsl --shutdown まで残り、lab.ps1 rm の後も残る。ほかのインスタンスに uid 2100 はないので影響しない。
#
# 使い方: research-firewall [--print]   (--print はルールを表示するだけで読み込まない)
set -euo pipefail

uid=2100
table=research_isolation
# 読み込んだルールのハッシュ。/run はインスタンスごとにあるので、テーブルが共有の名前空間に前から残っていても、
# このインスタンスの起動で読み込んだかを verify-isolation.sh が確かめられる
loaded=/run/research-firewall.sha256
# 読めなければここで止まる。ヒアドキュメントの中のコマンド置換では、失敗しても続いてしまう
resolv="$(cat /etc/resolv.conf)"

# 名前解決だけは通す。WSL の DNS トンネル (10.255.255.254) は lo に載っているので上の lo の許可で通るが、
# resolv.conf がほかの宛先を指す環境 (コンテナなど) のために 53 番を通す
dns_rules() {
  local keyword address family
  while read -r keyword address _; do
    [ "$keyword" = nameserver ] || continue
    address="${address%%\%*}"
    if [[ "$address" == *:* ]]; then family=ip6; else family=ip; fi
    printf '    %s daddr %s udp dport 53 accept\n' "$family" "$address"
    printf '    %s daddr %s tcp dport 53 accept\n' "$family" "$address"
  done <<<"$resolv"
}

# 先頭の 2 行で、前回のテーブルがあってもなくても消してから作り直す。全体が 1 回の処理として適用される。
# drop ではなく reject にする。IPv4 の connect() が時間切れを待たずに EHOSTUNREACH (No route to host) で失敗し、
# WebFetch も待たされない。verify-isolation.sh はこの失敗の仕方で、ルールが効いたことを判定する。
# IPv6 では同じ reject が EACCES (Permission denied) になるので、IPv6 を検査するときは判定を変える
#
# uid 2100 に一致したパケットだけを research のチェーンへ送る。「uid が違えば accept」と書くと、
# 所有者のないパケット (カーネルが返す ICMP や RST、close した後の TCP、NFS などカーネル内の通信) は
# どちらの条件にも一致せず、拒否のルールまで落ちてくる。全インスタンスで Windows からの ping に
# 応答できなくなることを確かめた
ruleset() {
  cat <<EOF
table inet $table
delete table inet $table
table inet $table {
  chain output {
    type filter hook output priority 0; policy accept;
    meta skuid $uid jump research
  }
  chain research {
    oif "lo" accept
$(dns_rules)
    ip daddr { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } reject with icmpx admin-prohibited
    # IPv6 は宛先を問わず拒否する。LAN の機器や Windows はグローバルなアドレスも持つので、範囲では絞れない。
    # NAT (既定) には IPv6 の経路がないので、今は何も変わらない
    meta nfproto ipv6 reject with icmpx admin-prohibited
  }
}
EOF
}

rules="$(ruleset)"
if [ "${1:-}" = --print ]; then
  printf '%s\n' "$rules"
  exit 0
fi
printf '%s\n' "$rules" | /usr/sbin/nft -f -
printf '%s\n' "$rules" | sha256sum | cut -d ' ' -f 1 >"$loaded"
