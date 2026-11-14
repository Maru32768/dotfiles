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
db="$work/usage.sqlite3"
usage() { uv run --quiet --script "$script" --db "$db" "$@" | tr -d '\r'; }
# 使い方: collect [<ログを置いたディレクトリ>]  (その下の claude と codex を読む)
collect() { usage collect --claude-dir "${1:-$work}/claude" --codex-dir "${1:-$work}/codex"; }
# 使い方: field <report の引数...> -- <Python の式>  (JSON の行の一覧を rows として式を評価する)
# Windows では python の引数の日本語が化けるので、式には日本語を書かない
field() {
  local args=()
  while [ "$1" != -- ]; do args+=("$1"); shift; done
  usage report --since 2026-01-01 --json "${args[@]}" | python3 -I -c "import json, sys; rows = {r['key']: r for r in json.load(sys.stdin)}; print(($2))" | tr -d '\r'
}

# 本体のログ: m1(review-loop、1行の応答が2行に分かれ、最初の行の出力は途中の値)、m2(review-loopの中でサブエージェントを起こす)、
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
        "cache_creation_input_tokens": 300, "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 200}}
lines = [
    {"type": "user", "timestamp": "2026-11-01T00:00:00Z", "message": {"role": "user", "content": "hi"}},
    call("m1", "claude-opus-5-5", "2026-11-01T00:00:01Z", {**opus, "output_tokens": 1}, "review-loop", content=[{"type": "thinking"}]),
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

# 100万分の1ドルで、m1: 入力10×4 + 5分の書き込み100×5 + 1時間の書き込み200×8 + 読み取り1000×0.2 + 出力100×20 = 4340、
# m2: 1×4 + 1×20 = 24、s1: 3×4 + 7×20 = 152
equals "サブエージェントは、親が起こしたときのスキルに数える" "$(field --by skill -- "rows['review-loop']['calls'], round(rows['review-loop']['cost_usd'] * 1e6)")" "(3, 4516)"
equals "fastは2倍、Haikuは10万トークンを超えると高い単価にする" "$(field --by model -- "round(rows['claude-fable-5-2']['cost_usd'] * 1e6), round(rows['claude-haiku-5-5']['cost_usd'] * 1e6)")" "(96000, 28000)"
equals "サブエージェントは、worktreeではなく親のセッションのプロジェクトに数える" "$(field --by project -- "sorted(rows)")" "['C:/repo']"
equals "サブエージェントは説明ごとに分けられる" "$(field --by agent -- "rows['R1 correctness']['calls'], sorted((k, r['calls']) for k, r in rows.items() if k != 'R1 correctness')[0][1], len(rows)")" "(1, 7, 2)"
equals "Codexは合計が変わったときだけ数え、キャッシュを入力から分ける" "$(field --source codex --by model -- "rows['gpt-6-astra']['input'], rows['gpt-6-astra']['cache_read'], rows['gpt-6-astra']['output']")" "(160, 140, 8)"
equals "単価の無いモデルは費用に入れず、件数を数える" "$(field --source codex --by model -- "rows['gpt-6-astra']['cost_usd'], rows['gpt-6-astra']['unpriced']")" "(0.0, 2)"
# 単価のある費用の合計は、m1 4340 + m2 24 + m3 96000 + m5 28000 + s1 152 + m4 24 = 128540
equals "割合は単価のある呼び出しの費用の合計で割る" "$(field --by skill -- "round(rows['review-loop']['share'], 6)")" "$(python3 -I -c 'print(round(4516 / 128540, 6))' | tr -d '\r')"
equals "単価の無い呼び出しは割合に入れない" "$(field --by source -- "round(rows['claude']['share'], 6), rows['codex']['share']")" "(1.0, 0.0)"

# 既定の期間(直近7日): 1日前と10日前の呼び出しのうち、1日前だけを数える
python3 -I - "$work" <<'EOF'
import json, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
log = Path(sys.argv[1]) / "recent/C--repo/s.jsonl"
log.parent.mkdir(parents=True)
now = datetime.now(timezone.utc)
log.write_text("".join(json.dumps({"type": "assistant", "timestamp": (now - timedelta(days=d)).strftime("%Y-%m-%dT%H:%M:%S.000Z"),
                                   "sessionId": "s", "message": {"id": f"d{d}", "model": "claude-opus-5-5",
                                                                 "usage": {"input_tokens": 1, "output_tokens": 1}}}) + "\n"
                       for d in (1, 10)), encoding="utf-8")
EOF
uv run --quiet --script "$script" --db "$work/recent.sqlite3" collect --claude-dir "$work/recent" --codex-dir "$work/none" >/dev/null
equals "既定では直近7日を数える" "$(uv run --quiet --script "$script" --db "$work/recent.sqlite3" report --json | python3 -I -c 'import json, sys; print(sum(r["calls"] for r in json.load(sys.stdin)))' | tr -d '\r')" "1"

# 型の違う行や、中身の違う .meta.json があっても、その行だけを飛ばして続ける
db="$work/odd.sqlite3"
python3 -I - "$work/odd" <<'EOF'
import json, sys
from pathlib import Path
odd = Path(sys.argv[1])
def call(mid, skill=None, **usage):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": "o", "attributionSkill": skill,
                       "message": {"id": mid, "model": "claude-opus-5-5", "usage": {"input_tokens": 1, **usage}}})
