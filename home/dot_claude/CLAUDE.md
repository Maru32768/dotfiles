# dotfiles

このマシンの設定は `~/dotfiles` で管理している (chezmoi + mise)。

- ホームの設定ファイルは直接編集しない。`chezmoi source-path <file>` でソースを調べて、そちらを編集する
- Claude Code の共通設定は `~/dotfiles/home/.claude-settings.json` に書く。`~/.claude/settings.json` はこれをマージして作られる
- スキルは `npx skills` で入れず、`~/dotfiles/home/.chezmoidata/skills.toml` に足す (`~/dotfiles/docs/skills.md`)
- API キーは `.env` や `mise.local.toml` に書かない。Bitwarden Secrets Manager に置き、mise のタスクから `bws-run <プロジェクト> -- <コマンド>` で渡す (`~/dotfiles/docs/secrets.md`)
- 開発ツールは mise で入れる。OS パッケージは、mise で入らないものだけ `packages/apt.txt` に足す
- Windows アプリは `packages/winget.json` に足す
- 詳しくは `~/dotfiles/docs/design.md` を読む

@~/.claude/pstack-models.md
