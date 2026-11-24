# 規則の元になった実績と参考資料

規則を変えるときに、なぜその規則があるかを確かめるために読む。

## 実績

**ベース ref を1回だけ計算して固定する**

> 実績: これを省いた初回、レビュアーが `master...HEAD`（16コミット/66ファイル）を見て、3件中2件が範囲外の指摘になった。

**検証コマンドを特定する**

> 実績: Docker が落ちていて DB エミュレータが無く、backend のテスト全体が
> 610秒後にテストランナーの panic で落ちた。ドメイン層だけを回すコマンドを台帳に書いてからは誰も踏まなくなった。
> このとき**「全件は未検証」は最終報告に必ず書く。** 通ったことにしない。

**テスト品質トラックにだけ書くこと**

> 実績: test 側の Must はほぼ全部これ由来。「出力形式の定数を別の値に変えてもフロントの全件が緑」「置換の再走査を戻しても全件緑」は、読むだけでは出てこなかった。

**直す前に、自分で再現する**

> 実績: 「エディタ用スキーマが古く30ファイルの作者が誤エラーを踏む」という指摘は、該当機能を使う定義がゼロで**前提が誤り**だった。逆に「引数によるコンパイル時の縛りは効かない」は `tsc` で再現でき、設計をやり直す根拠になった。

**mutation 由来の指摘を直したら、同じ mutation をもう一度当てる**

> 実績: 「`value: ""` の選択肢を持つフィクスチャを足した」あと、そのフィクスチャを丸ごと消しても
> 全件緑のままだった。テストが「空文字を返すこと」しか主張しておらず、ガードが先に空文字を
> 返すのでフィクスチャの有無で結果が変わらなかった。**次のラウンドの Should で検出された。**

> 実績: mutation を戻すつもりの `git checkout` で、同じファイルに入れた `ItemId` 削除を1回失った。

**docs とコメントの修正こそ裏を取る**

> 実績: 3件の重い指摘のうち2件が、親が前のラウンドで入れた docs 修正の退行だった。
> - 「この検証に引っかかったら `.value` を使え」と書いたが、直前で名指しした項目の `value` は
>   内部ID。従うと画面にIDが出る定義が出荷される
> - 「この項目の行も参照先に使える」と書いたが、その項目の定義側 label は内部コード名で、
>   利用者が見る文字列は実行時に組み立てられる別物だった
>
> どちらも「対象を列挙する」「代替を案内する」という**親切のつもりの加筆**で入った。
> 列挙と案内は、断定した瞬間に検証対象になる。

**停止と未解決の扱い**

> 実績1: 5ラウンドで収束。ラウンドごとの Must+Should は 8 → 5 → 7 → 5 → 1 → 0。
> **3ラウンド目以降も Must が出た**ので、2ラウンドで切り上げていたら退行を見逃していた。
> 一方で最後の1件は既存の分岐だったので、当時は上限を4とした。
>
> 2026-11の見直しで、上限を3回にした。R2〜R4で直した29件のうち23件は、前のラウンドの修正が
> 持ち込んだものだった。回を足すと、レビュアーは主に直前の修正の退行を拾うので、R3でも必ず直すものが
> 出たら、直さずに止めて、設計の前提を利用者に戻す(SKILL.mdの「流れと停止条件」)。
>
> 実績2: Must+Should が 6 → 2 → 2 → 2 で止まらなかった回。数字が動かなくても
> **レビュアーが同じ場所を巡回していたのではなく、毎回別の層に降りていた**
> （実装 → フィクスチャ → docs の案内 → 第1層スキーマ）。
> 「Should が減らない」は打ち切りの理由になるが、**巡回しているかどうかは件数ではなく
> 指摘の中身で判断する。**

## 参考資料（方針の根拠と限界）

