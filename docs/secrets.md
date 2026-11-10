# API キーなどの秘密情報

API キーやトークンは、Bitwarden Secrets Manager に置く。使うときは `bws-run` で、そのコマンドにだけ環境変数として渡す。`.env` や `mise.local.toml` に平文で書かない。

| もの | 置き場所 |
|---|---|
| API キーの値 | Secrets Manager。リポジトリごとにプロジェクトを分ける (`lattice`、`commandlib`、`noodlemap`) |
| マシンアカウントのトークン | `~/.config/bws/token.gpg`。自分の GPG 鍵で暗号化する。リポジトリには入れない |
| `bws` (CLI) | mise (`bitwarden-secrets-manager`、`mise.lock` で固定) |
| `bws-run` | chezmoi が `~/.local/bin` に置く。Linux は bash (`bws-run`)、Windows は PowerShell (`bws-run.cmd` と `bws-run.ps1`) |

Web サービスのパスワードは、Secrets Manager とは別の、Bitwarden のパスワードの金庫に置く。こちらの CLI (`bw`) は入れない。ログインしたセッションが残ると、同じユーザーの Claude が金庫全体を読めてしまうため。

## 使い方

```bash
bws-run noodlemap -- terraform plan
```

1. `~/.config/bws/token.gpg` を復号する。gpg-agent のキャッシュが切れていれば、パスフレーズの入力画面が出る。
2. プロジェクト名から ID を引き、そのプロジェクトの秘密情報を取ってくる。
3. 秘密情報の名前をそのまま環境変数の名前にして、コマンドを実行する。トークンはコマンドに渡さない。

渡す変数の名前だけを確かめるには `bws-run --list noodlemap` を使う。値は表示しない。

### プロジェクトで使う

プロジェクトのリポジトリには `bws-run` を書かない。OSS として公開しているので、ほかの人の環境では動かない。リポジトリは環境変数からキーを読むだけにしておき、手元で外から包む。mise のタスクも `mise exec` も、呼び出し元の環境変数を引き継ぐ。

手で包む代わりに、そのリポジトリの `mise.local.toml` (Git が無視するもの) に、包むためのタスクを 1 つ置く。値は書かない。

```toml
[tasks.bws]
description = "Run a task with the keys of the Bitwarden project commandlib"
run = "bws-run commandlib -- mise run"
```

```bash
mise run bws jev-review main
```

`mise run bws` の後の引数は、そのまま中の `mise run` に渡る。`mise exec` で動かすリポジトリでは、`run` を `bws-run <プロジェクト> -- mise exec --` にする。

- 同じ名前のタスクを `mise.local.toml` に書いて上書きしない。mise はタスクを丸ごと置き換えるので、`usage` や `description` が消え、リポジトリ側の変更にも追従しない。
- `[env]` から `bws-run` を呼ばない。そのディレクトリで動くすべてのプロセス (Claude も含む) にキーが渡り、ディレクトリを移るたびに `bws` がネットワークにつながる。
- `.env` や `mise.local.toml` にキーの行が残っていると、mise がそちらの値で上書きする。移したら消す。

PowerShell からは `bws-run.ps1` が、`cmd` からは `bws-run.cmd` が呼ばれる。

## 端末ごとの準備

1. Bitwarden の Web 画面で、その端末用のマシンアカウントを作る (`windows`、`dev` など)。使うプロジェクトに、読み取りだけの権限を付ける。
2. アクセストークンを発行して、その端末で保存する。

   ```bash
   bws-run --set-token
   ```

   入力は画面に表示されないので、1 回だけ貼り付けて Enter を押す。形式が違うトークン (2 回貼り付けたものなど) は保存しない。入力したトークンは `git config --global user.signingkey` の鍵で暗号化される。発行の画面に表示されたトークンは、ほかに残さない。

3. `doctor` の「Bitwarden Secrets Manager のトークン」が PASS になることを確かめる。

端末を作り直したら、古いマシンアカウントのトークンを Web 画面で失効させる。

`agent` 環境にはマシンアカウントを作らない。`verify-isolation.sh` が、トークンのファイル、`BWS_ACCESS_TOKEN`、Bitwarden CLI のログイン、API キーの環境変数がないことを確かめる。

## 秘密情報を足す

Web 画面で、そのプロジェクトに秘密情報を足す。名前は環境変数の名前にする (英数字と `_`)。使えない名前や、大文字と小文字だけが違う名前が重なっていると、`bws-run` は何も実行せずに失敗する。

## 守れること、守れないこと

- ディスクに平文の API キーを置かない。
- 普段のシェル、IDE、Claude の環境変数に API キーが入らない。
- 1 つの端末のトークンが漏れても、届くのはそのマシンアカウントに許したプロジェクトだけ。パスワードの金庫には届かない。

トークンを復号できる間は、同じユーザーで動くプロセスが `bws-run` を実行できる。Claude も例外ではない。GPG のキャッシュが切れれば入力を求める。キャッシュは最後に使ってから 24 時間、最長 72 時間 (`docs/gpg.md`)。

被害を小さくするのは、キーの側の設定。用途ごとに別のキーを発行し、使用量の上限や権限を絞る。

## 確かめていること

- `tests/ci/bws-run-test.sh` と `tests/ci/bws-run-test.ps1` が、偽の `gpg` と `bws` で試す。秘密情報が渡ること、トークンが渡らないこと、トークンと名前の検査、終了コード、Windows で `cmd` を通しても引数が崩れないこと。
- 本物の Secrets Manager とは CI で通信しない。
