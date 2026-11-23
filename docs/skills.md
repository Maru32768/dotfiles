# エージェントのスキル

GitHub で公開されているスキルを、Windows と `dev` に同じ版で置く。中身はリポジトリに入れず、出どころとコミットだけを書く。

| ファイル | 内容 |
|---|---|
| `home/.chezmoidata/skills.toml` | 第三者のスキルごとの出どころ(`repo`、`path`)、固定するコミット、置く先(省略可) |
| `home/.chezmoiexternals/skills.toml.tmpl` | 一覧からchezmoiのexternalを作る。GitHubのアーカイブから、そのスキルのディレクトリだけを取り出す |
| `home/dot_agents/skills/` | 共通で使う自作のスキルの正本 |
| `home/dot_claude/skills/` | 共通の自作スキルをClaude Codeへ展開する`include`テンプレートと、Claude Code専用の自作スキル(`usage-cap`) |
| `home/dot_gemini/config/skills.json` | Antigravityに`~/.agents/skills`を読ませる設定 |
| `provision/update-skills.sh` | スキルと、コミットに固定したプラグインのマーケットプレイスを、最新のコミットに上げる |

置く先は2つあり、既定では両方に置く。Antigravityは`~/.gemini/config/skills.json`で`~/.agents/skills`を参照するので、複製もシンボリックリンクも増やさずに同じスキルを読める。

| `targets` | 置く場所 | 読むもの |
|---|---|---|
| `claude` | `~/.claude/skills/<名前>` | Claude Code |
| `agents` | `~/.agents/skills/<名前>` | Codex、Antigravity(`~/.gemini/config/skills.json`経由) |

`agent`環境には置かない(`~/.claude`、`~/.agents`、`~/.gemini`を除外する)。`render.sh`が確かめる。

自分で書いたスキルは、共通で使うものを中身ごと`home/dot_agents/skills/<名前>/`に置き、`home/dot_claude/skills/<名前>/`に1行の`include`テンプレート(`{{- include "dot_agents/skills/..." -}}`)を並べて両方へ展開する。Claude Code専用のスキル(`usage-cap`)だけは`home/dot_claude/skills/<名前>/`に直接置く。正本とテンプレートの対応は`invariants.sh`が、展開結果の一致は`render.sh`が確かめる。

`imos-humanizer`が使ういもすさんのルール(`https://imoz.jp/humanizer.<ja|en>.txt`)はライセンスが分からないので、本文を入れずに`home/dot_agents/skills/imos-humanizer/rules.sha256`で版を固定している。`prose-polish`もこのスキルを呼ぶ。上流が更新されるとimos-humanizerの段が飛ばされるので、差分を読んでから`rules.sha256`を書き換える。

```bash
bash ~/.agents/skills/imos-humanizer/scripts/fetch-rules.sh --check
```

差分は、前に照合した版の控え (`~/.cache/imos-humanizer/`) と比べる。控えが無い端末では差分を出せないので、控えのある端末で確かめる。

## 自作のスキルが呼ぶもの

| 呼ぶもの | 呼ぶスキル | 入れ方 |
|---|---|---|
| `gh-stack` | split-pr-stack | `skills.toml` |
| `gh stack` (gh の拡張) | gh-stack | `home/run_onchange_after_50-gh-extensions.*` がタグを固定して入れる |
| `yomiyasu` | prose-polish、imos-humanizer | `skills.toml` |
| `clarity` | prose-polish | `skills.toml` |
| `web-design-guidelines`、`frontend-design` | docs-redesign(サイトの見た目は扱わず、この2つを案内する) | `skills.toml`、プラグイン(`frontend-design`) |
| docs-redesignの`scripts/outline.sh` | docs-overview(見出しの一覧に使う) | 同じく自作のスキルで、`home/dot_agents/skills/docs-redesign/`にある |
| cdnjsの`marked` 12.0.2と`mermaid` 10.9.8 | docs-overview(`scripts/view.sh`が作る表示用のHTMLが、開かれたときに読み込む) | 入れない。版とSRIのハッシュを`view.sh`に固定してある。読み込めないときは、HTMLがMarkdownのまま表示する。版は自動では上がらないので、勧告が出たら`view.sh`と`tests/ci/docs-overview-test.sh`の版とSRIを上げ、`tests/ci/docs-overview-browser-check.md`を`view.sh`で包んでブラウザで開き、確かめ直す |
| `ronny:engineering-small-prs` | split-pr-stack | プラグイン (`home/.claude-settings.json`) |
| `mattpocock-skills:grilling`、`mattpocock-skills:domain-modeling`、`mattpocock-skills:pr` | ship-task | プラグイン (`mattpocock-skills`) |
| `pstack:poteto-mode`、`pstack:technical-writing` | ship-task、prose-polish | プラグイン (`pstack`) |
| `ponytail:ponytail-review` | review-loop | プラグイン (`ponytail`) |
| `codex review` (Codex の CLI) | review-loop | Linux は mise (`docs/codex.md`)、Windows は Codex のアプリ |
| `~/work/blog/marulabs-knowledge` (Private のリポジトリ `Maru32768/marulabs-knowledge`) | knowledge-capture | dotfiles では管理しない。無ければ、スキルが `gh repo clone` で clone する (clone の方式は端末ごとの gh の設定に従う)。記録を調べる gitleaks の版は、marulabs-knowledge の `.mise.toml` と `mise.lock` が固定する |
| デスクトップアプリの`get_usage`ツール、`usage-log cap`が書く`~/.local/state/usage/weekly-cap` | usage-cap | `get_usage`はデスクトップアプリが持つ。`usage-log`はchezmoiが置く(`docs/tools.md`) |
| `explain-before-shorten` | prose-polish | 管理しない。記事 (`https://zenn.dev/microsoft/articles/explain-before-shorten`) に本文があるだけで、リポジトリもライセンスも無い。使う端末に手で置く |

