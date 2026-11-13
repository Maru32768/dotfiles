# research 環境

Claude に Web (`WebSearch`、`WebFetch`) を読ませて、公開されている情報を調べさせるための、使い捨ての WSL インスタンス。名前が `research-` で始まると、このプロファイルで作られる。

隔離の仕組みは agent 環境 (`docs/agent.md`) と同じで、次の点だけが違う。

| 項目 | agent | research |
|---|---|---|
| Web のツール | `WebFetch` と `WebSearch` を拒否する | 許可する (`permissions.allow` に入れるので、確認なしで動く) |
| Bash の通信先 | `allowedDomains` の宛先だけ | なし |
| Bash の書き込み先 | 作業ディレクトリと `~/.npm`、`~/go/pkg` | 作業ディレクトリだけ |
| 資格情報 | 保存したトークン (`CLAUDE_CODE_OAUTH_TOKEN`) | 呼び出し元が渡す API キー (`ANTHROPIC_API_KEY`) |
| ユーザー | `agent` (uid 2000) | `research` (uid 2100) |
| LAN とメタデータの宛先 | サンドボックスの外からは届く | uid で絞ったファイアウォールで拒否する |
| ファイル | `provision/agent/` | `provision/research/` (管理設定、起動の `research-claude.sh`、ファイアウォールの `firewall.sh`、起動時の `boot.sh`) |

ホームのファイルは agent と同じもの (chezmoi のプロファイル `agent`) を置く。Claude Code のバージョンも、agent と同じく `provision/agent/claude-version` で固定する。管理設定は、上の違いのほかは agent と同じでなければならない。`tests/ci/invariants.sh` が比べる。

## 使い方

1 回の調査に 1 つのインスタンスを作り、終わったら消す。スナップショットは取らない。Windows の PowerShell で実行する。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 new research-foo
```

```powershell
bws-run research -- powershell -ExecutionPolicy Bypass -File lab\lab.ps1 run research-foo -Path ~/work/run
```

`run` は Claude を対話で起動する。プロンプトを引数で渡す (`-p`) 方法はない。

```powershell
powershell -ExecutionPolicy Bypass -File lab\lab.ps1 rm research-foo
```

`run` は `ANTHROPIC_API_KEY` がなければ失敗する。`new` と `verify` の検査は、agent と同じく `lab.ps1 token` で保存したトークンを使って Claude を動かすので、API の料金はかからない。

## API キー

- Secrets Manager に、このキーだけを置くプロジェクトを作る (例: `research`)。`bws-run` はプロジェクトの秘密情報をすべて `lab.ps1` の環境変数にするので、ほかのキーと同じプロジェクトに置かない (`docs/secrets.md`)。
- キーは専用の Anthropic のワークスペースで発行し、そのワークスペースに使用量の上限を設定する。インスタンスの中の Claude 本体はキーを持つので、持ち出されたときの被害は上限で抑える。
- `lab.ps1` はキーを保存しない。1 回の `wsl.exe` の実行にだけ `WSLENV` で渡し、終われば `WSLENV` を元に戻す。
- インスタンスの中では、キーは Claude 本体の環境変数にだけある。`sandbox.credentials.envVars` で Bash から隠す。

`research-claude` は、`ANTHROPIC_API_KEY` と `CLAUDE_CODE_OAUTH_TOKEN` のどちらか 1 つだけを受け付ける。どちらもないとき、両方あるときは起動しない。トークンは `lab.ps1 verify` の検査で使う。起動前の `verify-isolation.sh` は `ANTHROPIC_` で始まる環境変数を漏れとみなすので、その検査にだけ `ANTHROPIC_API_KEY` を渡さない。

## ファイルの受け渡し

Windows の Git Bash で実行する。Windows PowerShell 5.1 のパイプとリダイレクトはバイナリを書き換えるので、tar のアーカイブが壊れる。

`research-claude` は Claude を `--setting-sources user` で起動するので、Claude は作業ディレクトリの `.claude/skills` と `.claude/agents` を読まない (Windows の Claude Code 2.1.318 で確認)。スキルとサブエージェントは、Claude が読む research ユーザーの `~/.claude` に置く。

```bash
tar -cf - -C <リポジトリ>/.claude skills/<スキル> agents/<エージェント>.md | wsl.exe -d research-foo --cd '~' -e sh -c 'mkdir -p .claude && tar -xf - -C .claude'
```

調べる対象などの入力は作業ディレクトリに置く。

```bash
tar -cf - <入力> | wsl.exe -d research-foo --cd '~/work' -e sh -c 'mkdir -p run && tar -xf - -C run'
```

結果は tar で受け取る。

```bash
wsl.exe -d research-foo --cd '~/work/run' -e tar -cf - results > results.tar
```

受け取った側では空のディレクトリに展開する。`-P` は付けない (付けると `/` で始まる名前や `..` を含む名前がそのまま展開される)。中身は Web から来たものとして扱い、実行しない。

```bash
tar -tvf results.tar
mkdir results-foo && tar -xf results.tar -C results-foo
```

## 通信の制限

`WebFetch` はサンドボックスの外の Claude 本体から通信するので、サンドボックスでは止まらない。代わりに nftables のルール (`provision/research/firewall.sh`) で、research ユーザーから次の宛先への通信を拒否する。

| 通す | 拒否する |
|---|---|
| `lo` (サンドボックスのプロキシが使う) | IPv4: `0.0.0.0/8`、`10.0.0.0/8`、`100.64.0.0/10`、`169.254.0.0/16`、`172.16.0.0/12`、`192.168.0.0/16`、`224.0.0.0/4`、`240.0.0.0/4` |
| `/etc/resolv.conf` の DNS サーバーへの 53 番 (WSL の DNS トンネル `10.255.255.254` は `lo` に載っているので、`lo` の許可で通る) | IPv6: すべて (LAN の機器や Windows はグローバルなアドレスも持つので、範囲では絞れない) |

- **全インスタンスに効く:** WSL のインスタンスはネットワークの名前空間を 1 つ共有する (`readlink /proc/1/ns/net` が一致する)。ルールは、送り元の uid が 2100 のパケットだけを research のチェーンへ送る。ほかのインスタンスでは uid 2100 を使わない (`provision/root.sh`)。「uid が 2100 でなければ通す」とは書かない。所有者のないパケット (カーネルが返す ICMP や RST、`close()` した後の TCP、NFS などカーネルの中の通信) はどちらの条件にも一致しないので、そう書くと、これらのパケットが拒否のルールまで進み、拒否する宛先へのものは全インスタンスで拒否される。実際に、Windows から WSL への ping が返らなくなった。
- **読み込むとき:** 起動のたびに `wsl.conf` の `[boot] command` (`/usr/local/sbin/research-boot`) が root で読み込む。テーブル `inet research_isolation` を消して作り直すので、何度読み込んでも同じになる。
- **消えるとき:** `wsl --shutdown` まで残る。`lab.ps1 rm` の後も残るが、uid 2100 はほかにないので影響しない。ほかのインスタンスの root が `nft flush ruleset` などを実行しても消える。`research-claude` が確かめるのは起動したときだけなので、実行の途中で消えても気づかない。
- **`flush ruleset` を使わない:** どのインスタンスで実行しても、共有のルールがすべて消える (Docker などのルールも)。`nftables.service` は既定の設定でこれを実行するので、`root.sh` が nftables を入れる前に無効にする。

### 届くもの

- **公開の Web:** 何でも読めて、URL に入れれば何でも送れる。インスタンスには秘密を入れない。
- **localhost:** ほかのインスタンスで待ち受けているサービスにも、Claude 本体からは届く (`WebFetch` で `http://localhost:<ポート>` など)。`lo` に載っている DNS トンネルの `10.255.255.254` にも、53 番以外のポートを含めて Claude 本体から届く。サンドボックスの中の Bash からは届かない。
- **ネットワークのモード:** NAT (既定) を前提にしている。mirrored では `127.0.0.1` への通信が Windows で待ち受けているサービスに届き、`lo` を通すルールでは止まらない。
- **IPv6:** すべて拒否するが、検査は IPv4 だけ。NAT (既定) には IPv6 の経路がない。

