#!/bin/bash
# インスタンスの間で共有されるマウントを、このインスタンスの中でだけ外す。
# wsl.conf の [boot] command から root で実行される。
#
# /mnt/wsl は全インスタンスで共有され、Docker Desktop のソケットや、ほかのインスタンスの
# バインドマウントが見える。WSLg のマウントからは Windows の画面やクリップボードへ届く。
#
# shared のまま外すと、ほかのインスタンスにも伝わって Docker Desktop を壊しかねない。
# 必ず先に private にする。private にできなければ外さない。
set -uo pipefail

for target in /tmp/.X11-unix /mnt/wslg /mnt/wsl; do
  # 同じ場所に重なっていることがあるので、なくなるまで外す
  while mountpoint -q "$target"; do
    if ! mount --make-rprivate "$target" || ! umount -l "$target"; then
      break
    fi
  done
done
