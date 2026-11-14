# CI

`.github/workflows/ci.yml` が push と週 1 回の定期実行で動く。検査の中身は `tests/ci/` にあり、手元でも同じものを実行できる。

| ジョブ | スクリプト | 内容 |
|---|---|---|
| `static` | `tests/ci/static.sh` | shellcheck、フック・`bws-run`・`split-pdf`・`split-pr-stack`・review-loopの`evidence.sh`・`usage-log`・docs-redesignのスクリプトのテスト、不変条件、chezmoi のレンダリング、gitleaks、actionlint |
| `container` | `tests/ci/container.sh <main\|agent\|research>` | `ubuntu:26.04` で環境を作り、確認と再適用まで行う |
| `windows` | `tests/ci/windows.ps1`、`tests/ci/bws-run-test.ps1`、`tests/ci/lab-run-test.ps1` | Windows PowerShell 5.1 での構文、Windows 版の `bws-run` のテスト、`lab.ps1 run`が偽の`wsl.exe`に渡す引数のテスト(Windows PowerShell 5.1とPowerShell 7の両方で動かす)、PSScriptAnalyzer |

定期実行は、固定していないもの (apt、インストーラー、Vim プラグイン) の破損に気づくためにある。

`.github/workflows/update-skills.yml` は、固定したスキルを上げる PR を週 1 回作る (`docs/skills.md`)。書き込みの権限を持つので、CI のワークフローには混ぜない。

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

```bash
bash tests/ci/container.sh research
```

`container.sh` は作業ツリーの内容を使うので、コミットの前に試せる。1 回あたり数分かかり、数 GB をダウンロードする。

## 確かめていること

- **`tests/ci/invariants.sh`:** PowerShell と cmd のスクリプトが ASCII だけ、mise 本体のバージョンが `user.sh` と `bootstrap.ps1` で同じ、GPG の鍵の指定が同じ、など。コメントや手順でしか守られていない約束をここに移す。
- **`tests/ci/render.sh`:** `linux-main`、`linux-agent`、`windows-main` の 3 通りを描画して適用する。スクリプトは実行しない。スキルだけはアーカイブを実際に取ってきて、`SKILL.md` があることまで確かめるので、ネットワークを使う (`docs/skills.md`)。
- **agent に置くファイルの一覧:** `render.sh` に書いた一覧と完全に一致しないと失敗する。新しいファイルを足すと必ず失敗するので、そのときに隔離への影響を考えて一覧を直す。

## 確かめられないこと

| 対象 | 理由 | どう確かめるか |
|---|---|---|
| systemd と `wsl.conf` の効果 | コンテナにはない。`doctor.sh --container` は飛ばす | `lab.ps1 restore-test` |
| agent と research の隔離 | WSL の設定に依存する。`verify-isolation.sh` はコンテナでは実行しない。research の通信の制限だけは、コンテナに `CAP_NET_ADMIN` を与えて試す (`docs/research.md`) | `lab.ps1 restore-test` |
| Windows での適用 | `render.sh` はテンプレートの `.chezmoi.os` を差し替えるだけ。`.ps1.tmpl` の構文も見ない | `bootstrap.ps1` |

## 復元テスト

CI で確かめられないものは、実物の WSL で確かめる。Windows の PowerShell で実行する。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 restore-test
```

GitHub の `master` から `main`、`agent`、`research` を新しく作り、`doctor.sh` と `verify-isolation.sh` で確かめて、消す。途中で失敗しても消す。ほかのインスタンスには触らない。

- 結果は `%LOCALAPPDATA%\dotfiles-lab\restore-test.json`、ログは同じ場所の `restore-test.log` に残る。
- `doctor.ps1` が結果を報告する。失敗しているか、45 日より古ければ TODO になる。
- トークンを保存してあれば、Claude を動かす検査も行う。`-NoClaude` で飛ばせる。
- 実行している `lab.ps1` は手元のものだが、作るものは `master` になる。`lab.ps1` を変えたら `~\dotfiles` も更新する。

### 定期的に実行する

月に 1 回ほど、タスクスケジューラで実行する。ログオン中にしか動かない。逃したときは次にログオンしたときに動く。

```powershell
$action = New-ScheduledTaskAction -Execute powershell -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$HOME\dotfiles\lab\lab.ps1`" restore-test"
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Sunday -At 10am
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName dotfiles-restore-test -Action $action -Trigger $trigger -Settings $settings
```

## stable タグ

復元テストと CI の両方に通ったコミットに `stable` を付ける。署名が要るので、`dev` の端末で実行する。CI や定期実行では付けない。

```bash
bash ~/dotfiles/provision/promote-stable.sh
```

`master` を更新して壊れたら、`stable` から作り直せる。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new dev2 -Branch stable
```

Windows は `bootstrap.ps1 -Branch stable` で同じことができる。どちらもタグを取り出した状態になるので、作業を続けるときは `git switch master` を実行する。

直前の更新を戻すだけなら、`git revert` と `chezmoi apply` で足りる。

## CI の中で使うツール

`gitleaks` と `actionlint` は普段の環境に入れないので、`mise.lock` には載せず、`tests/ci/static.sh` にバージョンを書く。Actions は、タグの付け替えに影響されないようコミットのハッシュで固定する。
