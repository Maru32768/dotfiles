# mac

mac も、普段の開発に使う `main` の環境にする。chezmoi のデータでは `host = "mac"` になる。host は `chezmoi init` のときに `.chezmoi.os` が `darwin` かどうかで決まり、mac では `DOTFILES_HOST` を読まない。`DOTFILES_HOST` は、Linux で `wsl` と `desktop` を選ぶためのもの (`docs/desktop.md`)。

`agent` と `research` は作れない。`DOTFILES_PROFILE` に指定すると `chezmoi init` が止まる。

## 置くもの

WSL ではない Linux の PC (desktop) と同じものを置き、同じスクリプトを実行する。ただし、次のものは置かない (`home/.chezmoiignore`)。

| 置かないもの | 理由 |
|---|---|
| `~/.bashrc`、`~/.bash_profile` | mac のシェルは zsh |
| `~/.agents` | Codex を使わない。Codex のスキルの置き場 (`docs/skills.md`) |
| `~/.local/bin/op-run` | 1Password を使わない |

WSLg のための `~/.config/environment.d` も、desktop と同じく置かない。Windows 用のファイルは、Linux と同じく置かない。

## 仕事の PC (`work`)

chezmoi のデータの `work` は、仕事の PC かどうかを表す真偽値。仕事の PC にだけ置くファイルは、この値で分ける。mac に限らず、どの host でも使える。

- `DOTFILES_WORK=1` を付けた `chezmoi init` で `true`、`DOTFILES_WORK=0` で `false` になる。ほかの値では `chezmoi init` が止まる。
- `DOTFILES_WORK` がなければ、今の値を保つ。初めての `chezmoi init` では `false`。

```bash
DOTFILES_WORK=1 chezmoi init && chezmoi apply
```

## 署名鍵

desktop と同じく、PC ごとの鍵で署名し、Windows と WSL の鍵は使わない。

- 鍵の ID は、`DOTFILES_SIGNING_KEY` を付けた `chezmoi init` で chezmoi の `signingKey` に入る。その後の `chezmoi init` では、環境変数がなくても残る。
- 鍵を渡す前の `.gitconfig` には `signingkey` を書かない。

## 確かめていること

`tests/ci/render.sh` が、`.chezmoi.os` を `darwin` に差し替えて `darwin-main` と `darwin-work` を描画して適用する。host、`work` とその値が残ること、置かれるファイルと実行するスクリプト、署名鍵、mac に `agent` を作れないことを確かめる。`.chezmoi.os` を差し替えるだけなので、実際の mac での動作までは分からない。
