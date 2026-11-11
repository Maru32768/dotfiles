# dotfiles

このマシンの設定は`~/dotfiles`で管理している(chezmoi + mise)。

- ホームの設定ファイルは直接編集しない。`chezmoi source-path <file>`でソースを調べて、そちらを編集する
- Claude Codeの共通設定は`~/dotfiles/home/.claude-settings.json`に書く。`~/.claude/settings.json`はこれをマージして作られる
- スキルは`npx skills`で入れず、`~/dotfiles/home/.chezmoidata/skills.toml`に足す(`~/dotfiles/docs/skills.md`)
- APIキーは`.env`や`mise.local.toml`に書かない。Bitwarden Secrets Managerに置き、`bws-run <プロジェクト> -- <コマンド>`で外から渡す。リポジトリに`mise.local.toml`の`bws`タスクがあれば`mise run bws <タスク>`を使う。OSSのリポジトリには`bws-run`を書かない(`~/dotfiles/docs/secrets.md`)
- 開発ツールはmiseで入れる。OSパッケージは、miseで入らないものだけ`packages/apt.txt`に足す
- Windowsアプリは`packages/winget.json`に足す
- 詳しくは`~/dotfiles/docs/design.md`を読む

# 日本語の表記

書く日本語と直す日本語(UIの文言、ドキュメント、コメント、AI向けのプロンプト)は、次の表記にする。プロジェクトのCLAUDE.mdに別の規則があれば、そちらに従う。

- 英数字は半角にし、日本語との間にスペースを入れない: `AIを使って最大100件の記事を要約する`、`Google CloudのAPI`
- 丸括弧は半角の`()`にし、内側にも外側にもスペースを入れない: `更新間隔(分)`、`最大10件(無料)`。「」や【】はそのまま
- 次のスペースは残す: 英単語や固有名詞の中(`Google Cloud`)、`·`・`/`・`›`などの区切りの前後、URLの後ろ、マークアップの隣に置く先頭と末尾のスペース
- コード、識別子、パス、コマンド、URL、Markdownの構文は変えない。`一部`や`一度`などの漢数字は算用数字にしない
- 対象外: 日本語の語句を引用する英語の文(`returns the article to 未分類`)、外部から取得した記事やユーザーのデータ、`Intl`などが出力する文字列、マイグレーションや日付つきの記録などの履歴
- 既存の文章をこの表記に揃えるときは、ファイル全体への一括置換やUnicode正規化をせず、文脈を見て直す。見出しを変えたら、そのアンカーへのリンクも直す

# タスクの進め方

- 実装を伴うタスクは、ship-taskスキルの段階に沿って進める。質問への回答や、1ファイルで済む小さな修正には使わない
- issueが無いときは、依頼の内容を起点にする。issueへの書き戻し、子issueの起票、issueを閉じる手順は飛ばす

# コミット

- レビューの指摘を直すときは、修正ごとに1コミットにする。レビューの回ごとにまとめない。1つの変更で直る指摘はまとめて1コミットでよい
- 指摘を記録に残すときは、それぞれに修正したコミットを書く

# レビュー

- review-loopは4でponytail-review、simplify、prose-polishまで回す。review-loopを使うときは、prose-polishを別にかけない
- poteto-modeとreview-loopを一緒に使うときは、コードの片づけ(deslop、no-comments)と文書の推敲をreview-loopの4に任せる。poteto-modeのtechnical-writingとunslopは、返信とコミットメッセージにだけかける

@~/.claude/pstack-models.md
