# APIキー

APIキーは`.env`や`mise.local.toml`に書かない。1Passwordのvaultに置き、`op-run <vault> -- <コマンド>`で外から渡す。リポジトリに`mise.local.toml`の`op`タスクがあれば`mise run op <タスク>`を使う。OSSのリポジトリには`op-run`を書かない(`~/dotfiles/docs/secrets.md`)。
