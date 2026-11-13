# dotfiles

Windows と WSL (Ubuntu 26.04) の設定と開発ツールを、[chezmoi](https://www.chezmoi.io/) と [mise](https://mise.jdx.dev/) で揃えて管理する。

- 開発環境が壊れても、同じ手順で作り直せる
- Windows と WSL で、設定とツールのバージョンをできるだけ揃える
- Claude などのエージェントを、使い捨ての WSL インスタンスで隔離して動かす

自分の環境向けのもので、名前、メールアドレス、GPG 鍵などは自分のものを決め打ちしている。

## セットアップ

### Windows

`bootstrap.ps1` だけあれば始められる。何度実行してもよい。

```powershell
powershell -ExecutionPolicy Bypass -File bootstrap.ps1
```

winget でアプリを入れ、このリポジトリを `~\dotfiles` に clone し、mise と chezmoi で設定を適用して、`tests\doctor.ps1` で確認する。

### WSL のインスタンス

Windows の PowerShell で、`~\dotfiles` から実行する。既存のインスタンスには触らない。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new dev
```

Ubuntu 26.04 を入れ、root とユーザーの初期設定 (`provision/`) を流し、`tests/doctor.sh` で確認する。パスワードと資格情報は、作ったあとに手で設定する。

```powershell
wsl -d dev -u root passwd maru
```

```bash
~/dotfiles/provision/setup-credentials.sh
```

名前が `agent-` で始まるインスタンスは、エージェント用の隔離した環境になる (`docs/agent.md`)。`research-` で始まると、同じ隔離で Web を読ませる調べもの用の環境になる (`docs/research.md`)。

### 設定を変えたあと

```bash
chezmoi diff    # 差分を見る
chezmoi apply   # 反映する
```

## 構成

```text
home/          chezmoi のソース (.chezmoiroot)
packages/      apt.txt (mise で入らないもの) と winget.json (Windows アプリ)
bootstrap.ps1  Windows の入口
lab/lab.ps1    WSL のインスタンスの作成、削除、復元テスト
provision/     インスタンスの初期設定
tests/         doctor (環境の確認)、verify-isolation (agent と research の隔離の確認)、ci/ (CI の検査)
docs/          設計と、話題ごとの説明
```

## 検査

CI (`.github/workflows/ci.yml`) と同じ検査を手元でも実行できる。

```bash
bash tests/ci/static.sh          # shellcheck、テスト、不変条件、レンダリング、gitleaks、actionlint
bash tests/ci/container.sh main  # コンテナで環境を作って確かめる (agent と research も可)
```

CI で確かめられない WSL の挙動は、`lab.ps1 restore-test` で実物のインスタンスを作って確かめる (`docs/ci.md`)。

## 文書

| 文書 | 内容 |
|---|---|
| [docs/design.md](docs/design.md) | 目的、方針、構成、採用しなかったもの |
| [docs/tools.md](docs/tools.md) | mise によるツールのバージョン管理 |
| [docs/claude.md](docs/claude.md) | Claude Code の設定と、署名の回避を止めるフック |
| [docs/codex.md](docs/codex.md) | Codex の設定 |
| [docs/skills.md](docs/skills.md) | エージェントのスキルの管理 |
| [docs/agent.md](docs/agent.md) | エージェント用の環境と隔離 |
| [docs/research.md](docs/research.md) | Web を読ませる調べもの用の環境と、LAN への通信の制限 |
| [docs/secrets.md](docs/secrets.md) | API キーの扱い (Bitwarden Secrets Manager と `bws-run`) |
| [docs/gpg.md](docs/gpg.md) | GPG のコミット署名 |
| [docs/ci.md](docs/ci.md) | CI、復元テスト、`stable` タグ |
