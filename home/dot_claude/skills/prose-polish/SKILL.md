---
name: prose-polish
description: 日本語と英語の文書を、意味を保ったまま推敲する。説明の組み立てを直し、文書の種類に合うスキルで表面を整え、imos-humanizer スキルでいもすさんのルールを収束するまでかけ、親が差分を読んで反映する。ドキュメントや PR/MR 本文の推敲、「文書を整えて」「推敲して」「polish the docs」で使う。review-loopからも呼ばれる。
---

# 文書の推敲

## 入力

- **対象:** ファイルと、直してよい行範囲。base を渡されたら、`<base>...HEAD` で追加・変更された段落だけを対象にする（新規ファイルは全体）。差分に無い既存の文は直さない。直すと差分が膨らみ、レビュアーが本題を追えなくなる。PR/MR 本文は、GitLab なら `glab mr view -F json --jq .description`、GitHub なら `gh pr view --json body --jq .body` で取る。
- **利用者が持つリポジトリの PR/MR 本文:** remote が GitHub の `Maru32768` のリポジトリでは、本文を読むのは利用者だけなので、2 と 3 を飛ばす。代わりに親が、日本語なら `yomiyasu`（この指示で名前を出して頼まれたものとして扱う）、英語なら `pstack:technical-writing` を 1 回だけかけ、`<work>/pr-body.final.md` に書く。yomiyasuスキルが回すスクリプトも、2と同じく`<work>`で実行する。1 の退避と 4 の反映は同じように行う。
- **作業ディレクトリ `<work>`:** 呼び出し元が渡す(review-loopなら台帳のディレクトリの`prose/`)。渡されなければ、システムプロンプトにscratchpadのディレクトリが書かれていればその下に、無ければ`/tmp`の下に、`prose-polish-<対象の名前>/`を作る。WindowsのGit Bashでは、`cygpath -m`で`C:/...`の形に直したパスを使う。
- **台帳:** 呼び出し元に台帳があれば、採らなかった変更をその「推敲で採らなかった変更」に書く。無ければ報告に書く。
- **文書の規約:** リポジトリの `CLAUDE.md` などに文書の決まり（訳を行ごとに対応させる、表記の規則など）があれば、2 のサブエージェントと 3 の imos-humanizer スキルに制約として渡す。humanizer ルールより優先する。訳と行ごとに対応させている文書では、行を分けたりつないだりさせず、見出し・箇条書き・空行の位置も変えさせない。片方の言語だけ直した行は、対応を検査するリポジトリで引っかかることがあるので、報告に書かせる。

対象にするのは地の文だけ。コード、コードコメント、コードブロック、インラインコード、URL、識別子は残す。`CLAUDE.md` `AGENTS.md` `SKILL.md` などエージェントへの指示ファイルも対象外にする。文体より指示の正確さが優先で、yomiyasu も既定で除外している。

## 道具の選び方

ファイルごとに、地の文の言語と文書の種類で決める。

| 言語 | 文書の種類 | 1段目（順に実行） | 検査 | humanizer ルール |
|---|---|---|---|---|
| 日本語 | すべて | `explain-before-shorten` → `yomiyasu` | `yomiyasu_check.py` の run と verify | `ja` |
| 英語 | 技術文書（README、手順書、API、設計書、PR/MR 本文） | `explain-before-shorten` → `technical-writing` | Vale | `en` |
| 英語 | 読み物（記事、ブログ、告知、エッセイ） | `explain-before-shorten` → `clarity`（rewrite モード） | Vale | `en` |

- Skill ツールに渡す名前は、使えるスキルの一覧の表記に合わせる（`anthropic-skills:explain-before-shorten`、`pstack:technical-writing` のように接頭辞が付くことがある）。
- `explain-before-shorten` は日本語向けに書かれている。英語の文には、その手順をそのまま当てはめる。
- yomiyasu の `--doc-type` は、PR/MR 本文が `pr`、手順書・README が `manual`、設計書・仕様書が `formal`。当てはまらなければ指定しない。読者は `expert`。
- Vale は、対象のリポジトリに `.vale.ini` があればそれを使う。無ければ `--config ~/.claude/skills/prose-polish/vale.ini` を付け、最初に1回 `vale --config ~/.claude/skills/prose-polish/vale.ini sync` でスタイルを取る。

## 手順

1. **親が原文を退避する。** 原文を `<work>/<path>.orig`、PR/MR 本文を `<work>/pr-body.orig.md` に置く。これが検査の `--source` になり、PR/MR 本文を戻すときの控えにもなる。

