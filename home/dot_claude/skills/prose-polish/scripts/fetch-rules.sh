#!/bin/bash
# いもすさんの humanizer ルール (https://imoz.jp/humanizer.<ja|en>.txt) を、rules.sha256 に固定した版のときだけ置く。
# 本文はライセンスが分からないので dotfiles に入れず、取得のたびに照合する。照合済みの控えは手元のキャッシュにだけ残す。
#
#   fetch-rules.sh <ja|en> <置く先>   固定した版と違えば失敗する
#   fetch-rules.sh --check            上流が固定した版と違えば、控えとの差分と、rules.sha256 に書く行を出す
set -euo pipefail

pins="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules.sha256"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/prose-polish"
mkdir -p "$cache"

pinned() { awk -v f="$1" '$2 == f { print $1 }' "$pins"; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

if [ "${1:-}" = --check ]; then
  changed=0
  for lang in ja en; do
    name="humanizer.$lang.txt"
    new="$(mktemp)"
    curl -fsSL "https://imoz.jp/$name" -o "$new"
    if [ "$(sha "$new")" = "$(pinned "$name")" ]; then
      rm -f "$new"
      continue
    fi
    changed=1
    echo "== $name が更新されている"
    if [ -f "$cache/$name" ]; then
      diff -u "$cache/$name" "$new" || true
    else
      echo "(固定した版の控えが無いので差分を出せない)"
    fi
    echo "rules.sha256 に書く行: $(sha "$new")  $name"
    rm -f "$new"
  done
  [ "$changed" -eq 0 ] && echo "すべて固定した版と同じです"
  exit 0
fi

lang="${1:?ja か en を指定する}"
dest="${2:?置く先を指定する}"
case "$lang" in ja | en) ;; *) echo "ja か en を指定する: $lang" >&2; exit 1 ;; esac
name="humanizer.$lang.txt"
want="$(pinned "$name")"

if [ ! -f "$cache/$name" ] || [ "$(sha "$cache/$name")" != "$want" ]; then
  tmp="$(mktemp)"
  curl -fsSL "https://imoz.jp/$name" -o "$tmp"
  if [ "$(sha "$tmp")" != "$want" ]; then
    rm -f "$tmp"
    echo "$name が固定した版 ($want) と違う。fetch-rules.sh --check で差分を見て、dotfiles の rules.sha256 を更新する" >&2
    exit 1
  fi
  mv "$tmp" "$cache/$name"
fi
mkdir -p "$(dirname "$dest")"
cp "$cache/$name" "$dest"
