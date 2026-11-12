# dotfiles

このマシンの設定は`~/dotfiles`で管理している(chezmoi + mise)。

- ホームの設定ファイルは直接編集しない。`chezmoi source-path <file>`でソースを調べて、そちらを編集する
- Claude Codeの共通設定は`~/dotfiles/home/.claude-settings.json`に書く。`~/.claude/settings.json`はこれをマージして作られる
- スキルは`npx skills`で入れず、`~/dotfiles/home/.chezmoidata/skills.toml`に足す(`~/dotfiles/docs/skills.md`)
- APIキーは`.env`や`mise.local.toml`に書かない。Bitwarden Secrets Managerに置き、`bws-run <プロジェクト> -- <コマンド>`で外から渡す。リポジトリに`mise.local.toml`の`bws`タスクがあれば`mise run bws <タスク>`を使う。OSSのリポジトリには`bws-run`を書かない(`~/dotfiles/docs/secrets.md`)
- 開発ツールはmiseで入れる。OSパッケージは、miseで入らないものだけ`packages/apt.txt`に足す
- Windowsアプリは`packages/winget.json`に足す
- 詳しくは`~/dotfiles/docs/design.md`を読む

# ローカルの翻訳モデル

Windowsでは、翻訳専用のLLMのPLaMo 3 Translate(日英を含む53言語)を手元のGPUで動かせる(`~/dotfiles/docs/tools.md`)。

- `plamo-server.cmd`(既定は2B、`plamo-server.cmd 8b`で8B。Git Bashでは拡張子が要る)をバックグラウンドで起動すると、`http://127.0.0.1:8077/health`が`ok`を返してから使える。止めるまで動き続ける
- 訳すときは`/v1/chat/completions`に、原文を最後の`user`メッセージにして、`"chat_template_kwargs": {"target_lang": "ja"}`、`"temperature": 0`、`"stop": ["<|plamo:tag|>", "<|plamo:bos|>"]`を付けて送る。訳文は`choices[0].message.content`に入る
- 入力と出力の合計は16,384トークンまでなので、長い文書は見出しや段落の区切りで分けて送る。Markdownの構文と行の数は保たれる
- 用語集(`glossary`)、文体(`form`)、前後の文脈(`context`)も指定できる。書き方はモデルカード(https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF)を読む
- 訳文には全角の括弧や、日本語と英数字の間のスペースが混じる。そのまま使わず、上の表記の規則に合わせて推敲する

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
- PR/MRのタイトルと本文は、そのリポジトリのコミットメッセージと同じ言語で書く

# レビュー

- review-loopは4でponytail-review、simplify、prose-polishまで回す。review-loopを使うときは、prose-polishを別にかけない
- poteto-modeとreview-loopを一緒に使うときは、コードの片づけ(deslop、no-comments)と文書の推敲をreview-loopの4に任せる。poteto-modeのtechnical-writingとunslopは、返信とコミットメッセージにだけかける

# 技術的な知見の記録

作業中に次のような知見が得られたら、そのタスクの利用者への最後の返信の末尾に`記録候補: <タイトル案>(/knowledge-capture)`を1行だけ書く。サブエージェントとして返す報告には書かない。提案は1つのタスクで1回で、迷ったら提案する。記録は、利用者が頼んだときに`knowledge-capture`スキルで行う。

- エラーメッセージを読むだけでは分からなかった不具合の原因、環境やバージョンに依存する問題、ドキュメントと違う挙動やドキュメントにない挙動
- 選択肢を比べて決めた設計判断
- ソースコードや実験で確かめた内部の仕組み
- 短く書ける意外な挙動や設定の注意点
- 解決しないまま中断する長い調査

この会話で既に記録した問題について新しく分かったことがあれば、追記を提案する。

@~/.claude/pstack-models.md
