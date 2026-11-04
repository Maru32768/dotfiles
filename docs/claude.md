# Claude Code の設定

Windows と WSL で同じ設定を使うため、共通部分を `claude/` で管理する。

| ファイル | 内容 |
|---|---|
| `claude/settings.json` | 共通の設定 (モデル、プラグイン、マーケットプレイス、フックなど) |
| `claude/hooks/block-signing-bypass/` | 署名の回避を止めるフック (Go) |
| `scripts/008_claude.sh` | 上記を両環境へ反映する |

## 反映

```bash
./scripts/008_claude.sh --check   # 差分を見るだけ
./scripts/008_claude.sh           # 反映する
```

`install.sh` からも実行される。

- `settings.json` は Claude Code 自身も書き換えるので、symlink にせずマージする。
- 環境固有のキーは残り、同じキーは `claude/settings.json` が優先される。配列は丸ごと置き換わるので、共通設定にある `hooks.PreToolUse` に環境固有のフックを足しても次の反映で消える。
- 上書きする前に、元のファイルを `settings.json.bak.<時刻>` として残す。
- フックは WSL 上の Go でテストしてから、Linux 用と Windows 用をビルドして `~/.claude/hooks/` に置く。Windows に Go は要らない。
- フックのソースを変えたら、再実行するまで反映されない。

どちらかの環境で `/config` などから変えた設定を共通にしたいときは、`claude/settings.json` に書き写して反映し直す。

## 署名回避を止めるフック

Bash / Edit / Write の実行前に動き、コミット署名を回避する操作を拒否する。

| 種類 | 例 |
|---|---|
| 署名を外すフラグ | `--no-gpg-sign`, `git tag --no-sign` |
| 一時的な設定の上書き | `git -c commit.gpgsign=false`, `git -c gpg.program=...` |
| 署名設定の変更 | `git config commit.gpgsign false`, `--unset` |
| 環境変数での回避 | `GIT_CONFIG_GLOBAL=...`, `HOME=... git` |
| `git commit` を通らないコミット | `git commit-tree`, `git fast-import` |
| 設定ファイルの直接編集 | `.gitconfig`, `.git/config` |

設定の読み取りと通常の `git commit` は通る。署名できないときは、Claude が失敗を報告して止まるので、自分のターミナルでコミットする。

発動の確認は、Claude に次の無害なコマンドを実行させる。拒否されれば動いている。

```bash
true # hook test: --no-gpg-sign
```

### 制限

- コマンド文字列の照合なので、スクリプトファイルに書いて実行するなどの方法はすり抜ける。
- 禁止フラグに言及しただけのコマンド (コミットメッセージや `grep`) も拒否される。
- フックの起動に失敗すると、エラーを報告してコマンドは実行される。
- Windows ではコマンドの書き方が Git Bash 前提で、PowerShell では動かない。Claude Code は Git Bash があればそれを使う。
- Claude がフック自体や `settings.json` を書き換えることは止めていない。

確実に止めるには、GitHub のブランチ保護で署名を必須にする。

### Go で書いている理由

- Bash / Edit / Write の実行ごとに動くので、起動が速いほうがよい。計測では WSL で 4 ms、Windows で約 29 ms (Git Bash の起動分を除く) で、Perl や node より速かった。
- ビルド済みのバイナリを置くので、実行する環境にランタイムが要らない。
- `GOOS=windows` で WSL から Windows 用をビルドできる。

### テスト

```bash
cd claude/hooks/block-signing-bypass && go test ./...
```

止めるコマンドと通すコマンドの一覧は `main_test.go` にある。回避方法を見つけたら、ここにケースを足してからルールを直す。
