# Claude Code の設定

Windows と WSL で同じ設定を使うため、共通部分を chezmoi で管理する。

| ファイル | 内容 |
|---|---|
| `home/.claude-settings.json` | 共通の設定 (プラグイン、マーケットプレイス、フックなど) |
| `home/dot_claude/modify_settings.json` | 共通の設定を `settings.json` へマージする (chezmoi のテンプレートなので両 OS で動く)。review-loopが台帳を置くディレクトリへの許可も足す(「review-loopの台帳の置き場」) |
| `home/dot_claude/CLAUDE.md` | ユーザー全体の指示。dotfiles で設定を管理していることのほか、日本語の表記、タスクの進め方、コミットとレビューの決まりと、技術的な知見の記録を提案する決まりを書く。指示として読まれるだけで、強制はしない。`agent` には置かない |
| `home/dot_claude/pstack-models.md` | pstack のロールごとのモデル。`/setup-pstack` が書き、`CLAUDE.md` の `@` 行で読み込む |
| `home/dot_claude/skills/` | 自分で書いたスキル (`docs/skills.md`) |
| `home/.hooks-src/block-signing-bypass/` | 署名の回避を止めるフック (Go) |
| `home/run_onchange_after_20-build-hooks.*` | フックをテストしてビルドする (`.sh` と `.ps1`) |

## 反映

```bash
chezmoi diff    # 差分を見るだけ
chezmoi apply   # 反映する
```

- `settings.json` は Claude Code 自身も書き換えるので、丸ごと置き換えずにマージする。
- Claude Code が書き換えると並び順が変わるので、`chezmoi status` には差分が出続ける。`doctor` はこのファイルを比べず、フックの登録だけを確かめる。
- モデルと effort は画面から変える個人の選択なので、共通の設定に入れない。
- 環境固有のキーは残り、同じキーは共通の設定が優先される。配列は丸ごと置き換わるので、共通の設定にある `hooks.PreToolUse` に環境固有のフックを足しても次の反映で消える。
- フックはソースが変わると自動でテストとビルドが走る。テストが落ちたら置き換えない。

どちらかの環境で `/config` などから変えた設定を共通にしたいときは、`home/.claude-settings.json` に書き写して反映し直す。

## compact

会話をcompactする時期を、既定より早める。main会話は毎回、文脈全体をキャッシュから読み直すので、文脈が小さいほど1回に送るトークンが減る。

- `autoCompactWindow: 500000`: 50万トークンでcompactする。既定では、1Mのモデルで約97万トークンまで待つ。値はモデルのコンテキストウィンドウで頭打ちになる。`/autocompact`で決めた値はモデルごとに`modelSettings`へ保存され、こちらより優先される。
- `idleCompaction: true`: 20万トークン以上の会話から離れると、1時間のキャッシュが切れる前にcompactする。戻ったときに、会話全体をキャッシュへ書き直さずに済む。1時間のキャッシュが使われるのは定額プランのmain会話だけなので、キャッシュが5分で切れるサブエージェントでは動かない。

compactが増えると、序盤の細かい指示が要約で落ちやすくなる。決めたことは会話の外(issue、PR、コミット)に残す。

## review-loopの台帳の置き場

`modify_settings.json`が`permissions.additionalDirectories`に`<ホーム>/.local/state/review-loop`を足す。review-loopは台帳をここに置く(`home/dot_claude/skills/review-loop/SKILL.md`の0)。このディレクトリは作業ディレクトリと同じ扱いになり、読むときに確認が出ない。書き込みの確認は今の権限モードに従い、`acceptEdits`では出ない。

- ほかの置き場は向かない。セッションのscratchpadは、セッションが終わると消えることがあり、別のセッションからは見つからない。リポジトリの`.git`と`.claude`はClaude Codeの保護パスで、書き込みのたびに確認が出る。作業ツリーに置くと、リポジトリごとに無視の規則を足さない限り、台帳が`evidence.sh`の指紋に入る。
- 足すパスはchezmoiの`.chezmoi.homeDir`から作った絶対パスにする。`~`で書いたパスをClaude Codeが展開するかは、公式の文書に書かれていない。
- `additionalDirectories`はファイルを読み書きできるようにするだけで、そこからCLAUDE.md、スキル、設定を読み込まない(公式の文書の「Additional directories grant file access, not configuration」)。
- 台帳を初めて作るまで、このディレクトリは無い。無いディレクトリをClaude Codeがどう扱うかは確かめていない。
- `agent`と`research`には`~/.claude`を置かないので、この許可も入らない。
- `tests/ci/render.sh`は、共通の設定が`permissions`に台帳の置き場だけを足すことと、既存の`permissions.allow`が残ることを確かめる。

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
- 同じソースを Windows 用にもビルドできる。

### テスト

```bash
cd home/.hooks-src/block-signing-bypass && go test ./...
```

止めるコマンドと通すコマンドの一覧は `main_test.go` にある。回避方法を見つけたら、ここにケースを足してからルールを直す。