2. **1ファイル（PR/MR 本文も1件）につきサブエージェントを1つ、同じメッセージで並列に起動する。** worktree は要らない。本体ツリーには書かせない。プロンプトに以下を書く。
   - 表の1段目のスキルを、順に Skill ツールで実行しろ。yomiyasu はこの指示で名前を出して頼まれたものとして扱え（yomiyasu はドキュメントの更新では名前を出されない限り動かない）。yomiyasuスキルが回すlint、run、verifyも、下の日本語の検査と同じ決まりで`<work>`で実行しろ。yomiyasuのSKILL.mdにある「コマンドに`cd`や`&&`を付けない」より、こちらを優先しろ。clarity は rewrite モードで実行し、`[TK: ...]` は本文に入れずに「書き手に確かめたい点」として報告しろ。
   - 原文のパスと、直してよい行範囲（新規ファイルなら全体）。**範囲外の行を変えるな。**
   - 文書の種類と読者。
   - **意味を変えるな。** 主張・条件・確度（「場合がある」「できる」「してよい」）・手順の順序・数値を保て。実装と食い違う記述を見つけても直さず報告しろ（推敲で黙って変えると誰も検証しない）。
   - 推敲稿を `<work>/<path>.h0`（PR/MR 本文は `pr-body.h0.md`）に書き、表の検査を通せ。`--source` には**推敲前の退避**を渡す。1段目の途中稿を渡すと、その組み替えが検査から漏れる。
     - 日本語: `<work>`で実行し、ファイルは`<work>`からの相対パスで渡す。yomiyasuは、実行したディレクトリの外のファイルと、そこからの道筋に点で始まる部分があるパスを読まずに、終了コード2で止まる。語の一覧は`<work>`から上のgitのリポジトリの`.yomiyasu-words/`しか探さないので、対象のリポジトリの最上位に`.yomiyasu-words/`があれば、`--words <その絶対パス>`を足す。

       ```bash
       cd <work> && python3 ~/.claude/skills/yomiyasu/scripts/yomiyasu_check.py run \
         --source <退避した原文> --final <推敲稿> --doc-type <種類> --reader expert \
         --fail-on meaning-risk --fact-gaps --state-dir .yomiyasu
       cd <work> && python3 ~/.claude/skills/yomiyasu/scripts/yomiyasu_check.py verify \
         --final <推敲稿> --state-dir .yomiyasu
       ```

       `--state-dir`を省くと、`<work>`より上にgitのリポジトリがあれば、その直下に`.yomiyasu/`が作られる。終了コード1（meaning-risk）が出たら、その書き換えを戻すか、意味が同じだと言える根拠を報告しろ。
     - 英語: `vale --output=line [--config <上の設定>] <推敲稿>`。指摘があると終了コードは1になる。指摘は直す合図ではなく候補として扱え。直してよい範囲の行の指摘だけを見て、直したか、残した理由を報告しろ。
   - 推敲稿には注記や質問を入れるな。報告は本文で返せ。変えたところ（5点まで）、書き手に確かめたい点、検査の指摘とその扱い（日本語は meaning-risk の候補と verify の出力の2行目）。

3. **imos-humanizer スキルを実行する。** 渡すもの:
   - 対象のファイルと直してよい行範囲、言語、文書の種類と読者、文書の規約（2 と同じ）
   - 作業ディレクトリ `<work>`
   - 原文の退避 `<path>.orig` と、入力稿 `<path>.h0`（PR/MR 本文は `pr-body.orig.md` と `pr-body.h0.md`）
   - 検査: 表の検査。日本語は 2 と同じ yomiyasu の run と verify、英語は 2 と同じ Vale の設定。Vale の指摘は 2 と同じく候補として扱わせる
   - 反映は prose-polish の 4 で行うので、imos-humanizer の 4 は飛ばす

   imos-humanizer は、ファイルごとに採った出力を `<work>/<path>.final`（PR/MR 本文は `pr-body.final.md`）に置き、パス数と収束したかを報告する。ルールが固定した版と違って飛ばしたときは、`.h0` を `.final` にコピーし、そのことを最終報告に書く。

4. **親が反映する。** サブエージェントの推敲を鵜呑みにしない。
   - `diff -u <orig> <final>` を自分で読む。範囲外の行の変化、コードブロック・識別子・数値・リンクの変化は戻す。
   - 主張・条件・確度が動いたものは採らない。確度は弱まった方向も見る（yomiyasu の検査では捕まらず、英語には検査が無い）。原文に無い説明・例・手順が足されていたら戻す。docs は何も受け止めない。採らなかったものは台帳か報告に書く。
   - 「書き手に確かめたい点」は、コードか会話から答えが出るものは親が答えて反映する。出ないものは最終報告に回す。
   - ドキュメントは本体ツリーに反映する。コミットは呼び出し元の流れに従う。単独で使ったときは反映までにして、コミットはユーザーの指示を待つ。
   - PR/MR 本文は `glab mr update <id> --description "$(cat pr-body.final.md)"`（GitHub は `gh pr edit <n> --body-file pr-body.final.md`）で更新し、**取得し直して最終稿と一致するか確認する。** 元に戻すときは `pr-body.orig.md` を同じ手順で書き戻す。

## 失敗モード

| 症状 | 原因 | 対処 |
|---|---|---|
| 推敲で差分が膨らむ | 差分に無い既存の文まで直した | 直してよい行範囲を渡し、範囲外の変化は親が戻す |
| 推敲で仕様が変わる | 「場合がある」の言い切り、「できる」→「する」などの書き換え | 日本語は yomiyasu を `--fail-on meaning-risk` で通し、`--source` には推敲前の退避を渡す。英語は親が diff で見る |
| 言い切りが「〜ことがある」や "may" に弱まる | 確度を弱めた書き換えは yomiyasu の meaning-risk に数えられない | 親が `.orig` との diff で確度を見る |
| docs に検証していない説明が増える | humanizer ルールや clarity が具体例や手順の補足を促す | 足すなと指示し、足された行は親が戻す |
| Vale の指摘を全部直して文が崩れる | 指摘を直す合図として扱った | 候補として扱い、範囲内の行だけ見る |

## 報告

- 推敲したファイルと、PR/MR 本文を更新したか（無くて対象外ならそう書く）。元の本文の控え `pr-body.orig.md` のパス
- 採らなかった変更、答えの出なかった「書き手に確かめたい点」、検査の結果（yomiyasu の verify、Vale の残した指摘）
- imos-humanizer をファイルごとに何パスかけて収束したか（未収束で上限に達したもの、ルールが固定した版と違って飛ばしたものはそう書く）

`<work>` は PR/MR 本文の控えがあるので消さない。
