# dotfiles の設計

## 目的

1. 開発環境が壊れても、簡単に作り直せる
2. Windows と WSL の設定とツールを、できるだけ揃える
3. Claude などのエージェントを、使い捨ての環境で安全に動かす

## 基本方針

**どの環境も壊して作り直せる状態にする。** 復元、OS の更新、エージェント用の環境は、同じ手順で作る。

| 管理するもの | 手段 | 理由 |
|---|---|---|
| 設定ファイル | chezmoi (`home/`) | Windows にも実ファイルを置ける。環境の違いをテンプレートで表せる |
| 開発ツール | mise (`home/dot_config/mise/`) | Windows と WSL でバージョンを揃えられる。`mise.lock` で固定する (`docs/tools.md`) |
| エージェントのスキル | chezmoi の external (`home/.chezmoidata/skills.toml`) | 出どころとコミットだけを書き、中身は取ってくる (`docs/skills.md`) |
| Claude Code と Codex の設定 | chezmoi の `modify_` | アプリも書き換えるので、共通の部分だけをマージする (`docs/claude.md`、`docs/codex.md`) |
| OS パッケージ | `packages/apt.txt` | mise で入らないものだけに絞り、OS 更新の影響を減らす |
| Windows アプリ | `packages/winget.json` | `winget import` で入れる |
| インスタンスの作成と削除 | `lab/lab.ps1` | Windows 側にあるので、WSL が壊れていても動く |
| 確認 | `tests/doctor.sh`、CI (`docs/ci.md`) | 作り直せたことを機械的に確かめる |
| 秘密情報 | リポジトリに入れない | 公開リポジトリのため |
| API キー | Bitwarden Secrets Manager と `bws-run` | 使うコマンドにだけ渡す (`docs/secrets.md`) |

作業データは対象外。

## 構成

```text
.chezmoiroot             chezmoi のソースが home/ だと示す
home/                    chezmoi のソース
  .chezmoi.toml.tmpl     プロファイルと共通の値
  .claude-settings.json  Claude Code の共通設定
  .codex-config.toml     Codex の共通設定
  .chezmoidata/          スキルの一覧
  .chezmoiexternals/     スキルを取ってくる external
  .hooks-src/            フックのソース
  run_*                  ツールの導入やフックのビルド
packages/                apt.txt と winget.json
bootstrap.ps1            Windows の入口
provision/               インスタンスの初期設定
lab/lab.ps1              インスタンスの作成と削除
tests/                   doctor.sh と doctor.ps1 (環境の確認)、verify-isolation.sh (agent の隔離の確認)
  ci/                    CI の検査。手元でも実行できる
.github/workflows/       CI (docs/ci.md)
docs/
```

## Windows のセットアップ

```powershell
powershell -ExecutionPolicy Bypass -File bootstrap.ps1
```

`winget` でアプリを入れ、リポジトリを `~\dotfiles` に clone し、mise と chezmoi で設定を適用して `tests\doctor.ps1` で確認する。

| 対象 | 扱い |
|---|---|
| `.gitconfig`, `.ideavimrc`, mise の設定 | WSL と同じ内容 |
| `.vimrc` | VS Code の Vim 拡張用 (`home/.vimrc-files/vscode.vimrc`)。Linux 用とは別 |
| `.bashrc`, `.bash_profile` | Git Bash 用。mise を優先する |
| PowerShell の profile | mise を有効にする。プロジェクトの環境変数も direnv ではなく mise で扱う。パスは OneDrive の `Documents` 前提 |
| スキル | WSL と同じもの (`docs/skills.md`) |
| Codex の設定 | Windows だけ (`docs/codex.md`) |
| `.tmux.conf`, `.ssh`, `.gnupg` など | 管理しない (`home/.chezmoiignore`) |

Windows ではシステムの `PATH` がユーザーの `PATH` より先に来るので、`C:\Program Files\Go` などが mise より優先される。Git Bash と PowerShell では profile で mise を優先するが、IDE のように profile を読まないプロセスにはシステムのものが見える。

## インスタンスの作り方

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new dev
```

1. `wsl --install` で Ubuntu 26.04 を入れる (既存のインスタンスには触らない)
2. root で OS パッケージ、ユーザー、`wsl.conf` を設定する
3. ユーザーで mise と chezmoi を入れ、設定を適用する
4. `doctor.sh` で確認する

対話が必要なものは、作成後に手で行う。

```powershell
wsl -d dev -u root passwd maru
```

```bash
~/dotfiles/provision/setup-credentials.sh
```

## 資格情報

| 環境 | SSH キー | GPG 署名鍵 |
|---|---|---|
| Windows | 既存の `~/.ssh/github` | 正式な鍵 |
| `dev` | 環境ごとに新規作成して GitHub に登録 | 正式な鍵を取り込む |
| `agent` | 持たない | 持たない |

- `~/.ssh` と `~/.gitconfig` を Windows へのリンクにしない。WSL が単体で復元できなくなり、隔離とも両立しないため。
- SSH キーは環境ごとに作り直せるので、バックアップしない。作り直したら古い鍵を GitHub から消す。
- SSH キーのパスフレーズも gpg-agent で扱う。入力はポップアップで、キャッシュは GPG と同じ (最後に使ってから 24 時間、最長 72 時間)。
- 長く保管する秘密は GPG 鍵だけ (`docs/gpg.md`)。
- パスワードマネージャーは Bitwarden。構築の前提にはしない。`agent` ではログインしない。
- API キーは Secrets Manager に置き、`bws-run` で渡す。`.env` や `mise.local.toml` に平文で書かない (`docs/secrets.md`)。

## エージェント用の環境

WSL の分離だけには頼らず、インスタンス、ユーザー、資格情報、Claude の設定、サンドボックス、通信の層を重ねる。成果物は署名なしの `agent/*` ブランチで受け取り、確認してから署名する。詳しくは `docs/agent.md`。

WSL の各インスタンスは VM とカーネルを共有するので、悪意あるコードを閉じ込める壁としては弱い。信頼できないリポジトリには devcontainer や `wslc` を使う。隔離の効果は `tests/verify-isolation.sh` で実際に試して確かめる。

## 進める順番

1. `dev` (Ubuntu 26.04) を chezmoi と mise で作る
2. Windows に同じ chezmoi と mise を適用する
3. `lab` に `agent` プロファイルを足し、隔離のテストを作る
4. GitHub Actions と定期的な `lab.ps1 restore-test` で、復元できることを確認し続ける (`docs/ci.md`) ← 今ここ
5. `wslc` を評価する

## 採用しなかったもの

| 候補 | 理由 |
|---|---|
| `do-release-upgrade` | 20.04 からは 22.04、24.04 を経由する必要があり、やり直しも利かない |
| Nix / home-manager | Windows を同じ仕組みで扱えない |
| Ansible | この規模には重い |
| cloud-init | `wsl -u root` で十分で、仕組みを増やさずに済む |
| `winget configure` | アプリの一覧を入れるだけなら `winget import` で足りる。管理者権限も要らない |
| `wslu` | 廃止されていて、Ubuntu 26.04 に候補がない |