main = odd / "claude/p/o.jsonl"
sub = odd / "claude/p/o/subagents/agent-z.jsonl"
sub.parent.mkdir(parents=True)
# 辞書のトークンと辞書のスキルは飛ばし、文字列で書かれたトークンは数として読む
main.write_text("\n".join([call("bad", cache_creation="n/a"), call("a1"), call("d1", output_tokens={"x": 1}),
                           call("d2", skill={"x": 1}), call("d3", output_tokens="5")]) + "\n", encoding="utf-8")
sub.write_text(call("z1") + "\n", encoding="utf-8")
sub.with_suffix(".meta.json").write_text("null", encoding="utf-8")
rollout = odd / "codex/sessions/r.jsonl"
rollout.parent.mkdir(parents=True)
usage = {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1}
rollout.write_text("\n".join(json.dumps(e) for e in [
    {"type": "session_meta", "payload": {"id": "r", "cwd": "C:/repo", "source": {"subagent": ["x"]}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:00Z", "payload": {"type": "token_count", "info": "x"}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:01Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": usage, "last_token_usage": usage}}},
]) + "\n", encoding="utf-8")
EOF
equals "型の違う行は飛ばし、ほかの行とログは読む" "$(collect "$work/odd")" "3個のログを読み、4件の呼び出しを足した"
equals "読めたログは読み直さない" "$(collect "$work/odd")" "0個のログを読み、0件の呼び出しを足した"
equals "文字列で書かれたトークンも数として集計する" "$(field --by source -- "rows['claude']['output']")" "5"

# Codexのサブエージェントの記録は、自分のsession_metaの次に親のものを持つ。親と同じ行番号の呼び出しも別に数える
db="$work/fork.sqlite3"
python3 -I - "$work/fork" <<'EOF'
import json, sys
from pathlib import Path
base = Path(sys.argv[1]) / "codex/sessions"
base.mkdir(parents=True)
usage = {"input_tokens": 10, "cached_input_tokens": 0, "output_tokens": 1}
count = {"type": "event_msg", "timestamp": "2026-11-01T00:00:00Z",
         "payload": {"type": "token_count", "info": {"total_token_usage": usage, "last_token_usage": usage}}}
parent = {"type": "session_meta", "payload": {"id": "P", "cwd": "C:/repo", "source": "exec"}}
child = {"type": "session_meta", "payload": {"id": "C", "cwd": "C:/repo", "source": {"subagent": "review"}}}
(base / "rollout-P.jsonl").write_text("\n".join(json.dumps(e) for e in [parent, {"type": "turn_context", "payload": {}}, count]) + "\n", encoding="utf-8")
(base / "rollout-C.jsonl").write_text("\n".join(json.dumps(e) for e in [child, parent, count]) + "\n", encoding="utf-8")
spawned = {"type": "session_meta", "payload": {"id": "T", "cwd": "C:/repo", "source": {"subagent": {"thread_spawn": {"parent_thread_id": "P"}}}}}
(base / "rollout-T.jsonl").write_text("\n".join(json.dumps(e) for e in [spawned, parent, count]) + "\n", encoding="utf-8")
# 最初のsession_metaにidが無くても、2つ目の親のものは使わない
nameless = {"type": "session_meta", "payload": {"cwd": "C:/repo", "source": {"subagent": "review"}}}
(base / "rollout-N.jsonl").write_text("\n".join(json.dumps(e) for e in [nameless, parent, count]) + "\n", encoding="utf-8")
EOF
equals "Codexのサブエージェントの呼び出しを、親の呼び出しと別に数える" "$(collect "$work/fork")" "4個のログを読み、4件の呼び出しを足した"
equals "Codexのサブエージェントは、その種類で分けられる" "$(field --by agent-type -- "rows.get('review', {}).get('calls'), rows.get('thread_spawn', {}).get('calls'), len(rows)")" "(2, 1, 3)"

