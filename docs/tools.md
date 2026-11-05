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

mise 本体は `MISE_VERSION` と `$MiseVersion` を書き換える。引数なしの `mise self-update` で上げると、別の環境とずれる。

## 固定できていないもの

| 対象 | 理由 |
|---|---|
| `rust`, `goimports` | rustup と `go install` で入るので、バージョンの固定だけでチェックサムはない |
| Claude Code | 公式のインストーラーで入れて、自動更新に任せている |
| Vim プラグイン | vim-plug が最新を取得する |
| `apt.txt` のパッケージ | Ubuntu の更新に任せる |

## Windows

`aws-cli` は mise では Windows に入らないので、`config.toml` で Linux と macOS に限定し、Windows では `winget` で入れる。
