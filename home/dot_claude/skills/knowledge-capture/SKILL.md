---
name: knowledge-capture
description: 開発中に分かった技術的な知見を、Privateリポジトリmarulabs-knowledgeの調査記録に残す。利用者が/knowledge-captureを実行したとき、または記録を頼んだときに使う。
argument-hint: "[記録する内容のメモ]"
allowed-tools: Bash(git remote -v) Read(~/work/blog/marulabs-knowledge/**) Edit(~/work/blog/marulabs-knowledge/knowledge/**) Bash(git -C ~/work/blog/marulabs-knowledge add *) Bash(git -C ~/work/blog/marulabs-knowledge commit *) Bash(git -C ~/work/blog/marulabs-knowledge status *)
---

# 調査記録を残す

この会話で分かった知見を、`~/work/blog/marulabs-knowledge`の調査記録に書いてコミットする。記録はPrivateで、記事化と公開は別の作業。Draftは作らない。

コマンドは、`~`を展開せず、`$(...)`や変数を入れずに、ここに書いた形のまま実行する。`allowed-tools`の許可がこの文字列に合い、許可の判定もできるようにするため。

1. **所属を確かめる。** 今のディレクトリで`git remote -v`を実行する。remoteが`github.com/Maru32768/`のもの、上流が公開されているOSSのclone、remoteのないリポジトリ、gitのリポジトリでない場所のどれかなら次へ進む。どれでもなければ、所属を利用者に1回だけ尋ねて、このターンを終える。続けてよいと答えが来たら、Skillツールで`knowledge-capture`をもう一度呼んでから2へ進む。`allowed-tools`の許可は、利用者が次のメッセージを送ると消えるため。`~/work/blog/marulabs-knowledge`がなければ、そう返して止まる
2. **書式を読む。** `~/work/blog/marulabs-knowledge/CLAUDE.md`の「絶対のルール」と「調査ログの記録方法」、それに`templates/knowledge.md`。ファイル名、frontmatter、見出し、根拠のラベル、参照の書き方、秘密情報の伏せ方は、これらに従う
3. **既存の記録を探す。** Grepツールで`~/work/blog/marulabs-knowledge/knowledge/`を、`project`の値と、エラーメッセージや関数名で探す。同じ問題の記録があれば、それに追記する。なければ新しく作る
4. **書く。** `type`を選び、その種類の見出しで書く。主張のすべてに根拠のラベルが付き、`[観測]`、`[出典]`、`[再現]`の根拠が同じ記録に貼ってあれば、このステップは終わり
   - 使うのは、この会話に残っている事実だけ。圧縮などで細部が曖昧なら、読み取りだけのコマンド、ファイルの読み直し、`git log`で確かめ直す。状態を変えうるコマンドと、承認を求められるコマンドは再実行しない。確かめられない事実は「記録の時点で確認できなかった」と書くか、`[推論]`か`[仮説]`にする
   - 載せてよいか迷う情報は省き、省いたことを返信に書く
   - `article`を決め、理由を「公開の検討」に書く
5. **コミットする。** `<記録のパス>`はリポジトリからの相対パス。`git -C ~/work/blog/marulabs-knowledge add <記録のパス>`を実行し、続けて`git -C ~/work/blog/marulabs-knowledge commit -m "<記録の内容を表す英語の1文>" -- <記録のパス>`でコミットする。パスを付けるのは、前からステージされていた変更をコミットに入れないため。`git -C ~/work/blog/marulabs-knowledge status --short`の出力に記録のパスがなければ終わり。プッシュは利用者の指示を待つ
6. **返す。** 1〜3行で、記録のパス、`article`の判断、確かめられなかったことや省いたことを書く
