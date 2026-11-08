# エージェントのスキル

GitHub で公開されているスキルを、Windows と `dev` に同じ版で置く。中身はリポジトリに入れず、出どころとコミットだけを書く。

| ファイル | 内容 |
|---|---|
| `home/.chezmoidata/skills.toml` | スキルごとの出どころ (`repo`、`path`)、固定するコミット、置く先 |
| `home/.chezmoiexternals/skills.toml.tmpl` | 一覧から chezmoi の external を作る。GitHub のアーカイブから、そのスキルのディレクトリだけを取り出す |
| `provision/update-skills.sh` | 固定したコミットを最新に上げる |

置く先は 2 つある。

| `targets` | 置く場所 | 読むもの |
|---|---|---|
| `claude` | `~/.claude/skills/<名前>` | Claude Code |
| `codex` | `~/.agents/skills/<名前>` | Codex など |

`agent` 環境には置かない。`render.sh` が確かめる。

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

`skills.toml` に項目を足して、反映する。`path` は、リポジトリの中で `SKILL.md` があるディレクトリ。直下なら `""`。

```toml
[skills.example]
repo = "owner/name"
path = "skills/example"
commit = "<40 桁のハッシュ>"
targets = ["claude", "codex"]
```

```bash
chezmoi apply
```

## 更新する

```bash
bash ~/dotfiles/provision/update-skills.sh --dry-run
```

新しいコミットがあるものと、差分を見る compare の URL を表示する。中身を読んでから、引数なしか、スキルの名前を付けて実行すると `skills.toml` が書き換わる。

```bash
bash ~/dotfiles/provision/update-skills.sh rust-skills
```

## 確かめていること

- `render.sh` が、すべてのスキルのアーカイブを取ってきて、どの置く先にも `SKILL.md` があることを確かめる。`path` の書き間違いはここで見つかる。
- `doctor` の「chezmoi の管理ファイルに差分がない」が、手元のスキルが固定した版と違えば失敗する。
