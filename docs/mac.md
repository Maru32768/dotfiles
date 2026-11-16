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

desktopと同じく、WSLgのための`~/.config/environment.d`も置かない。Linuxと同じく、Windows用のファイルも置かない。zshの設定(`~/.zprofile`、`~/.zshrc`)はmacにだけ置く。

Homebrewを`/opt/homebrew`に入れるApple Siliconのmacだけを考えている。

## シェル

- `~/.zprofile`はHomebrewの環境を読み、`~/.local/bin`、`~/go/bin`、miseのshimsをPATHの先頭に足す。macOSの`/etc/zprofile`がpath_helperでシステムのパスを先頭に並べ直すので、`.zshenv`ではなくここで足す。
- `~/.zshrc`は対話のシェルの設定、`mise activate`、`GPG_TTY`を持つ。`~/.zshrc.local`があれば最後に読む(`docs/design.md`の「ローカルの設定」)。
- 既にある`~/.zprofile`と`~/.zshrc`は、適用すると置き換わる。残したい行は、適用する前に`~/.zshrc.local`に移す。`~/.zprofile`から移した行は、対話のシェルでだけ読まれるようになる。

## SSHとGPG

- SSHはmacOSのssh-agentを使う。GitHubの鍵は`~/.ssh/config`の`AddKeysToAgent`でssh-agentに読み込み、パスフレーズを`UseKeychain`でKeychainに保存する。仕事のホストの鍵もmacOSのssh-agentで使うので、Linuxと違って`SSH_AUTH_SOCK`をgpg-agentに向けず、gpg-agentのSSHの機能(`enable-ssh-support`)も使わない。
- `~/.ssh/config`の先頭に`IgnoreUnknown UseKeychain`を置き、Apple以外のssh(Homebrewのopensshなど)が`UseKeychain`で止まらないようにする。`IgnoreUnknown`も最初に見つけた値が使われるので、`~/.ssh/config.local`に書いた`IgnoreUnknown`は効かない。ほかに無視させたいオプションがあれば、dotfilesのこの行に足す。
- GPGのパスフレーズはpinentry-macの画面で入力する。`gpg-agent.conf`に`pinentry-program`が無いときだけ、chezmoiが`/opt/homebrew/bin/pinentry-mac`を足す(JetBrains IDEなどが書いたものは残る)。pinentry-macは`packages/Brewfile`で入る。

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

## セットアップ

1. Homebrewを入れる(<https://brew.sh>)。Xcodeのコマンドラインツールも一緒に入る。
2. リポジトリを取ってきて、Homebrewの一覧にあるものと設定を入れる。仕事のPCなら、`user.sh`を実行するコマンドの先頭に`DOTFILES_WORK=1`を付ける。

   ```bash
   git clone https://github.com/Maru32768/dotfiles.git ~/dotfiles
   ```

   ```bash
   brew bundle --file ~/dotfiles/packages/Brewfile
   ```

   ```bash
   bash ~/dotfiles/provision/user.sh main ~/dotfiles
   ```

3. 新しいターミナルを開いて、`~/.zprofile`のPATHを効かせる。
4. 資格情報を作る。GPGのパスフレーズはpinentry-macの画面で、SSHキーのパスフレーズはターミナルで入力する。

   ```bash
   ~/dotfiles/provision/setup-credentials.sh
   ```

   スクリプトはこのPC専用のGPG署名鍵とSSHキーを作り、それぞれの公開鍵を表示する。GPGの公開鍵は<https://github.com/settings/gpg/new>に、SSHの公開鍵は<https://github.com/settings/ssh/new>に登録して、もう一度実行する。鍵のuidとSSHキーのコメントには、ホスト名ではなく`mac`か`work-mac`が入る(uidはGitHubで公開される)。1Password(`op-run`)は使わないので、暗号化の副鍵は作らない。

5. `bash ~/dotfiles/tests/doctor.sh`で確かめる。

## 確かめていること

`tests/ci/render.sh`が`.chezmoi.os`を`darwin`に差し替えて、`darwin-main`と`darwin-work`を描画して適用する。hostと`work`の値、それらが残ること、置くファイルと実行するスクリプト、署名鍵、macに`agent`を作れないことを確かめる。macのhostが`DOTFILES_HOST`や設定に残ったhostで変わらないことも確かめる。Linuxのwslとdesktop、Windowsでも、`work`が同じように読まれて残ることと、PR運用の指示を置くことを確かめる。zshがあれば、zshを動かして、`~/.zshrc`が最後まで読めて`~/.zshrc.local`を読むことと、`~/.zprofile`のPATHを確かめる(CIではランナーにzshを入れる)。`gpg-agent.conf`のpinentry-macと、`~/.ssh/config`の`AddKeysToAgent`と`UseKeychain`の行も確かめる。macの`~/.ssh/config`は、`UseKeychain`をどのsshも知らない名前に替えてから実行環境のsshで読み、`IgnoreUnknown`がどのホストにも効くことを確かめる。`.chezmoi.os`を差し替えるだけなので、実際のmacでの動作はCIの`macos`のジョブで確かめる。ジョブで試さないもの(鍵の作成、pinentry-macの画面、Keychain)は`docs/ci.md`の「確かめられないこと」にある。
