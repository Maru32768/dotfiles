# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Windows と WSL (Ubuntu 26.04) の設定とツールを chezmoi と mise で管理する、公開リポジトリ。設計の全体は `docs/design.md`、話題ごとの詳細は `docs/*.md` にある。挙動を変えたら、対応する文書も直す。文書とコメントは日本語で書く。

## コマンド

```bash
bash tests/ci/static.sh                 # 環境を作らずにできる検査をすべて (shellcheck、フックのテスト、bws-run のテスト、split-pdf のテスト、split-pr-stackのテスト、不変条件、レンダリング、gitleaks、actionlint)
bash tests/ci/invariants.sh             # 不変条件だけ
bash tests/ci/render.sh                 # linux-main / linux-agent / windows-main を描画して置かれるものを確かめる (スキルの取得でネットワークを使う)
bash tests/ci/bws-run-test.sh           # bws-run (bash 版) のテスト
bash tests/ci/split-pdf-test.sh         # split-pdf のテスト (pypdf を PyPI から取得する)
bash tests/ci/split-pr-stack-test.sh    # split-pr-stackのスクリプトのテスト(偽のghで試す。jqをmiseで取得する)
cd home/.hooks-src/block-signing-bypass && go test ./...            # フックのテスト
cd home/.hooks-src/block-signing-bypass && go test -run 'TestName' ./...  # 1 つだけ
bash tests/ci/container.sh main         # ubuntu:26.04 のコンテナで環境を作って確かめる。agent と research も可。数分かかり、数 GB をダウンロードする
bash tests/doctor.sh                    # 今の環境の確認
chezmoi diff && chezmoi apply           # ホームへの反映
```

`container.sh` は作業ツリーの内容を使うので、コミット前に試せる。Windows 側の検査 (`tests/ci/windows.ps1`、`tests/ci/bws-run-test.ps1`) は CI の windows ジョブで動く。CI は `docs/**` と `**.md` だけの変更では動かない。

## 構造の要点

- **chezmoi のソースは `home/`** (`.chezmoiroot`)。`dot_`、`private_`、`executable_`、`modify_`、`run_onchange_after_NN-*`、`.tmpl` は chezmoi の命名規則。ホームのファイルを直接編集せず、ここを編集する。
- **環境は OS とプロファイルの組み合わせ。** プロファイルは `main` (普段の開発) と `agent` (Claude を動かす使い捨ての WSL) で、`DOTFILES_PROFILE` で決まる (`home/.chezmoi.toml.tmpl`)。インスタンスの `research` (Web を読ませる使い捨ての WSL) は、ホームに `agent` のファイルを置く。どの環境に何を置かないかは `home/.chezmoiignore` で決める。
- **agent に置くファイルの一覧は `tests/ci/render.sh` に書いてあり、完全一致で検査する。** `home/` にファイルを足すと必ず失敗するので、隔離への影響を考えてから一覧を直す。
- **Claude Code と Codex の設定はマージする。** `home/.claude-settings.json` と `home/.codex-config.toml` が共通部分で、`home/dot_claude/modify_settings.json` と `home/dot_codex/modify_config.toml` が既存のファイルへマージする。配列は丸ごと置き換わる。モデルと effort は共通の設定に入れない (`docs/claude.md`)。
- **`home/dot_claude/CLAUDE.md` はユーザー全体の指示** (`~/.claude/CLAUDE.md`) で、このファイルとは別物。
- **スキル:** 第三者のものは `home/.chezmoidata/skills.toml` に出どころとコミットだけを書き、external で取ってくる。中身はリポジトリに入れない。自作のものは `home/dot_claude/skills/<名前>/` に中身ごと置く (`docs/skills.md`)。
- **ツール:** mise の `home/dot_config/mise/config.toml` と `mise.lock` で固定する。mise で入らないものだけ `packages/apt.txt`、Windows アプリは `packages/winget.json` (`docs/tools.md`)。
- **入口:** Windows は `bootstrap.ps1`、WSL のインスタンスは `lab/lab.ps1` (Windows 側から作成・削除・`restore-test`) が `provision/root.sh` と `provision/user.sh` を流す。
- **agent の隔離:** `provision/agent/` (管理設定 `managed-settings.json`、起動の `agent-claude.sh`、固定する Claude Code のバージョン `claude-version`)。効果は `tests/verify-isolation.sh` が実際に試す。`allowWrite` に足した場所は `agent-claude.sh` で先に作る (`docs/agent.md`)。
- **research の隔離:** agent と同じ隔離に、`provision/research/` (管理設定、起動の `research-claude.sh`、uid 2100 の通信で LAN の宛先を拒否する `firewall.sh`) を足す。プロファイルごとの違いは `lab/lab.ps1` の `$Profiles`、`provision/root.sh`、`tests/verify-isolation.sh` の表にある。管理設定は決めた違いのほかは agent と同じで、`tests/ci/invariants.sh` が比べる。nftables のルールは全インスタンスで共有されるので、uid で絞る (`docs/research.md`)。

## 守ること

- `tests/ci/invariants.sh` が検査している約束: PowerShell と cmd のスクリプトは ASCII だけ (Windows PowerShell 5.1 は BOM なしの UTF-8 を、cmd はコードページの違う文字を読み違える)。mise 本体のバージョンは `provision/user.sh` の `MISE_VERSION` と `bootstrap.ps1` の `$MiseVersion` で揃える。GPG のフィンガープリントは各スクリプトで揃える。
- PowerShell のスクリプトは Windows PowerShell 5.1 でも動くように書く。
- 改行は LF (`.gitattributes`)。
- 公開リポジトリなので、秘密情報を入れない (gitleaks が履歴すべてを調べる)。API キーは Bitwarden Secrets Manager と `bws-run` で渡す (`docs/secrets.md`)。
- CI の Actions はコミットのハッシュで固定する。CI 専用のツール (gitleaks、actionlint) のバージョンは `tests/ci/static.sh` に書き、`mise.lock` には載せない。
- `block-signing-bypass` フックが署名を回避する操作を拒否する。署名できないときは回避せず、失敗を報告して止まる。止めるコマンドと通すコマンドの一覧は `main_test.go` にあり、ルールを直す前にケースを足す。
- コミットメッセージは日本語。1 行目に変更の要約、本文に理由を書く。
