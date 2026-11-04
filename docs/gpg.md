# GPG コミット署名

コミットは GPG 署名する (`commit.gpgsign = true`)。GitHub に登録している鍵は次の 1 本だけ。

| 項目 | 値 |
|---|---|
| 鍵 ID | `78324D99D34D3111` |
| フィンガープリント | `7AF93B4735CF2AAC930EF5CD78324D99D34D3111` |
| 種類 | rsa4096 (2026-04-14 作成) |

WSL には GitHub に登録していない古い鍵 `87D535BB8566CC0A` も残っている。`user.signingkey` を設定しているので署名には使われない。

## Windows と WSL の関係

- `~/.gitconfig` は Windows 側 `C:\Users\maru3\.gitconfig` への symlink で、両環境で共有している (`scripts/005_wsl_windows.sh`)。
- `gpg.program = gpg` なので、各環境の `PATH` で解決される。

| 環境 | 使われる gpg | 鍵の場所 |
|---|---|---|
| Windows | `C:\Program Files\Git\usr\bin\gpg.exe` | `C:\Users\maru3\.gnupg` |
| WSL | `/usr/bin/gpg` | `~/.gnupg` |

Kleopatra 系の `%APPDATA%\gnupg` は別の場所で、署名には使っていない。

`.gitconfig` に Windows のパスを書くと WSL で動かなくなる (その逆も同じ) ので、`gpg.program` にはパスを書かない。

## 新しい環境のセットアップ

1. `./install.sh` を実行する。`scripts/004_git.sh` が署名設定を、`scripts/007_gpg.sh` がキャッシュ時間を設定する。
2. バックアップから秘密鍵を取り込む。パスフレーズの入力があるので、対話できる端末で実行する。

   ```bash
   ./scripts/gpg_import_key.sh <エクスポートした秘密鍵ファイル>
   ```

   フィンガープリントが違うファイルなら、何も変更せずに終了する。

3. 署名を確認する。

   ```bash
   echo test | gpg -u 78324D99D34D3111 --clearsign > /dev/null && echo OK
   ```

Windows がすでにセットアップ済みなら、バックアップの代わりに直接取り込むこともできる。

```bash
"/mnt/c/Program Files/Git/usr/bin/gpg.exe" --armor --export-secret-keys 78324D99D34D3111 | gpg --import
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

WSL では `pinentry-gtk2` を使い、WSLg のポップアップで入力する。`scripts/000_apt.sh` が入れる。

- `/usr/bin/pinentry` は `update-alternatives` の自動選択で `pinentry-gtk-2` を指す (優先度が `pinentry-curses` より高い)。
- `~/.gnupg/gpg-agent.conf` の `pinentry-program` は JetBrains IDE が書き込んだ `pinentry-ide.sh` を指しているが、IDE の外では `/usr/bin/pinentry` を呼ぶので同じポップアップが出る。
- 端末を持たないプロセス (Claude のコミットなど) でも `DISPLAY` があればポップアップが出るはず。キャッシュが切れた状態では未確認。

## キャッシュ時間

パスフレーズのキャッシュは WSL で 8 時間にしている。`GPG_CACHE_TTL_SECONDS` で変えられる。

```bash
GPG_CACHE_TTL_SECONDS=3600 ./scripts/007_gpg.sh
```

- キャッシュが有効な間は、Claude を含む同じユーザーのプロセスがパスフレーズなしで署名できる。
- 再読み込みするとキャッシュは消える。WSL が停止したときも消える。
- Windows 側の `gpg-agent` には適用していない。

## トラブルシュート

| 症状 | 原因と対処 |
|---|---|
| `Inappropriate ioctl for device` | パスフレーズの入力画面を出せない。`readlink -f /usr/bin/pinentry` が `pinentry-gtk-2` を指し、`DISPLAY` が設定されているか確認する。端末で入力するなら `export GPG_TTY=$(tty)` (`.bashrc` では設定済み) |
| `cannot run C:\Program Files\...` | `gpg.program` に Windows のパスが入っている。`git config --global gpg.program gpg` |
| GitHub で Unverified になる | 別の鍵で署名している。`git log -1 --show-signature` で鍵 ID を確認する |
