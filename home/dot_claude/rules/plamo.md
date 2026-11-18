# ローカルの翻訳モデル

Windowsでは、翻訳専用のLLMであるPLaMo 3 Translate(日英を含む53言語)を手元のGPUで動かせる(`~/dotfiles/docs/tools.md`)。

- 先に`http://127.0.0.1:8077/health`を見て、`ok`なら起動せずにそのまま使う(ほかのセッションがサーバーを起動していることがある)
- `plamo-server.cmd`は既定で2Bを、`plamo-server.cmd 8b`は8Bを動かす。Git Bashでは拡張子が要る。バックグラウンドで起動すると、`/health`が`ok`を返してから使える。初回はサーバーがモデルを取得する(2Bは1.8GB、8Bは5.3GB)。止めるまで動き続ける
- 訳すときは原文を最後の`user`メッセージにし、`"chat_template_kwargs": {"target_lang": "ja"}`、`"temperature": 0`、`"stop": ["<|plamo:tag|>", "<|plamo:bos|>"]`を付けて`/v1/chat/completions`に送る。訳文は`choices[0].message.content`に入る
- 入力と出力の合計は16,384トークンまでで、同時に送ったリクエストはこれを分け合い、合わせて超えるとすべて失敗する。長い文書は見出しや段落の区切りで分けて、1つずつ送る。`finish_reason`が`stop`でなければ、訳文は途中で切れている。Markdownの構文と行の数はおおむね保たれるが、原文と訳文で行の数を比べて確かめる
- 用語集(`glossary`)、文体(`form`)、前後の文脈(`context`)も指定できる。書き方はモデルカード(https://huggingface.co/pfnet/plamo-3-translate-2b-GGUF)を読む
- 訳文には全角の括弧や、日本語と英数字の間のスペースが混じる。そのまま使わず、`~/.claude/CLAUDE.md`の｢日本語の表記｣の規則に合わせて推敲する
