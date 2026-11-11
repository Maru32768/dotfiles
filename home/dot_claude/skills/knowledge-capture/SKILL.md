---
name: knowledge-capture
description: 開発中に分かった技術的な知見を、Privateリポジトリmarulabs-knowledgeの調査記録に残す。利用者が/knowledge-captureを実行したとき、または記録を頼んだときに使う。
argument-hint: "[記録する内容のメモ]"
allowed-tools: Bash(git remote -v) Read(~/work/blog/marulabs-knowledge/**) Edit(~/work/blog/marulabs-knowledge/knowledge/**) Bash(git -C ~/work/blog/marulabs-knowledge add *) Bash(git -C ~/work/blog/marulabs-knowledge commit *) Bash(git -C ~/work/blog/marulabs-knowledge status *)
---

# 調査記録を残す

この会話で分かった知見を、`~/work/blog/marulabs-knowledge`の調査記録に書いてコミットする。記録はPrivateで、記事化と公開は別の作業。Draftは作らない。

コマンドは、`~`を展開せず、`$(...)`や変数を入れずに、ここに書いた形のまま実行する。`allowed-tools`の許可がこの文字列に合い、許可の判定もできるようにするため。

1. **所属を確かめる。** `~/work/blog/marulabs-knowledge`がなければ、`git clone git@github.com:Maru32768/marulabs-knowledge.git ~/work/blog/marulabs-knowledge`で用意できると返して止まる。WSLのmainにはあり、Windowsには別にcloneしない限りない。あれば、今のディレクトリで`git remote -v`を実行する。remoteが`github.com/Maru32768/`のもの、上流が公開されているOSSのclone、remoteのないリポジトリ、gitのリポジトリでない場所のどれかなら次へ進む。どれでもなければ、所属を利用者に1回だけ尋ねて、このターンを終える。続けてよいと答えが来たら、Skillツールで`knowledge-capture`をもう一度呼んでから2へ進む。`allowed-tools`の許可は、利用者が次のメッセージを送ると消えるため
2. **書式を読む。** `~/work/blog/marulabs-knowledge/CLAUDE.md`の全体と`templates/knowledge.md`を読む。ファイル名、`<area>`、frontmatter、見出し、根拠のラベル、参照の書き方、秘密情報の伏せ方は、これらに従う
3. **既存の記録を探す。** Grepツールで`~/work/blog/marulabs-knowledge/knowledge/`を、`project`の値と、エラーメッセージや関数名で探す。同じ問題の記録があれば、それに追記する。なければ新しく作る
4. **書く。** `type`を選び、その種類の見出しで書く。主張のすべてに根拠のラベルが付き、`[観測]`、`[出典]`、`[再現]`の根拠が同じ記録に貼ってあれば、このステップは終わり
   - 使うのは、この会話に残っている事実だけ。圧縮などで細部が曖昧なら、今のディレクトリと`~/work/blog/marulabs-knowledge`の中を読むコマンドとファイルの読み直しだけで確かめ直す。その外を読むコマンドは承認を求められ、状態を変えうるコマンドは副作用を繰り返すので、どちらも再実行しない。確かめられない事実は、CLAUDE.mdの書き方に従って書く
   - 載せてよいか迷う情報は省き、省いたことを返信に書く
   - `article`を決め、理由を「公開の検討」に書く
5. **コミットする。** `<記録のパス>`はリポジトリからの相対パス。先に`mise -C ~/work/blog/marulabs-knowledge exec -- gitleaks dir --no-banner --redact -v --exit-code 3 <記録のパス>`を、ほかのコマンドをつなげずに実行する。終了コードはBashツールの結果に出る。gitleaksの版はmarulabs-knowledgeの`.mise.toml`と`mise.lock`で決まる。終了コードが0なら次へ進む。3なら、出力の`Line`と`RuleID`が示す値を`[REDACTED]`に置き換えて、もう一度実行する。誤検出だと判断した値は、CLAUDE.mdの書き方に従って印を付けて残し、もう一度実行して0になるのを確かめ、そのことを返信に書く。それ以外の終了コードは検査の失敗なので、コミットせずに出力を返して止まる。次に`git -C ~/work/blog/marulabs-knowledge add <記録のパス>`を実行し、続けて`git -C ~/work/blog/marulabs-knowledge commit -m "<記録の内容を表す英語の1文>" -- <記録のパス>`でコミットする。パスを付けるのは、前からステージされていた変更をコミットに入れないため。`git -C ~/work/blog/marulabs-knowledge status --short`の出力に記録のパスがなければ終わり。プッシュは利用者の指示を待つ
6. **返す。** 1〜3行で、記録のパス、`article`の判断、確かめられなかったことや省いたことを書く
