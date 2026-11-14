# agent 環境

Claude を確認の少ない設定で動かすための、使い捨ての WSL インスタンス。名前が `agent-` で始まると、このプロファイルで作られる。

Web を読ませて調べものをさせるときは、同じ隔離をもとにした research 環境を使う (`docs/research.md`)。

## 使い方

Windows の PowerShell で実行する。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new agent-foo
```

トークンは最初に 1 回だけ保存する。`claude setup-token` の出力を、次のコマンドの入力欄に貼る。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 token
```

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 run agent-foo -Path work/repo
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 verify agent-foo
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 rm agent-foo
```

`-Path` はインスタンスの中のパスで、`/` か `~` で始まらなければホームからの相対パスとみなす。省くと `~/work` で動く。`~/work/repo` とは書かない。PowerShell 7 は先頭の `~` を Windows のホームに展開し、`bws-run` を通すと引用符で囲んでも展開される (PowerShell 7.6 で確認)。`-Prompt '<プロンプト>'` を付けると、対話の代わりに `claude -p` で 1 回だけ実行する。サンドボックスは作業ディレクトリへの書き込みを許すので、ホームでは起動しない。`rm` で消せるのは `agent-*`、`research-*`、`restore-test*` だけ。ほかは `wsl --unregister` を自分で実行する。

## コードの受け渡し

インスタンスに資格情報がないので、公開リポジトリは中で `git clone` する。非公開のリポジトリは手元から渡す。

```bash
git bundle create - --all | wsl.exe -d agent-foo --cd '~' -e sh -c 'cat > /tmp/in.bundle && git clone /tmp/in.bundle work/repo && rm /tmp/in.bundle'
```

成果物は署名なしの `agent/*` ブランチで受け取り、内容を確認してから手元で署名する。

```bash
wsl.exe -d agent-foo --cd '~/work/repo' -e git bundle create - agent/foo > agent-foo.bundle
```

```bash
git fetch agent-foo.bundle agent/foo:agent/foo
```

## 隔離の層

| 層 | 内容 |
|---|---|
| インスタンス | `wsl.conf` で interop と automount を無効化。共有される `/mnt/wsl` と WSLg のマウントを外す (`provision/agent/isolate-mounts.sh`) |
| ユーザー | `sudo` なし。uid は 2000 で、普段のユーザー (1000) と分ける |
| 資格情報 | SSH キー、GPG 鍵、AWS を入れない。トークンはインスタンスに保存しない |
| Claude の設定 | root 所有の `/etc/claude-code/managed-settings.json` (`provision/agent/managed-settings.json`) |
| サンドボックス | Bash が書けるのは作業ディレクトリと、`allowWrite` に挙げたキャッシュだけ。サンドボックスを使えないときは起動しない |
| 通信 | Bash からは `allowedDomains` の宛先だけ。`api.anthropic.com` は入れない |
| ツール | `WebFetch` と `WebSearch` を無効化。`/proc` の読み取りとシェルの設定ファイルの書き換えを拒否する |
| リポジトリの設定 | `--setting-sources user` で読まない (フックや `apiKeyHelper` はサンドボックスの外で動く) |
| 拡張 | フック、MCP、プラグインを管理設定で閉じる。chezmoi の `.claude` も適用しない |

権限モードは `acceptEdits`。作業ディレクトリの中の編集と、サンドボックスの中の Bash は確認なしで動く。それ以外は確認を求める。bypass モードは禁止している。

## 確かめ方

`tests/verify-isolation.sh` が、設定を読むだけでなく実際に試す。トークンを保存してあれば、`lab.ps1 new`、`lab.ps1 verify`、`lab.ps1 restore-test` で Claude も動かす。`-NoClaude` を付けると動かさない。

| 区分 | 内容 |
|---|---|
| 外から試す | 実物の `whoami.exe` を起動できないこと (`lab.ps1` がインスタンスにコピーする) |
| OS | `sudo`、Windows のドライブ、共有マウント、秘密鍵に届かないこと。管理設定を書き換えられないこと |
| サンドボックス | `tests/sandbox-probe.sh` を Claude に実行させ、ホームへの書き込みや、許可していない宛先、共有ネットワーク上のポート、トークンに届かないこと。commit など開発の作業はできること |
| 対照 | 同じプローブをサンドボックスの外で実行し、検出できることを確かめる |
| ツール | `Read` で `/proc` を読めず、`~/.bashrc` に書けないこと。規則は `/proc/version` で必ず確かめる。プロセスの環境変数は、ルールが効かなくてもトークンが漏れないよう、目印だけを持つプロセスで試す。モデルが試さなかったときは NOTE にする (下の「拒否ルールの検査」) |

agent と research のどちらとして調べるかは、`root.sh` が置く `/etc/claude-code/isolation-profile` で決まる。このファイルがないと FAIL にして agent として調べるので、置く前に作ったインスタンスは作り直す。プロファイルごとに違う期待 (uid、Web のツール、Bash の通信先と書き込み先、隠す環境変数、プローブで届くのが正しいもの、LAN の検査) は、`verify-isolation.sh` の先頭の表にまとめてある。

`dev` で実行すれば FAIL が並ぶので、検査が失敗を検出できることも確かめられる。

```bash
wsl.exe -d dev -e bash -s -- --exe /mnt/c/Windows/System32/whoami.exe < tests/verify-isolation.sh
```

起動の前にも `provision/agent/agent-claude.sh` が同じ検査を実行し、FAIL があれば起動しない。ただしこのときは Claude を動かす検査を行わない。

### 拒否ルールの検査

`verify-isolation.sh` は Claude に `/proc/version` と目印のプロセスの `/proc/<PID>/environ` を `Read` させ、最大 3 回試す。

- `/proc/version` は必ず判定する。その `Read` の結果が拒否のエラーで、中身を含まなければ PASS。モデルが Bash で読んだ結果は見ない (サンドボックスの中の Bash は読める)。
- 環境変数は、モデルが試したときだけ判定する。試さなければ NOTE。2026-11-07 の `restore-test` で、3 回とも試さずに失敗した。応答の記録が残っておらず、原因は分かっていない (同じ指示を `dev` の Haiku に与えると試した)。
- どちらかを試さなかったときは、モデルが呼んだツールと最後の返答を出力する。

## Claude Code のバージョン

Claude Code の更新でサンドボックスの挙動が変わることがあるので、隔離を確かめたバージョンに固定する。

- バージョンは `provision/agent/claude-version` に書く。`root.sh` が root 所有で `/etc/claude-code/claude-version` に置き、インストーラーにそのバージョンを渡す。
- `verify-isolation.sh` が実物のバージョンと比べる。違えば起動前の検査で止まる。
- `DISABLE_AUTOUPDATER` を `agent-claude.sh` と管理設定で指定する。ただし、ログインしていない環境では自動更新が起きず、効果は確かめられていない。`claude update` はこの指定があっても更新する (2.1.317 で確認)。止める手段として頼りにしているのは、上の検査のほう。

上げるときは `claude-version` を書き換えて、インスタンスを作り直す。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new agent-foo
```

トークンを保存してあれば、`new` が Claude を動かす検査まで行う。このファイルを置く前に作ったインスタンスは検査に通らないので、作り直す。

## トークン

`claude setup-token` のトークンを使う。Max プランの枠を使うので、追加の費用はかからない。公式文書によると、できるのはモデルへのリクエストだけで、有効期限は 1 年。**失効の方法は公式文書に書かれていない。** 持ち出されうるものとして扱う。

| 場所 | 扱い |
|---|---|
| Windows | `%LOCALAPPDATA%\dotfiles-lab\claude-oauth-token.dpapi` に DPAPI で暗号化して保存 |
| 起動時 | `lab.ps1` が 1 回の `wsl.exe` にだけ `WSLENV` で渡す |
| インスタンス | Claude 本体の環境変数にだけある。`sandbox.credentials.envVars` で Bash から隠す |

`/proc/<PID>/environ` は、Claude 2.1.318 の `Read` では組み込みの制限でも読めない。`Read(//proc/**)` の拒否ルールはその上の保険で、ルールだけの効果は `/proc/version` で確かめた (ありなら拒否され、なしなら読める)。

Windows のユーザー環境変数には入れない。Windows 上の Claude Code でも `/login` より優先されてしまう。

API キーで動かすのは research 環境で、キーは呼び出し元が `bws-run` で渡す (`docs/research.md`)。

## CLAUDE_CODE_SUBPROCESS_ENV_SCRUB を使わない理由

トークンをサブプロセスから消す機能だが、Claude Code 2.1.318 で試すと次のことが起きたので、管理設定には入れない。`verify-isolation.sh` でも有効にしていないことを確かめている。

- 権限モードが `default` に固定され、`autoAllowBashIfSandboxed` も効かない。Bash が毎回確認を求める
- `--allowedTools` で Bash を許可すると、ホームの直下に書ける (なしなら `Read-only file system` で拒否される)。ネットワークの制限と `~/.local/bin` への書き込みの拒否は効いている
- 作業ディレクトリに空の `package.json`、`.env`、`yarn.lock` などを作って残す
- それらを `.git/info/exclude` に追記するので、本物の `package.json` を新しく作っても `git status` に出ない

## 既知の制限

- **カーネルを共有する:** 各インスタンスは同じ VM で動く (`boot_id` が一致する)。悪意あるコードを閉じ込める壁としては弱い。信頼できないリポジトリには devcontainer か `wslc` を使う。
- **ネットワークを共有する:** IP アドレスも待ち受けポートも、ほかのインスタンスと同じものが見える。`wsl.conf` では分離できない。サンドボックスの中の Bash からは届かないが、外で動くもの (Claude 本体) からは届く。
- **ツールはサンドボックスの外で動く:** `Read`、`Edit`、`Write` を止めるのは権限ルールだけ。
- **許可した宛先へは持ち出せる:** たとえば攻撃者のトークンで `github.com` に push できる。
- **起動前の検査は自己申告:** 検査のスクリプトは `agent` ユーザーのものなので、中で書き換えられていれば信用できない。怪しければ作り直す。
- **WSLENV の値は環境変数:** 同じユーザーのプロセスなら `/proc` から読める。サンドボックスの中からは見えないことを確かめている。

## 変更するとき

通信先や書き込み先は `provision/agent/managed-settings.json` を編集して、インスタンスを作り直す。`allowWrite` に足した場所は、`agent-claude.sh` で先に作っておく。サンドボックスの中からは作れない。拒否ルールなど research と共通の部分を変えたら、`provision/research/managed-settings.json` も揃える。`tests/ci/invariants.sh` が比べる。

`/mnt/wsl` は全インスタンスで共有される。`isolate-mounts.sh` のように private にしてから外す。そのまま外したり、上に別のものをマウントしたりすると、ほかのインスタンスの Docker Desktop に影響する恐れがある。
