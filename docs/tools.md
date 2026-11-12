# 開発ツールのバージョン管理

ツールは mise で入れて、どの環境でも同じバージョンになるように固定する。

| ファイル | 役割 |
|---|---|
| `home/dot_config/mise/config.toml` | どこまで自動で上げてよいか (例: `python = "3.14"`) |
| `home/dot_config/mise/mise.lock` | 正確なバージョン、URL、チェックサム (Linux と Windows の両方) |
| `provision/user.sh` の `MISE_VERSION`、`bootstrap.ps1` の `$MiseVersion` | mise 本体のバージョン (揃える) |
| `packages/apt.txt` | mise で入らないもの (バージョンは Ubuntu に任せる) |

## 更新する

`dev` で実行する。

```bash
cd ~/dotfiles/home/dot_config/mise
cp config.toml mise.lock ~/.config/mise/
cd ~
mise lock --global --bump              # lock を最新にする
mise install
bash ~/dotfiles/tests/doctor.sh
cp ~/.config/mise/mise.lock ~/dotfiles/home/dot_config/mise/
```

動作を確かめてからコミットする。1 つだけ上げるときは `mise lock --global --bump python` のように指定する。

マイナーバージョンをまたぐときは (Python の 3.14 から 3.15 など)、先に `config.toml` を書き換える。

mise 本体は `MISE_VERSION` と `$MiseVersion` を書き換える。ずれていると CI が失敗する。引数なしの `mise self-update` で上げると、別の環境とずれる。 Windows の mise は winget で入れているので、バージョンが違ってもセットアップは止めず、警告だけ出す。

## プロジェクトの mise.lock

`lockfile = true` は全プロジェクトに効くので、`.mise.toml` のあるリポジトリで `mise install` すると、そこにも `mise.lock` ができる。`lockfile = false` にするとグローバルの `mise.lock` も無視されて固定が効かなくなるので (古いバージョンをロックに書いて確かめた)、設定は外さない。

代わりに `~/.config/git/ignore` で `mise.lock` と `.mise/` を無視する。追跡済みのファイルには影響しない。プロジェクトで新しく `mise.lock` をコミットするときは `git add -f` を使う。

## 固定できていないもの

| 対象 | 理由 |
|---|---|
| `rust`, `goimports` | rustup と `go install` で入るので、バージョンの固定だけでチェックサムはない |
| Claude Code (`main`) | 公式のインストーラーで入れて、自動更新に任せている。`agent` はバージョンを固定する (`docs/agent.md`) |
| Vim プラグイン | vim-plug が最新を取得する。`linux.vimrc` が変わると、足りないものを導入し直す |
| エージェントのスキル | コミットで固定するが、チェックサムはない (`docs/skills.md`) |
| `apt.txt` のパッケージ | Ubuntu の更新に任せる |

## PLaMo 3 Translate

翻訳専用のLLMであるPLaMo 3 Translateを、Windowsのllama.cppで動かす。`plamo-server`(既定は2B、`plamo-server 8b`で8B)が、OpenAI互換のAPIを`http://127.0.0.1:8077`で提供する。モデルは初回の起動でHugging Faceから`~/.cache/huggingface/hub`に取得する(2Bは1.8GB、8Bは5.3GB)。使い方(翻訳の向き、用語集、文体の指定)はモデルカード(https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF)にある。

- llama.cppのWindows向けのビルドはプレリリースにしかなく、`latest`では取得できない。上げるときは`config.toml`のタグ(`b12317`など)を書き換えて`mise lock --global`する
- CUDA版は本体とcudartが別のzipで、miseでは片方しか入らないので、Vulkan版にしている。GTX 1080で測った速さ(Q4_K_M、トークン/秒)は次のとおりで、翻訳時間のほとんどを占める生成の速さはCUDA版と変わらない(約6,900字を2Bで25秒)

| ビルド | 2Bの入力の処理 | 2Bの生成 | 8Bの入力の処理 | 8Bの生成 |
|---|---:|---:|---:|---:|
| CUDA 12.4 | 1863 | 85 | 638 | 35 |
| Vulkan | 883 | 94 | 263 | 36 |

- 8Bは16kの文脈でVRAMを7.7GB使うので、ほかのアプリがGPUを使っていると足りなくなる
- CORSは既定ですべてのオリジンを許すので、ブラウザで開いたページから応答を読めないように`--cors-origins localhost`で絞る

## Windows

`aws-cli` は mise では Windows に入らないので、`config.toml` で Linux と macOS に限定し、Windows では `winget` で入れる。
