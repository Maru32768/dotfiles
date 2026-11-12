#!/bin/bash
# split-pdf (home/dot_local/bin/executable_split-pdf) を、pypdf で作った PDF で試す。初回は pypdf を PyPI から取得する。
# check に渡す文字列の中で変数を展開するので、SC2016 を抑える
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/home/dot_local/bin/executable_split-pdf"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }
# Windows の Python はパイプに CRLF で書く
split() { uv run --quiet --script "$script" "$@" | tr -d '\r'; }
pages() { uv run --quiet --no-project --with pypdf python -I -c 'import sys; from pypdf import PdfReader; print(sum(len(PdfReader(f).pages) for f in sys.argv[1:]))' "$@"; }

# book.pdf (14 ページ): 序文 p1、Part I p2 (Ch1 p2 とその節 p3、Ch2 p4)、Part II p7 (Ch3 p8、Ch4 p10)、
# 付録 p12 と同じページの奥付。unordered.pdf (10 ページ): しおりがページ順でない (p6、p3、p9)。
# names.pdf: ASCII にないダッシュ、空白だけ、100 字の日本語の名前。aes.pdf: AES-256 で閲覧の制限だけをかけた PDF
uv run --quiet --no-project --with "pypdf[crypto]" python -I - "$work" <<'EOF'
import sys
from pypdf import PdfWriter

def pdf(path, n, marks, encrypt=False):
    w = PdfWriter()
    for _ in range(n):
        w.add_blank_page(100, 100)
    made = {}
    for title, page, parent in marks:
        made[title] = w.add_outline_item(title, page - 1, parent=made.get(parent))
    if encrypt:
        w.encrypt(user_password="", owner_password="owner", algorithm="AES-256")
    w.write(path)

pdf(f"{sys.argv[1]}/book.pdf", 14, [
    ("Preface", 1, None),
    ("Part I", 2, None), ("Ch1", 2, "Part I"), ("Ch1.1", 3, "Ch1"), ("Ch2", 4, "Part I"),
    ("Part II", 7, None), ("Ch3", 8, "Part II"), ("Ch4", 10, "Part II"),
    ("Appendix", 12, None), ("Colophon", 12, None),
])
pdf(f"{sys.argv[1]}/unordered.pdf", 10, [("B", 6, None), ("A", 3, None), ("C", 9, None)])
pdf(f"{sys.argv[1]}/names.pdf", 3, [("A — B", 1, None), ("   ", 2, None), ("あ" * 100, 3, None)])
pdf(f"{sys.argv[1]}/aes.pdf", 2, [("A", 1, None)], encrypt=True)
EOF

book="$work/book.pdf"
equals "最上位のしおりごとに分ける。同じページの奥付は付録に含める" "$(split "$book" --list)" "1  p.1-1  Preface
2  p.2-6  Part I
3  p.7-11  Part II
4  p.12-14  Appendix"
equals "--level 1 は章ごとに分け、Part の外の序文と付録もファイルにする" "$(split "$book" --level 1 --list)" "1  p.1-1  Preface
2  p.2-3  Ch1
3  p.4-6  Ch2
4  p.8-9  Ch3
5  p.10-11  Ch4
6  p.12-14  Appendix"
equals "しおりがページ順でなくても範囲が重ならない" "$(split "$work/unordered.pdf" --list | cut -c4-)" "p.3-5  A
p.6-8  B
p.9-10  C"
check "--list ではフォルダを作らない" '[ ! -e "$work/book" ]'

before="$(sha1sum <"$book")"
split "$book" --every 4 --out "$work/every" >/dev/null
equals "--every 4 のファイル名" "$(cd "$work/every" && ls)" "1 p.1-4.pdf
2 p.5-8.pdf
3 p.9-12.pdf
4 p.13-14.pdf"
equals "--every のファイルを合わせると元のページ数になる" "$(pages "$work"/every/*.pdf)" "14"
split "$book" --out "$work/chapters" >/dev/null
equals "元の PDF を書き換えない" "$(sha1sum <"$book")" "$before"
check "しおりごとのファイルに、しおりの名前がタイトルとして入る" '[ "$(uv run --quiet --no-project --with pypdf python -I -c "import sys; from pypdf import PdfReader; print(PdfReader(sys.argv[1]).metadata.title)" "$work/chapters/4 Appendix.pdf")" = Appendix ]'
check "--every 0 を拒む" '[[ "$(split "$book" --every 0 2>&1)" == *"--every must be at least 1"* ]]'

# ASCII で書けない名前でも止まらない。空の名前はページ範囲に、長い名前は Linux の上限に収める。
# Git Bash は 255 バイトを超える名前を切って見せるので、長さの確認は Linux (CI) でだけ効く
check "出力の文字コードで書けない名前でも止まらない" 'PYTHONIOENCODING=ascii split "$work/names.pdf" --out "$work/names"'
check "空白だけの名前は、ページ範囲をファイル名にする" '[ -f "$work/names/2 p.2-2.pdf" ]'
check "長い名前は 255 バイトに収める" '[ "$(cd "$work/names" && ls | LC_ALL=C awk "{ print length }" | sort -n | tail -1)" -le 255 ]'
check "閲覧の制限だけをかけた AES の PDF を分けられる" 'split "$work/aes.pdf" --list'

if [ "$failures" -gt 0 ]; then
  printf '\n%d 件の問題があります\n' "$failures"
  exit 1
fi
