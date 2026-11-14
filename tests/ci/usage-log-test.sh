#!/bin/bash
# usage-log (home/dot_local/bin/executable_usage-log) を、作ったClaude CodeとCodexのログで試す
# check に渡す文字列の中で変数を展開するので、SC2016 を抑える
# shellcheck disable=SC2016
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/home/dot_local/bin/executable_usage-log"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }
equals() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1"; printf '  want: %s\n  got:  %s\n' "$3" "$2"; fi; }
# Windows の Python はパイプに CRLF で書く
usage() { uv run --quiet --script "$script" --db "$work/usage.sqlite3" "$@" | tr -d '\r'; }
collect() { usage collect --claude-dir "$work/claude" --codex-dir "$work/codex"; }
# 使い方: field <report の引数...> -- <Python の式>  (JSON の行の一覧を rows として式を評価する)
# Windows では python の引数の日本語が化けるので、式には日本語を書かない
field() {
  local args=()
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  usage report --since 2026-01-01 --json "${args[@]}" | python3 -I -c "import json, sys; rows = {r['key']: r for r in json.load(sys.stdin)}; print(($2))" | tr -d '\r'
}

# 本体のログ: m1(review-loop、1行の応答が2行に分かれる)、m2(review-loopの中でサブエージェントを起こす)、
# m3(スキルなし、Fable、fast)、壊れた行、<synthetic>、ユーザーの行。サブエージェントのログ: s1(worktreeの中、m2が起こした)。
# old は期間の前。Codex: 同じ合計の token_count が2回続く(2回目は数えない)。
python3 -I - "$work" <<'EOF'
import json, sys
from pathlib import Path
work = Path(sys.argv[1])
main = work / "claude/C--repo/sess1.jsonl"
sub = work / "claude/C--repo/sess1/subagents/agent-x.jsonl"
sub.parent.mkdir(parents=True)

def call(mid, model, ts, usage, skill=None, cwd="C:/repo", content=(), speed="standard"):
    usage = {"speed": speed, **usage}
    return {"type": "assistant", "timestamp": ts, "sessionId": "sess1", "cwd": cwd, "gitBranch": "main",
            "effort": "high", "attributionSkill": skill,
            "message": {"id": mid, "model": model, "usage": usage, "content": list(content)}}

opus = {"input_tokens": 10, "output_tokens": 100, "cache_read_input_tokens": 1000,
        "cache_creation_input_tokens": 200, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 200}}
lines = [
    {"type": "user", "timestamp": "2026-11-01T00:00:00Z", "message": {"role": "user", "content": "hi"}},
    call("m1", "claude-opus-5-5", "2026-11-01T00:00:01Z", opus, "review-loop", content=[{"type": "thinking"}]),
    call("m1", "claude-opus-5-5", "2026-11-01T00:00:01Z", opus, "review-loop", content=[{"type": "text"}]),
    call("m2", "claude-opus-5-5", "2026-11-01T00:00:02Z", {"input_tokens": 1, "output_tokens": 1}, "review-loop",
         content=[{"type": "tool_use", "id": "toolu_1", "name": "Agent", "input": {}}]),
    call("m3", "claude-fable-5-2", "2026-11-01T00:00:03Z", {"input_tokens": 1000, "output_tokens": 1000}, speed="fast"),
    call("m5", "claude-haiku-5-5", "2026-11-01T00:00:05Z", {"input_tokens": 50000, "cache_read_input_tokens": 60000, "output_tokens": 0}),
    call("old", "claude-opus-5-5", "2025-12-31T23:59:59Z", {"input_tokens": 1, "output_tokens": 1}),
    call("syn", "<synthetic>", "2026-11-01T00:00:04Z", {"input_tokens": 9, "output_tokens": 9}),
]
main.parent.mkdir(parents=True, exist_ok=True)
main.write_text("\n".join(json.dumps(l) for l in lines) + "\n{broken\n", encoding="utf-8")
sub.write_text(json.dumps(call("s1", "claude-opus-5-5", "2026-11-01T00:00:06Z", {"input_tokens": 3, "output_tokens": 7},
                               cwd="C:/repo/.claude/worktrees/agent-x")) + "\n", encoding="utf-8")
