# mac

macも、普段の開発に使う`main`の環境にする。chezmoiのデータでは`host = "mac"`になる。hostは`chezmoi init`のときに、`.chezmoi.os`が`darwin`かどうかで決まる。`DOTFILES_HOST`はLinuxで`wsl`か`desktop`を選ぶためのもので(`docs/desktop.md`)、macでは読まない。

`agent`と`research`は作れない。`DOTFILES_PROFILE`に指定すると`chezmoi init`が止まる。

## 置くもの

WSLではないLinuxのPC(desktop)と同じものを置き、同じスクリプトを実行する。ただし、次のものは置かない(`home/.chezmoiignore`)。

| 置かないもの | 理由 |
|---|---|
| `~/.bashrc`、`~/.bash_profile` | macのシェルはzsh |
| `~/.agents` | Codexのスキルの置き場(`docs/skills.md`)だが、Codexを使わない |
| `~/.local/bin/op-run`、`~/.claude/rules/secrets.md` | 1Passwordを使わない |

desktopと同じく、WSLgのための`~/.config/environment.d`も置かない。Linuxと同じく、Windows用のファイルも置かない。代わりに、zshの設定(`~/.zprofile`、`~/.zshrc`)をmacにだけ置く。

Homebrewを`/opt/homebrew`に入れる、Apple Siliconのmacだけを考えている。

## シェル

- `~/.zprofile`は、Homebrewの環境を読み、`~/.local/bin`、`~/go/bin`、miseのshimsをPATHの先頭に足す。macOSの`/etc/zprofile`(path_helper)がシステムのパスを先頭に並べ直すので、`.zshenv`ではなくここで足す。
- `~/.zshrc`は、対話のシェルの設定、`mise activate`、`GPG_TTY`を持つ。最後に`~/.zshrc.local`があれば読む(`docs/design.md`の「ローカルの設定」)。

## SSHとGPG

- SSHは、macOSのssh-agentを使う。GitHubの鍵は、`~/.ssh/config`の`UseKeychain`と`AddKeysToAgent`でKeychainに入れる。仕事のホストの鍵もKeychainのagentで使うので、Linuxと違い、`SSH_AUTH_SOCK`をgpg-agentに向けず、gpg-agentのSSHの機能(`enable-ssh-support`)も使わない。
- GPGのパスフレーズは、pinentry-macの画面で入力する。`gpg-agent.conf`に`pinentry-program`が無いときだけ、chezmoiが`/opt/homebrew/bin/pinentry-mac`を足す(JetBrains IDEなどが書いたものは残る)。

## 仕事のPC(`work`)

chezmoiのデータの`work`は仕事のPCかどうかを表す真偽値。仕事のPCにだけ置くファイルは、この値で分ける。macに限らず、どのhostでも使える。

- `DOTFILES_WORK=1`を付けた`chezmoi init`で`true`、`DOTFILES_WORK=0`で`false`になる。ほかの値では`chezmoi init`が止まる。
- `DOTFILES_WORK`がなければ、今の値を保つ。初めての`chezmoi init`では`false`。

```bash
DOTFILES_WORK=1 chezmoi init && chezmoi apply
```

仕事のPCにだけ、PR運用の指示(`~/.claude/rules/pr.md`)を置く(`docs/claude.md`)。

## 署名鍵

desktopと同じく、PCごとの鍵で署名し、WindowsとWSLの鍵は使わない。

- 鍵のIDは、`DOTFILES_SIGNING_KEY`を付けた`chezmoi init`でchezmoiの`signingKey`に入る。その後の`chezmoi init`では、環境変数がなくても残る。
- 鍵を渡す前の`.gitconfig`には`signingkey`を書かない。

## 確かめていること

`tests/ci/render.sh`が`.chezmoi.os`を`darwin`に差し替えて、`darwin-main`と`darwin-work`を描画して適用する。hostと`work`の値、それらが残ること、置くファイルと実行するスクリプト、署名鍵、macに`agent`を作れないことを確かめる。macのhostが、`DOTFILES_HOST`や設定に残ったhostで変わらないことも確かめる。`work`は、LinuxのwslとdesktopとWindowsでも、同じように読んで残り、PR運用の指示を置くことを確かめる。zshがあれば、`~/.zshrc`が最後まで読めて`~/.zshrc.local`を読むことと、`~/.zprofile`のPATHを、zshを動かして確かめる(CIではランナーにzshを入れる)。`gpg-agent.conf`のpinentry-macと、`~/.ssh/config`のKeychainの行も確かめる。`.chezmoi.os`を差し替えるだけなので、実際のmacでの動作までは分からない。
