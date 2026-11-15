# WSL ではない Linux の PC

サブ PC のような、Ubuntu Desktop 26.04 を直接入れた PC も、WSL の `dev` と同じ `main` の環境にする。chezmoi のデータでは `host = "desktop"` になる (WSL は `wsl`、Windows は `windows`)。

| 項目 | WSL (`dev`) | desktop |
|---|---|---|
| 作り方 | Windows 側の `lab.ps1 new` | PC で `provision/root.sh` と `provision/user.sh` を直接実行する |
| ユーザー | `root.sh` が作る | OS のインストールで作ったものを使う |
| `/etc/wsl.conf` | `root.sh` が書く | 書かない |
| `~/.config/environment.d/wslg.conf` | 置く (gpg-agent に WSLg の画面を渡す) | 置かない。デスクトップのセッションが `DISPLAY` を systemd に渡す |
| `.bash_profile` の `MISE_IGNORED_CONFIG_PATHS` | 書く (`/mnt/c` の下の Windows 用の設定を読まない) | 書かない |
| GPG の署名鍵 | Windows と同じ鍵を取り込む | PC ごとに作る |
| `agent`、`research` | 作れる | 作れない (`chezmoi init` が止まる) |

`host` は、`chezmoi init` のときに WSL のカーネルかどうかで決まり、設定に残る。`DOTFILES_HOST` (`wsl` か `desktop`) で指定もできる。CI のコンテナは WSL ではないカーネルで動くので、`tests/ci/container.sh` が指定している。

## セットアップ

1. Ubuntu Desktop 26.04 を入れ、普段のユーザーでログインする。
2. リポジトリを取ってきて、OS パッケージと設定を入れる。

   ```bash
   sudo apt-get install -y git
   ```

   ```bash
   git clone https://github.com/Maru32768/dotfiles.git ~/dotfiles
   ```

   ```bash
   sudo bash ~/dotfiles/provision/root.sh "$USER" ~/dotfiles/packages/apt.txt
   ```

   ```bash
   bash ~/dotfiles/provision/user.sh main ~/dotfiles
   ```

3. ログインし直して、`.bash_profile` の `PATH` を効かせる。
4. 資格情報を作る。パスフレーズはポップアップで入力する。

   ```bash
   ~/dotfiles/provision/setup-credentials.sh
   ```

   この PC 専用の GPG 署名鍵と SSH キーを作り、それぞれの公開鍵を表示する。GPG の公開鍵は <https://github.com/settings/gpg/new> に、SSH の公開鍵は <https://github.com/settings/ssh/new> に登録して、もう一度実行する。

5. `op-run` を使うなら、この PC 用の 1Password のサービスアカウントを作り、`op-run --set-token` で保存する (`docs/secrets.md`)。
6. `bash ~/dotfiles/tests/doctor.sh` で確かめる。

## 署名鍵

desktop の署名鍵は、Windows と WSL の鍵とは別にする。PC を失ったり破られたりしても、失効するのはその PC の鍵だけで済む。

- `setup-credentials.sh` が ed25519 の署名鍵と、cv25519 の暗号化の副鍵を作る。暗号化の副鍵は、`op-run` がトークンを署名の鍵あてに暗号化するために要る。有効期限は付けない。
- uid は `Maru32768 (<PC の名前>) <maru32768@gmail.com>`。GitHub はメールアドレスで鍵とコミットを結びつけるので、メールアドレスは同じにする。
- 作った鍵の ID は、`DOTFILES_SIGNING_KEY` を付けた `chezmoi init` で chezmoi の `signingKey` に入る。その後の `chezmoi init` では、環境変数がなくても残る。鍵を作る前の `.gitconfig` には `signingkey` を書かない。
- 1Password には置かない。失くしたら GitHub から消し、`setup-credentials.sh` で作り直して登録し直す。`op-run` のトークンも `op-run --set-token` で保存し直す。
- Windows と WSL の鍵は、この PC に入れない。

## 確かめていること

- `tests/ci/render.sh` が、`linux-desktop` を描画して適用する。置かれるファイルが `linux-main` から WSLg の設定を除いたものと一致すること、`.gitconfig` の署名の設定、`signingKey` が残ること、desktop に `agent` を作れないことを確かめる。
- `tests/ci/container.sh desktop` が、ユーザーを先に作ったコンテナで `root.sh`、`user.sh`、`doctor.sh` を流す。

## 実物の PC で確かめたこと

サブ PC (Ubuntu 26.04.1、GNOME の Wayland のセッション) で、この手順のとおりに作って確かめた (2026-11-16)。

- `doctor.sh` は、資格情報の TODO (1Password のトークンと Claude のログイン) のほかは通る。
- パスフレーズの入力画面は出る。Ubuntu Desktop では `pinentry-gnome3` が選ばれ、`doctor.sh` はそれも GUI として通す。
- 作った鍵で署名でき、GitHub への登録も `doctor.sh` が確かめる。
- SSH キーは、シェルの中では gpg-agent で扱われる。GNOME は自分の SSH エージェントを動かし、セッションの `SSH_AUTH_SOCK` をそちらに向けるが、`.bashrc` がシェルの中で gpg-agent に向け直す。シェルを通らない GUI のアプリは、GNOME のエージェントを使う。
- bubblewrap で名前空間を作れる。Ubuntu は権限のないユーザーの名前空間を AppArmor で制限できるが、このサブ PC では `kernel.apparmor_restrict_unprivileged_userns` が `0` だった。`1` の PC では、Claude Code のサンドボックスが動かないかもしれない。サンドボックスの中で Claude にコマンドを動かさせるところまでは、まだ試していない。