`update-skills.sh` は gh の拡張のタグを上げない。gh-stack の `commit` を上げたら、`run_onchange_after_50-gh-extensions.sh` と `.ps1` のタグも上流の最新のリリースに揃える。

## 方針

- **コミットで固定する:** スキルはエージェントへの指示なので、知らないうちに中身が変わらないようにする。
- **中身を複製しない:** 第三者のファイルを公開リポジトリに載せない。
- **`exact`:** 上流で消えたファイルは手元からも消える。手で足したファイルも次の `chezmoi apply` で消える。

`npx skills add` や `npx skills update` で、ここにあるスキルを入れ直さない。次の `chezmoi apply` で上書きされる。`doctor` では「chezmoi の管理ファイルに差分がない」が失敗する。

管理していないスキルは、置いたままで消えない。`~/.claude/skills/synced` (claude.ai から同期されるもの) などがそれにあたる。

### npx skills から移るとき

`npx skills` は Windows で、`~/.claude/skills/<名前>` を `~/.agents/skills/<名前>` へのジャンクションにすることがある。chezmoi はジャンクションを扱えず、`chezmoi apply` が `unsupported file type` で止まる。先にリンクだけを消す。

```powershell
cmd /c rmdir "$HOME\.claude\skills\rust-skills"
```

`rmdir` はジャンクションそのものだけを消し、リンク先の中身は残す。`Remove-Item -Recurse` はリンク先まで消すことがあるので使わない。

`npx skills` が書き換えていた `SKILL.md` の先頭や、入れていなかったファイル (`metadata.json` など) は、最初の `chezmoi apply` で上流と同じになる。

## 足す

`skills.toml`に項目を足して、反映する。`path`は、リポジトリの中で`SKILL.md`があるディレクトリ。直下なら`""`。`targets`を省くと`["claude", "agents"]`の両方に置かれる。特定の置く先に絞るときだけ`targets`を書く。

```toml
[skills.example]
repo = "owner/name"
path = "skills/example"
commit = "<40桁のハッシュ>"
```

```bash
chezmoi apply
```

## 更新する

`skills.toml`のスキルと、`home/.claude-settings.json`でコミットに固定したプラグインのマーケットプレイス(`docs/claude.md`の｢プラグイン｣)を、同じスクリプトとPRで上げる。

`.github/workflows/update-skills.yml` が週 1 回 (日曜 5:00 JST) `update-skills.sh` を実行し、新しいコミットがあれば `bot/update-skills` ブランチと PR を作る。PR の本文に compare の URL が並ぶので、中身を読む。CI は `GITHUB_TOKEN` の push では動かないので、ワークフローが `workflow_dispatch` で動かす。この CI の結果は PR のチェック欄に出ないので、本文の「CI:」のリンクから見る。

コミットは署名されていない。GitHub の画面からマージせず、署名の鍵がある端末で取り込む。`commit.gpgsign` で署名される。

```bash
cd ~/dotfiles && git pull --ff-only && git fetch origin bot/update-skills && git cherry-pick FETCH_HEAD && git push
```

マーケットプレイスの固定を上げたときは、`chezmoi apply`で反映しても入れたプラグインは前の版のままなので、`docs/claude.md`の｢プラグイン｣の手順で入れ替える。

PR は、次の実行ですべて最新になったと分かったときに閉じられる。すぐ閉じるなら `gh pr close bot/update-skills --delete-branch` を実行する。

手元で確かめるときは、スクリプトを直接実行する。

```bash
bash ~/dotfiles/provision/update-skills.sh --dry-run
```

新しいコミットがあるものと、差分を見るcompareのURLを表示する。中身を読んでから、引数なしで、またはスキルかマーケットプレイスの名前を付けて実行すると、新しいコミットがあるものは、`skills.toml`か`home/.claude-settings.json`で固定したコミットが書き換わる。`home/.claude-settings.json`では、そのマーケットプレイスの`ref`の行だけが変わる。

```bash
bash ~/dotfiles/provision/update-skills.sh rust-skills
```

## 確かめていること

- `render.sh` が、すべてのスキルのアーカイブを取ってきて、どの置く先にも `SKILL.md` があることを確かめる。`path` の書き間違いはここで見つかる。
- `doctor` の「chezmoi の管理ファイルに差分がない」が、手元のスキルが固定した版と違えば失敗する。
