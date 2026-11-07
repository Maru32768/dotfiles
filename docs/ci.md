# CI

`.github/workflows/ci.yml` が push と週 1 回の定期実行で動く。検査の中身は `tests/ci/` にあり、手元でも同じものを実行できる。

| ジョブ | スクリプト | 内容 |
|---|---|---|
| `static` | `tests/ci/static.sh` | shellcheck、フックのテスト、不変条件、chezmoi のレンダリング、gitleaks、actionlint |
| `container` | `tests/ci/container.sh <main\|agent>` | `ubuntu:26.04` で環境を作り、確認と再適用まで行う |
| `windows` | `tests/ci/windows.ps1` | Windows PowerShell 5.1 での構文と PSScriptAnalyzer |

定期実行は、固定していないもの (apt、インストーラー、Vim プラグイン) の破損に気づくためにある。

## 手元で実行する

```bash
bash tests/ci/static.sh
```

```bash
bash tests/ci/container.sh main
```

```bash
bash tests/ci/container.sh agent
```

`container.sh` は作業ツリーの内容を使うので、コミットの前に試せる。1 回あたり数分かかり、数 GB をダウンロードする。

## 確かめていること

- **`tests/ci/invariants.sh`:** PowerShell のスクリプトが ASCII だけ、mise 本体のバージョンが `user.sh` と `bootstrap.ps1` で同じ、GPG の鍵の指定が同じ、など。コメントや手順でしか守られていない約束をここに移す。
- **`tests/ci/render.sh`:** `linux-main`、`linux-agent`、`windows-main` の 3 通りを描画して適用する。スクリプトは実行しない。
- **agent に置くファイルの一覧:** `render.sh` に書いた一覧と完全に一致しないと失敗する。新しいファイルを足すと必ず失敗するので、そのときに隔離への影響を考えて一覧を直す。

## 確かめられないこと

| 対象 | 理由 | どう確かめるか |
|---|---|---|
| systemd と `wsl.conf` の効果 | コンテナにはない。`doctor.sh --container` は飛ばす | `lab.ps1 new restore-test` |
| agent の隔離 | WSL の設定に依存する。`verify-isolation.sh` はコンテナでは実行しない | `lab.ps1 verify` |
| Windows での適用 | `render.sh` はテンプレートの `.chezmoi.os` を差し替えるだけ。`.ps1.tmpl` の構文も見ない | `bootstrap.ps1` |

## CI の中で使うツール

`gitleaks` と `actionlint` は普段の環境に入れないので、`mise.lock` には載せず、`tests/ci/static.sh` にバージョンを書く。Actions は、タグの付け替えに影響されないようコミットのハッシュで固定する。
