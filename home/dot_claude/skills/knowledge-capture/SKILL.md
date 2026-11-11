---
name: knowledge-capture
description: 開発中に分かった技術的な知見を、Privateリポジトリmarulabs-knowledgeの調査記録に残す。利用者が/knowledge-captureを実行したとき、または記録を頼んだときに使う。
argument-hint: "[記録する内容のメモ]"
allowed-tools: Bash(git remote -v) Read(~/work/blog/marulabs-knowledge/**) Edit(~/work/blog/marulabs-knowledge/knowledge/**) Bash(git -C ~/work/blog/marulabs-knowledge add *) Bash(git -C ~/work/blog/marulabs-knowledge commit *) Bash(git -C ~/work/blog/marulabs-knowledge status *)
---

# 調査記録を残す

この会話で分かった知見を、`~/work/blog/marulabs-knowledge`の調査記録に書いてコミットする。記録はPrivateで、記事化と公開は別の作業。Draftは作らない。

コマンドは、`~`を展開せず、`$(...)`や変数を入れずに、ここに書いた形のまま実行する。`allowed-tools`の許可がこの文字列に合い、許可の判定もできるようにするため。

1. **所属を確かめる。** 今のリポジトリで`git remote -v`を、ほかのコマンドとつなげずに実行する(`allowed-tools`の許可がこの文字列に合う)。remoteが`github.com/Maru32768/`のもの、上流が公開されているOSSのclone、remoteのないリポジトリのどれかなら次へ進む。どれでもなければ、所属を利用者に1回だけ確かめ、答えを待つ。`~/work/blog/marulabs-knowledge`がなければ、そう返して止まる
2. **書式を読む。** `~/work/blog/marulabs-knowledge/CLAUDE.md`の「調査ログの記録方法」と`templates/knowledge.md`。frontmatter、見出し、根拠のラベルは、この2つに従う
3. **既存の記録を探す。** Grepツールで`~/work/blog/marulabs-knowledge/knowledge/`を、`^project: <リポジトリ名>`と、エラーメッセージや関数名で探す。同じ問題の記録があれば、それに追記して`updated`を今日にする。なければ`knowledge/<area>/YYYY-MM-DD-<リポジトリ名>-<topic>.md`を作る
4. **書く。** `type`を選び、その種類の見出しで書く。主張のすべてに根拠のラベルが付き、`[観測]`、`[出典]`、`[再現]`の根拠が同じ記録に貼ってあれば、このステップは終わり
   - 使うのは、この会話に残っている事実だけ。圧縮などで細部が曖昧なら、コマンドの再実行、ファイルの読み直し、`git log`で確かめ直す。確かめられない事実は「記録の時点で確認できなかった」と書くか、`[推論]`か`[仮説]`にする
   - エラー、コマンド、出力、スタックトレースは原文で貼る。トークン、キー、パスワード、接続文字列は`[REDACTED]`に置き換える。載せてよいか迷う情報は省き、省いたことを返信に書く
   - ソースは`path:line`にバージョンかコミットを添える。修正したコミットは`<リポジトリ名>@<短いハッシュ>`で書く
   - `article`を決め、「公開の検討」に理由を1〜2行で書く
5. **コミットする。** `<記録のパス>`はリポジトリからの相対パス。`git -C ~/work/blog/marulabs-knowledge add <記録のパス>`を実行し、続けて`git -C ~/work/blog/marulabs-knowledge commit -m "<記録の内容を表す英語の1文>" -- <記録のパス>`でコミットする。パスを付けるのは、前からステージされていた変更をコミットに入れないため。`git -C ~/work/blog/marulabs-knowledge status --short`の出力に記録のパスがなければ終わり。プッシュは利用者の指示を待つ
6. **返す。** 1〜3行で、記録のパス、`article`の判断、確かめられなかったことや省いたことを書く