# SSHのリモートのセッションでは、サブエージェントのログが subagents/ の外にあり、.meta.json は toolUseId だけを持つ
db="$work/ssh.sqlite3"
python3 -I - "$work/ssh" <<'EOF'
import json, sys
from pathlib import Path
base = Path(sys.argv[1]) / "claude/ssh-host"
base.mkdir(parents=True)
def call(mid, cwd, **extra):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": "s", "cwd": cwd, **extra,
                       "message": {"id": mid, "model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": 1},
                                   "content": [{"type": "tool_use", "id": "toolu_9", "name": "Agent"}] if mid == "M" else []}})
(base / "s.jsonl").write_text(call("M", "C:/repo", attributionSkill="ship-task") + "\n", encoding="utf-8")
(base / "agent-q.jsonl").write_text(call("Q", "A:/wt") + "\n", encoding="utf-8")
(base / "agent-q.meta.json").write_text(json.dumps({"toolUseId": "toolu_9"}), encoding="utf-8")
EOF
collect "$work/ssh" >/dev/null
equals "subagents/ の外のサブエージェントも、本体と分ける" "$(field --by agent -- "len(rows), sorted(r['calls'] for r in rows.values())")" "(2, [1, 1])"
equals "subagents/ の外のサブエージェントも、親のセッションのプロジェクトに数える" "$(field --by project -- "sorted(rows)")" "['C:/repo']"

# 再開やforkで、同じ応答が別のセッションのログにも写される
db="$work/copy.sqlite3"
python3 -I - "$work/copy" <<'EOF'
import json, sys
from pathlib import Path
base = Path(sys.argv[1]) / "claude/p"
base.mkdir(parents=True)
for session in ("a", "b"):
    (base / f"{session}.jsonl").write_text(json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": session,
        "message": {"id": "same", "model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": 1}}}) + "\n", encoding="utf-8")
EOF
equals "同じ応答が2つのログにあっても1回だけ数える" "$(collect "$work/copy")" "2個のログを読み、1件の呼び出しを足した"

# サブエージェントは自分のスキルを先に使い、無ければ親のスキルを使う。スキルの無い呼び出しはモデルによらず1つにまとめる
db="$work/skills.sqlite3"
python3 -I - "$work/skills" <<'EOF'
import json, sys
from pathlib import Path
base = Path(sys.argv[1]) / "claude/p"
(base / "s/subagents").mkdir(parents=True)
def call(mid, model="claude-opus-5-5", skill=None, agent=False):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": "s", "attributionSkill": skill,
                       "message": {"id": mid, "model": model, "usage": {"input_tokens": 1, "output_tokens": 1},
                                   "content": [{"type": "tool_use", "id": "toolu_7", "name": "Agent"}] if agent else []}})
(base / "s.jsonl").write_text("\n".join([call("M", skill="ship-task", agent=True), call("N"), call("O", "claude-fable-5-2")]) + "\n", encoding="utf-8")
for name, skill in (("agent-a", "simplify"), ("agent-b", None)):
    (base / f"s/subagents/{name}.jsonl").write_text(call(name, skill=skill) + "\n", encoding="utf-8")
    (base / f"s/subagents/{name}.meta.json").write_text(json.dumps({"agentType": "general-purpose", "toolUseId": "toolu_7"}), encoding="utf-8")
EOF
collect "$work/skills" >/dev/null
equals "サブエージェントのスキルは自分のものを先に使い、無ければ親のものを使う" "$(field --by skill -- "rows['simplify']['calls'], rows['ship-task']['calls']")" "(1, 2)"
equals "スキルの無い呼び出しは、モデルによらず1つにまとめる" "$(field --by skill -- "len(rows), sum(r['calls'] for k, r in rows.items() if k not in ('simplify', 'ship-task'))")" "(3, 2)"

db="$work/usage.sqlite3"

if [ "$failures" -ne 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
