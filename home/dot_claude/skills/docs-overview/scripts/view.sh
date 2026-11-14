#!/bin/bash
# 概観のMarkdownを、ブラウザで開くだけで読める1枚のHTMLに包み、標準出力に書く。Mermaidの図は構文を検査してから
# 描く。スクリプトが読み込めないときは、Markdownのまま表示する。
#
#   view.sh <概観のMarkdown>
#
# 概観は第三者の文書から作ることがあり、markedは生のHTMLを消毒しない。そこで、Markdownの中の生のHTMLは文字として
# 出す(<meta http-equiv="refresh">はCSPで止まらず、開いた人を別のサイトへ移動させる)。そのうえでCSPで、読み込む
# 2つのスクリプトと、ハッシュの合うインラインのスクリプトだけを動かす。インラインのスクリプトを変えたら、sha256-の
# 値を計算し直す(tests/ci/docs-overview-test.shが比べる)。
set -uo pipefail

[ $# -eq 1 ] || { printf 'usage: view.sh <概観のMarkdown>\n' >&2; exit 2; }
f=$1
[ -r "$f" ] && [ ! -d "$f" ] || { printf 'view.sh: 読めない: %s\n' "$f" >&2; exit 2; }
# awkは「名前=値」の形の引数を変数への代入として、-を標準入力として読む
case "$f" in /* | ?:* | ./*) ;; *=* | -*) f="./$f" ;; esac

page=$(cat <<'EOF'
<!doctype html>
<html lang="ja"><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-AHOAJsAdA55HElvUDMPx4hABm6FG0PcbGc4dzfeBIRk=' https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@TITLE@</title>
<style>
:root{--bg:#ffffff;--fg:#1f2328;--muted:#59636e;--border:#d1d9e0;--code:#f6f8fa;--link:#0969da}
@media (prefers-color-scheme: dark){
:root{--bg:#0d1117;--fg:#f0f6fc;--muted:#9198a1;--border:#3d444d;--code:#151b23;--link:#4493f8}}
body{background:var(--bg);color:var(--fg);font:16px/1.75 system-ui,"Yu Gothic UI","Hiragino Sans",sans-serif;
margin:0;padding:24px 16px}
main,#md,#status{max-width:940px;margin-left:auto;margin-right:auto}
a{color:var(--link)}
code{background:var(--code);padding:.1em .35em;border-radius:4px;font-size:.9em}
table{border-collapse:collapse;display:block;overflow-x:auto;margin:1em 0}
th,td{border:1px solid var(--border);padding:6px 10px;vertical-align:top;font-size:.94em;text-align:left}
th{background:var(--code)}
h1,h2{border-bottom:1px solid var(--border);padding-bottom:.3em}
h2{margin-top:2em}
pre.mermaid{background:transparent;text-align:center;overflow-x:auto}
#md{white-space:pre-wrap;font-size:.9em}
#status{color:var(--muted);font-size:.85em}
</style></head>
<body>
<p id="status">Mermaidの検査: 未実行(スクリプトが読み込めないときは、下にMarkdownのまま表示します)</p>
<main id="out"></main>
<pre id="md">@BODY@</pre>
<script src="https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js" integrity="sha512-xeUh+KxNyTufZOje++oQHstlMQ8/rpyzPuM+gjMFYK3z5ILJGE7l2NvYL+XfliKURMpBIKKp1XoPN/qswlSMFA==" crossorigin="anonymous"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js" integrity="sha512-6a80OTZVmEJhqYJUmYd5z8yHUCDlYnj6q9XwB/gKOEyNQV/Q8u+XeSG59a2ZKFEHGTYzgfOQKYEBtrZV7vBr+Q==" crossorigin="anonymous"></script>
<script>
(async () => {
  const raw = document.getElementById('md');
  const status = document.getElementById('status');
  if (typeof marked === 'undefined' || typeof mermaid === 'undefined') {
    status.textContent = 'Mermaidの検査: スクリプトを読み込めなかったので、Markdownのまま表示します';
    return;
  }
  const esc = (s) => s.replace(/[&<>]/g, (c) => '&#' + c.charCodeAt(0) + ';');
  marked.use({ renderer: { html: esc } });
  document.getElementById('out').innerHTML = marked.parse(raw.textContent);
  raw.style.display = 'none';
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
  const res = [];
  const blocks = [...document.querySelectorAll('pre > code.language-mermaid')];
  for (const [i, c] of blocks.entries()) {
    const src = c.textContent;
    try { await mermaid.parse(src); res.push('図' + (i + 1) + 'は構文OK'); }
    catch (e) { res.push('図' + (i + 1) + 'は構文エラー: ' + (e.message || e)); }
    const pre = c.parentElement; pre.className = 'mermaid'; pre.textContent = src;
  }
  try {
    await mermaid.run({ querySelector: 'pre.mermaid' });
    res.push('描画OK(' + document.querySelectorAll('pre.mermaid svg').length + '個)');
  } catch (e) { res.push('描画エラー: ' + (e.message || e)); }
  status.textContent = 'Mermaidの検査: ' + res.join(' / ');
})();
</script></body></html>
EOF
)
pre=${page%%@TITLE@*}
rest=${page#*@TITLE@}
mid=${rest%%@BODY@*}
post=${rest#*@BODY@}

# 1行目に題、2行目から本文を書く。題は最初の「# 」の行で決まるので、本文は最後まで溜めてから書く
LC_ALL=C awk '
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
BEGIN { title = ARGV[1]; sub(/.*\//, "", title) }
{ sub(/\r$/, "") }
!found && /^# / { title = substr($0, 3); found = 1 }
{ body = body esc($0) "\n" }
END { print esc(title); printf "%s", body }
' "$f" | {
  IFS= read -r title
  printf '%s%s%s' "$pre" "$title" "$mid"
  cat
  printf '%s\n' "$post"
}
