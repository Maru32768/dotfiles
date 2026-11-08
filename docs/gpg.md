# GPG コミット署名

コミットは GPG 署名する (`commit.gpgsign = true`)。GitHub に登録している鍵は次の 1 本だけ。

| 項目 | 値 |
|---|---|
| 鍵 ID | `78324D99D34D3111` |
| フィンガープリント | `7AF93B4735CF2AAC930EF5CD78324D99D34D3111` |
| 種類 | rsa4096 (2026-04-14 作成) |

WSL には GitHub に登録していない古い鍵 `87D535BB8566CC0A` も残っている。`user.signingkey` を設定しているので署名には使われない。

## Windows と WSL の関係

- `.gitconfig` は同じテンプレート (`home/dot_gitconfig.tmpl`) から環境ごとに作る。Windows へのリンクにはしない。
- `gpg.program = gpg` なので、各環境の `PATH` で解決される。

| 環境 | 使われる gpg | 鍵の場所 |
|---|---|---|
| Windows | `C:\Program Files\Git\usr\bin\gpg.exe` | `C:\Users\maru3\.gnupg` |
| WSL | `/usr/bin/gpg` | `~/.gnupg` |

Kleopatra 系の `%APPDATA%\gnupg` は別の場所で、署名には使っていない。

`gpg.program` に Windows のパスを書くと WSL で動かなくなる (その逆も同じ) ので、パスを書かない。

## 新しい環境のセットアップ

1. `lab\lab.ps1 new <名前>` でインスタンスを作る。署名設定とキャッシュ時間は chezmoi が適用する。
2. 鍵を取り込む。パスフレーズの入力があるので、対話できる端末で実行する。

   ```bash
   ~/dotfiles/provision/setup-credentials.sh                       # Windows の gpg から取り込む
   ~/dotfiles/provision/setup-credentials.sh <エクスポートしたファイル>  # バックアップから取り込む
   ```

   フィンガープリントが違うファイルなら、何も変更せずに終了する。同じスクリプトがこの環境専用の SSH キーも作る。

3. 署名を確認する。

   ```bash
   echo test | gpg -u 78324D99D34D3111 --clearsign > /dev/null && echo OK
   ```

## バックアップ

残すものは次の 3 つ。**どれもこのリポジトリには入れない** (`.gitignore` で `*.asc`, `*.gpg`, `*.rev` を除外している)。

| ファイル | 作り方 | 用途 |
|---|---|---|
| 秘密鍵 | `gpg --armor --export-secret-keys 78324D99D34D3111` | 復元 |
| 失効証明書 | `~/.gnupg/openpgp-revocs.d/<フィンガープリント>.rev` (Windows 側) | 鍵を失った・漏れたときの失効 |
| ownertrust | `gpg --export-ownertrust` | 信頼設定の復元 |

### クラウドに置く前に暗号化する

エクスポートした秘密鍵を守っているのは鍵のパスフレーズだけで、ファイルが漏れるとオフラインで総当たりされうる。失効証明書には鍵のパスフレーズの保護がなく、ファイルがあれば誰でも鍵を失効できる。Google Drive などに置くなら、鍵とは別の強いパスフレーズでファイルごと暗号化する。

```bash
gpg --symmetric --cipher-algo AES256 --output secret-key.asc.gpg secret-key.asc
```

このパスフレーズを同じ場所に保管しないこと。復元は `gpg --output secret-key.asc --decrypt secret-key.asc.gpg` で行う。

## パスフレーズの入力

WSL では `pinentry-gtk2` を使い、WSLg のポップアップで入力する。`packages/apt.txt` で入れる。

- `/usr/bin/pinentry` は `update-alternatives` の自動選択で `pinentry-gtk-2` を指す (優先度が `pinentry-curses` より高い)。
- JetBrains IDE が `gpg-agent.conf` に `pinentry-program` を書き込むことがある。chezmoi は必要な行だけを管理するので、この行は残る。
- SSH キーのパスフレーズも gpg-agent が扱うので、同じポップアップが出る。SSH の要求には表示先の情報が付かないので、`home/dot_config/environment.d/wslg.conf` で gpg-agent の環境に `DISPLAY` を入れている。
- 端末を持たないプロセス (Claude のコミットなど) でも `DISPLAY` があればポップアップが出るはず。キャッシュが切れた状態では未確認。

## キャッシュ時間

パスフレーズのキャッシュは WSL で、最後に使ってから 24 時間、入力してから最長 72 時間にしている。Windows 側の値に揃えた。変えるときは `home/private_dot_gnupg/modify_gpg-agent.conf` の `CACHE_TTL_SECONDS` と `MAX_CACHE_TTL_SECONDS` を直して `chezmoi apply` する。新しい値は gpg-agent を起動し直すと効く。

- キャッシュが有効な間は、Claude を含む同じユーザーのプロセスがパスフレーズなしで署名できる。
- 再読み込みするとキャッシュは消える。WSL が停止したときも消える。
- Windows 側の `gpg-agent` には適用していない。

## トラブルシュート

| 症状 | 原因と対処 |
|---|---|
| `Inappropriate ioctl for device` | パスフレーズの入力画面を出せない。`readlink -f /usr/bin/pinentry` が `pinentry-gtk-2` を指し、`DISPLAY` が設定されているか確認する。端末で入力するなら `export GPG_TTY=$(tty)` (`.bashrc` では設定済み) |
| `ssh-add` で `agent refused operation` | gpg-agent が入力画面を出せない。`gpg-connect-agent updatestartuptty /bye` を実行してから試す |
| `cannot run C:\Program Files\...` | `gpg.program` に Windows のパスが入っている。`git config --global gpg.program gpg` |
| GitHub で Unverified になる | 別の鍵で署名している。`git log -1 --show-signature` で鍵 ID を確認する |
