# APIキーなどの秘密情報

APIキーやトークンは、1Passwordのvaultに置く。使うときは`op-run`で、そのコマンドにだけ環境変数として渡す。`.env`や`mise.local.toml`に平文で書かない。

| もの | 置き場所 |
|---|---|
| APIキーの値 | 1Password。リポジトリごとにvaultを分ける(`lattice`、`commandlib`、`noodlemap`) |
| サービスアカウントのトークン | `~/.config/op-run/token.gpg`。自分のGPG鍵で暗号化する。リポジトリには入れない |
| `op`(CLI) | mise(`aqua:1password/cli`、`mise.lock`で固定) |
| `op-run` | chezmoiが`~/.local/bin`に置く。Linuxはbash(`op-run`)、WindowsはPowerShell(`op-run.cmd`と`op-run.ps1`) |

Webサービスのパスワードも1Passwordに置く。デスクトップアプリ(wingetの`AgileBits.1Password`)の設定にある「1Password CLIと連携」は有効にしない。有効にすると、アプリのロックが解けている間、同じユーザーで動く`op`(Claudeも含む)が、本人のアカウントのすべてのvaultを読めるようになるため。`op`はサービスアカウントのトークンでだけ使う。

## 使い方

```bash
op-run noodlemap -- terraform plan
```

1. `~/.config/op-run/token.gpg`を復号する。gpg-agentのキャッシュが切れていれば、パスフレーズの入力画面が出る。
2. vault名からIDを引き、そのvaultのアイテムを取ってくる。
3. アイテムのタイトルを環境変数の名前に、アイテムの秘匿フィールドの値をその値にして、コマンドを実行する。トークンはコマンドに渡さない。

渡す変数の名前だけを確かめるには`op-run --list noodlemap`を使う。値は表示しない。

### プロジェクトで使う

プロジェクトのリポジトリには`op-run`を書かない。OSSとして公開しているので、ほかの人の環境では動かない。リポジトリは環境変数からキーを読むだけにしておき、手元で外から包む。miseのタスクも`mise exec`も、呼び出し元の環境変数を引き継ぐ。

手で包む代わりに、そのリポジトリの`mise.local.toml`(Gitが無視するもの)に、包むためのタスクを1つ置く。値は書かない。

```toml
[tasks.op]
description = "Run a task with the keys of the 1Password vault commandlib"
run = "op-run commandlib -- mise run"
```

```bash
mise run op jev-review main
```

`mise run op`の後の引数は、そのまま中の`mise run`に渡る。`mise exec`で動かすリポジトリでは、`run`を`op-run <vault> -- mise exec --`にする。

- 同じ名前のタスクを`mise.local.toml`に書いて上書きしない。miseはタスクを丸ごと置き換えるので、`usage`や`description`が消え、リポジトリ側の変更にも追従しない。
- `[env]`から`op-run`を呼ばない。そのディレクトリで動くすべてのプロセス(Claudeも含む)にキーが渡り、ディレクトリを移るたびに`op`がネットワークにつながる。
- `.env`や`mise.local.toml`にキーの行が残っていると、miseがそちらの値で上書きする。移したら消す。

PowerShellからは`op-run.ps1`が、`cmd`からは`op-run.cmd`が呼ばれる。

## 端末ごとの準備

1. 1PasswordのWeb画面のDeveloperから、その端末用のサービスアカウントを作る(`windows`、`dev`など)。使うvaultに、読み取りだけの権限を付ける。
2. 表示されたトークンを、その端末で保存する。

   ```bash
   op-run --set-token
   ```

   入力は画面に表示されないので、1回だけ貼り付けてEnterを押す。形式が違うトークン(2回貼り付けたものなど)は保存しない。入力したトークンは`git config --global user.signingkey`の鍵で暗号化される。作成の画面に表示されたトークンは、1Passwordにも、ほかの場所にも残さない。

3. `doctor`の「1Passwordのサービスアカウントのトークン」がPASSになることを確かめる。

端末を作り直したら、古いサービスアカウントをWeb画面で削除する。

`agent`と`research`の環境にはサービスアカウントを作らない。researchのAPIキーはWindows側の`op-run`から`lab.ps1 run`に渡す(`docs/research.md`)。`verify-isolation.sh`が、トークンのファイル、`OP_SERVICE_ACCOUNT_TOKEN`などの1Passwordの環境変数、`op`に追加したアカウント、APIキーの環境変数がないことを確かめる(researchの起動前の検査は、渡した`ANTHROPIC_API_KEY`だけを外した環境で実行する)。

## 秘密情報を足す

Web画面かデスクトップアプリで、そのvaultにアイテムを足す。種類はAPI CredentialかPasswordにし、タイトルを環境変数の名前にする(英数字と`_`)。値は秘匿フィールド(API Credentialの`credential`、Passwordの`password`)に入れる。

次のときは、`op-run`は何も実行せずに失敗する。

- タイトルが環境変数の名前に使えない
- 大文字と小文字だけが違うタイトルが重なっている
- 値の入った秘匿フィールドが1つではない(ログインのアイテムに追加のパスワードを足したときなど)

## リクエストの上限

サービスアカウントのリクエストには上限がある。個人とファミリーのプランでは、アカウントのすべてのサービスアカウントを合わせて1日1,000件まで。`op-run`は1回の実行で、少なくとも、vaultの一覧とアイテムの一覧に1件ずつと、アイテムごとに1件を使う。キーが3つのvaultなら5件以上なので、ループの中で何百回も呼ばない。上限は[Service account rate limits](https://www.1password.dev/service-accounts/rate-limits)にある。

## 守れること、守れないこと

- ディスクに平文のAPIキーを置かない。
- 普段のシェル、IDE、Claudeの環境変数にAPIキーが入らない。
- 1つの端末のトークンが漏れても、届くのはそのサービスアカウントに許したvaultだけ。サービスアカウントには、個人用のvault(Personal)の権限を付けられない。

トークンを復号できる間は、同じユーザーで動くプロセスが`op-run`を実行できる。Claudeも例外ではない。GPGのキャッシュが切れれば入力を求める。キャッシュは最後に使ってから24時間、最長72時間(`docs/gpg.md`)。

被害を小さくするのは、キーの側の設定。用途ごとに別のキーを発行し、使用量の上限や権限を絞る。

## 確かめていること

- `tests/ci/op-run-test.sh`と`tests/ci/op-run-test.ps1`が、偽の`gpg`と`op`で試す。秘密情報が渡ること、トークンが渡らないこと、トークンと名前と秘匿フィールドの検査、終了コード、Windowsで`cmd`を通しても引数が崩れないこと。
- 本物の1Passwordとは、CIで通信しない。
