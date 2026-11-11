# Codex の設定

Codex は今のところ Windows で使う。Windows の CLI は Codex のアプリが入れる。

Linux (main と agent) には、review-loop の codex review に使う CLI だけを mise で入れる。`~/.codex` の設定は管理しない。使う前に、main で 1 度 `codex login` する。agent ではログインしないので、CLI があっても動かない。

| ファイル | 内容 |
|---|---|
| `home/.codex-config.toml` | 共通の設定 |
| `home/dot_codex/modify_config.toml` | 共通の設定を `~/.codex/config.toml` へマージする |

`config.toml` は Codex 自身も書き換えるので、Claude Code の `settings.json` と同じく、丸ごと置き換えずにマージする (`docs/claude.md`)。

- 環境固有のキーは残り、同じキーは共通の設定が優先される。配列は丸ごと置き換わる。
- マージした結果はキーの順に並べ直され、`'...'` のキーは `"..."` になる。中身は変わらない (実際の設定で、72 個のキーがすべて同じ値で残ることを確かめた)。
- Codex が書き直すと書式が戻るので、`chezmoi status` には差分が出続ける。`doctor.ps1` はこのファイルを比べない。
- `config.toml` が TOML として読めないと、`chezmoi apply` が失敗する。中身は書き換えない。

## 共通にするもの、しないもの

| 共通にする | 共通にしない |
|---|---|
| `approvals_reviewer`、`[windows] sandbox`、`[features]`、`[notice]`、`[desktop]` | `model` と effort (画面から変える個人の選択) |
| git のマーケットプレイス | `projects` の信頼 (環境ごとのパス) |
| 有効にするプラグイン | アプリが書き込む `notify`、`mcp_servers.node_repl`、`local` のマーケットプレイス (固有のパスやパイプ名を含む) |
| | `hooks.state` の信頼のハッシュ |

ほかに管理しないもの:

- `~/.codex/rules/default.rules` は、承認したコマンドがたまったもの。プロジェクトのパスを多く含む。
- `auth.json`、履歴、セッション、sqlite、キャッシュ。

画面から変えた設定を共通にしたいときは、`home/.codex-config.toml` に書き写して反映し直す。

## 確かめていないこと

新しい Windows で、`openai-bundled` などアプリが登録するマーケットプレイスより先にプラグインを有効にしたとき、Codex がどう扱うか。
