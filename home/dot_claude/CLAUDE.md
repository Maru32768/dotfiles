# dotfiles

このマシンの設定は `~/dotfiles` で管理している (chezmoi + mise)。

- ホームの設定ファイルは直接編集しない。`chezmoi source-path <file>` でソースを調べて、そちらを編集する
- Claude Code の共通設定は `~/dotfiles/home/.claude-settings.json` に書く。`~/.claude/settings.json` はこれをマージして作られる
- 開発ツールは mise で入れる。OS パッケージは、mise で入らないものだけ `packages/apt.txt` に足す
- Windows アプリは `packages/winget.json` に足す
- 詳しくは `~/dotfiles/docs/design.md` を読む

@~/.claude/pstack-models.md