sub.with_suffix(".meta.json").write_text(json.dumps({"agentType": "general-purpose", "description": "R1 correctness",
                                                     "toolUseId": "toolu_1"}), encoding="utf-8")

def tokens(i, c, o):
    return {"input_tokens": i, "cached_input_tokens": c, "output_tokens": o}
rollout = work / "codex/sessions/2026/11/01/rollout-c1.jsonl"
rollout.parent.mkdir(parents=True)
events = [
    {"type": "session_meta", "timestamp": "2026-11-01T00:00:00Z", "payload": {"id": "c1", "cwd": "C:/repo"}},
    {"type": "turn_context", "timestamp": "2026-11-01T00:00:00Z", "payload": {"model": "gpt-6-astra", "effort": "high"}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:10Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": tokens(100, 40, 5), "last_token_usage": tokens(100, 40, 5)}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:11Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": tokens(100, 40, 5), "last_token_usage": tokens(100, 40, 5)}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:12Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": tokens(300, 140, 8), "last_token_usage": tokens(200, 100, 3)}}},
]
rollout.write_text("\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8")
EOF

equals "collect は応答ごとに1行を足し、壊れた行と<synthetic>を飛ばす" "$(collect)" "3個のログを読み、8件の呼び出しを足した"
equals "変わっていないログは読み直さない" "$(collect)" "0個のログを読み、0件の呼び出しを足した"

printf '%s\n' '{"type": "assistant", "timestamp": "2026-11-01T00:00:07Z", "sessionId": "sess1", "cwd": "C:/repo", "message": {"id": "m4", "model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": 1}}}' >>"$work/claude/C--repo/sess1.jsonl"
equals "伸びたログは読み直し、新しい応答だけを足す" "$(collect)" "1個のログを読み、1件の呼び出しを足した"

rm -rf "$work/claude" "$work/codex"
equals "元のログを消しても、記録から集計できる" "$(field --by source -- "rows['claude']['calls'], rows['codex']['calls']")" "(6, 2)"
equals "期間の前の呼び出しは数えない" "$(field --since 2025-12-01 --by source -- "rows['claude']['calls']")" "7"

# 100万分の1ドルで、m1: 入力10×4 + 1時間の書き込み200×8 + 読み取り1000×0.2 + 出力100×20 = 3840、
# m2: 1×4 + 1×20 = 24、s1: 3×4 + 7×20 = 152
equals "サブエージェントは、親が起こしたときのスキルに数える" "$(field --by skill -- "rows['review-loop']['calls'], round(rows['review-loop']['cost_usd'] * 1e6)")" "(3, 4016)"
equals "fastは2倍、Haikuは10万トークンを超えると高い単価にする" "$(field --by model -- "round(rows['claude-fable-5-2']['cost_usd'] * 1e6), round(rows['claude-haiku-5-5']['cost_usd'] * 1e6)")" "(96000, 28000)"
equals "サブエージェントは、worktreeではなく親のセッションのプロジェクトに数える" "$(field --by project -- "sorted(rows)")" "['C:/repo']"
equals "サブエージェントは説明ごとに分けられる" "$(field --by agent -- "rows['R1 correctness']['calls'], sorted((k, r['calls']) for k, r in rows.items() if k != 'R1 correctness')[0][1], len(rows)")" "(1, 7, 2)"
equals "Codexは合計が変わったときだけ数え、キャッシュを入力から分ける" "$(field --source codex --by model -- "rows['gpt-6-astra']['input'], rows['gpt-6-astra']['cache_read'], rows['gpt-6-astra']['output']")" "(160, 140, 8)"
equals "単価の無いモデルは費用に入れず、件数を数える" "$(field --source codex --by model -- "rows['gpt-6-astra']['cost_usd'], rows['gpt-6-astra']['unpriced']")" "(0.0, 2)"
equals "割合は単価のある呼び出しの費用で割る" "$(field --by source -- "round(rows['claude']['share'], 6), rows['codex']['share']")" "(1.0, 0.0)"

if [ "$failures" -ne 0 ]; then
  printf '%d 件失敗\n' "$failures"
  exit 1
fi