- [claude.dev: How the Claude Code team does code review (2026-10)](https://claude.dev/blog/solving-code-review-at-anthropic/) — 上限、差分限定の再レビュー、同型指摘の集約、incident由来の評価セット。**Anthropicの運用例。記事の上限は3ラウンド。**
- [Google: State of Mutation Testing at Google (2018)](https://research.google/pubs/state-of-mutation-testing-at-google/) — diffベースのmutation選択と低価値な変異の除外。
- [StrykerJS: Configuration / Incremental](https://stryker-mutator.io/docs/stryker-js/incremental/) — per-test coverage、差分実行、キャッシュの制限。**テスト依存の選択がいつでも完全であるとは限らない。**
- [Anthropic: Finding bugs with Claude and property-based testing (2026-01)](https://www.anthropic.com/research/property-based-testing) — 性質の抽出と自動生成テストによる検証。生成した性質が仕様と一致するかは別途確認が要る。
- [TestSuiteBench (2026-10)](https://arxiv.org/abs/2610.13065) — LLM生成テストの実行成功とmutation検出能力の差。
- [How effective are traditional test criteria at detecting bugs in large language models generated code? (2026-09)](https://arxiv.org/abs/2609.09315) — LLMが書いたテストは、欠陥を約33%で踏むが、検出は1〜2%。期待値を仕様から作り直すと、最もよい場合で1%から28.6%に上がる。mutationを満たすテストは、カバレッジを満たすテストをわずかに上回るだけ。**関数の水準の課題と、小さいモデルでの結果。**
- [On the Risks of using LLM-Generated Tests for Regression Testing (2026-10)](https://arxiv.org/abs/2610.11835) — 145件のPRで、生成した回帰テストの8〜17%が、欠陥のある振る舞いを期待値にしていた。欠陥を見つけるテストは2.4〜4.8%。
- [On the risk of coding before testing (2026-07)](https://arxiv.org/abs/2607.05139) — 欠陥のあるコードを見てから作ったテストは欠陥の14%を、見ずに作ったテストは25%を検出した。
- [Validation Evidence in LLM Repair Agents (2026-07)](https://arxiv.org/abs/2607.28871) — 修正のエージェントで、通った検証の46.0%は、直す前と後のコードを区別しない。**区別を促す介入の効果(7.8ポイント)は、著者が先に決めた意味のある大きさ(10ポイント)に届いていない。**
- [Meta: Just-in-Time Catching Test Generation (2026-01)](https://arxiv.org/abs/2601.22832) — 差分そのものを変異とみなして、親のコミットと区別するテストを作る。技術者に報告した41件のうち、本物は8件。
- [Test Coverage Analysis of Agentic Pull Requests (2026-07)](https://arxiv.org/abs/2607.18057) — エージェントのPR 4,882件で、エラー処理(tryとcatch)の変更は、Javaの86.0%、Pythonの81.0%がテストに実行されない。
- [PROBE (2026-10)](https://arxiv.org/abs/2610.35987) — エージェントの指摘のうち、対応すべき入力の扱いの欠落は8%。メンテナが直した欠陥では18%。**リポジトリ全体から欠陥を探す課題で、差分のレビューではない。**
- [Maintaining Benchmarks Against Increasingly Capable Agents (2026-09)](https://arxiv.org/abs/2609.34262) — 通った実行3,810件から、検査をすり抜けて通したものを数えた。検査の側を直すと、すり抜けは届かなくなった。**モデルの間の比較は、条件を揃えていない。**
- [The Range Shrinks, the Threat Remains (2026-11のv4)](https://arxiv.org/abs/2605.17062) — 2026年のモデル5つで、挙げたパッケージ名の3.6〜5.0%が実在しない。**査読の無い、1人の著者の再現。**
- [ENISA: Technical Advisory on AI-assisted software development、draft v0.4 (2026-09)](https://www.enisa.europa.eu/sites/default/files/2026-09/ENISA%20Technical%20Advisory-AI-assisted-software-development-draft.pdf) — 依存の追加、ロックファイルの変更、CI/CDの変更は、受け入れる前にレビューか承認を求める。**草案。**
- [Anthropic: 評価環境がインターネットに届いていた3件の調査 (2026-07)](https://www.anthropic.com/news/investigating-incidents-cybersecurity-evals) — 外に出られないはずの評価環境が、設定の誤りで外に届いていた。
- [claude.dev: How the Claude Code team thinks about verification (2026-11)](https://claude.dev/blog/how-the-claude-code-team-thinks-about-verification/) — 不安定なテストを、skip、sleep、再試行で済ませない。**運用の紹介で、効果の測定は無い。**