## 確かめ方

`tests/verify-isolation.sh` は `/etc/claude-code/isolation-profile` (root 所有、`root.sh` が置く) でプロファイルを決め、プロファイルごとの期待を表から引いて調べる。research では agent の検査に次のものが加わるか変わる。

- 管理設定が上の表のとおりであること。
- サンドボックスの外の research ユーザーから、ゲートウェイの 445 番、`169.254.169.254`、`192.168.0.1`、`10.0.0.1` のそれぞれ 80 番に届かないこと。ルールは宛先を `reject with icmpx admin-prohibited` で拒否するので、`connect()` は時間切れではなくすぐに `No route to host` で失敗する。`No route to host` で失敗するかどうかで、ルールが効いたのか、応答がないだけかを区別する。
- 公開の Web (`https://example.com`) にはサンドボックスの外から届くこと。名前解決は、プロファイルに共通の検査 (`getent hosts github.com`) で確かめる。
- このインスタンスの起動でルールを読み込んだこと。`research-firewall` は読み込んだルールのハッシュを `/run/research-firewall.sha256` に残し、検査は今のルールのハッシュと比べる。テーブルは共有の名前空間に残るので、届かないことだけでは、前に別のインスタンスが読み込んだテーブルと区別できない。
- Claude を動かす検査では、`WebFetch` と `WebSearch` が使えること。サンドボックスのプローブで `net-allowed` と `work-git-https` (Bash の通信) が届かないこと。
- **未検証:** Claude を動かす検査は保存したトークンを使うので、`ANTHROPIC_API_KEY` がサンドボックスの中の Bash から見えないことは、管理設定 (`sandbox.credentials.envVars`) でしか確かめていない。API キーで最初に実行するときに確かめる。

`research-claude` も Claude を起動する前に同じ検査を実行するので、インスタンスの起動時にルールを読み込めていなければ Claude は起動しない。

`tests/ci/container.sh research` は、コンテナに `CAP_NET_ADMIN` を与えてルールを読み込む。コンテナは自分のネットワークの名前空間を持つので、ほかには影響しない。research ユーザーの通信が `No route to host` で拒否され、root と uid 65534 の通信は拒否されないことを確かめる。あわせて、`wsl.conf` の起動時のコマンド、`research-boot` を 2 回実行してもほかのテーブルが残ること、出力のフックが uid 2100 のときだけ jump する形であること、`/run` のハッシュ、資格情報が 2 つまたは 0 のときに `research-claude` が起動しないことを確かめる。
