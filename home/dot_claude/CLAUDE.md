# dotfiles

このマシンの設定は `~/dotfiles` で管理している (chezmoi + mise)。

- ホームの設定ファイルは直接編集しない。`chezmoi source-path <file>` でソースを調べて、そちらを編集する
- Claude Code の共通設定は `~/dotfiles/home/.claude-settings.json` に書く。`~/.claude/settings.json` はこれをマージして作られる
- スキルは `npx skills` で入れず、`~/dotfiles/home/.chezmoidata/skills.toml` に足す (`~/dotfiles/docs/skills.md`)
- API キーは `.env` や `mise.local.toml` に書かない。Bitwarden Secrets Manager に置き、mise のタスクから `bws-run <プロジェクト> -- <コマンド>` で渡す (`~/dotfiles/docs/secrets.md`)
- 開発ツールは mise で入れる。OS パッケージは、mise で入らないものだけ `packages/apt.txt` に足す
- Windows アプリは `packages/winget.json` に足す
- 詳しくは `~/dotfiles/docs/design.md` を読む

# コミット

- レビューの指摘を直すときは、修正ごとに 1 コミットにする。レビューの回ごとにまとめない。1 つの変更で直る指摘はまとめて 1 コミットでよい
- 指摘を記録に残すときは、それぞれに修正したコミットを書く

# レビュー

- review-loop は 4 で ponytail-review、simplify、prose-polish まで回す。review-loop を使うときは、prose-polish を別にかけない
- poteto-mode と review-loop を一緒に使うときは、コードの片づけ (deslop、no-comments) と文書の推敲を review-loop の 4 に任せる。poteto-mode の technical-writing と unslop は、返信とコミットメッセージにだけかける

@~/.claude/pstack-models.md
