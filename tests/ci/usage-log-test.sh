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
# 空行は飛ばした行に数えない
main.write_text("\n".join(json.dumps(l) for l in lines) + "\n{broken\n\n", encoding="utf-8")
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

equals "collect は応答ごとに1行を足し、<synthetic>を飛ばし、壊れた行を数える" "$(collect)" "3個のログを読み、8件の呼び出しを足した。形の違う1行を飛ばした"
equals "変わっていないログは読み直さない" "$(collect)" "0個のログを読み、0件の呼び出しを足した"

printf '%s\n' '{"type": "assistant", "timestamp": "2026-11-01T00:00:07Z", "sessionId": "sess1", "cwd": "C:/repo", "message": {"id": "m4", "model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": 1}}}' '{also broken' >>"$work/claude/C--repo/sess1.jsonl"
equals "伸びたログは読み直し、新しい応答だけを足し、飛ばした行を数え直す" "$(collect)" "1個のログを読み、1件の呼び出しを足した。形の違う2行を飛ばした"
equals "読み直したログも、変わらなければ次の回は読まない" "$(collect)" "0個のログを読み、0件の呼び出しを足した"

rm -rf "$work/claude" "$work/codex"
equals "元のログを消しても、記録から集計できる" "$(field --by source -- "rows['claude']['calls'], rows['codex']['calls']")" "(6, 2)"
equals "飛ばした行は、読み直したログの分を数え直して集計に出す" "$(usage report --since 2026-01-01 | grep '形が違う')" "これまでに読んだログで、形が違うので記録に入れなかった行: 2行"
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

# 既定の期間(直近7日): 6日前と8日前の呼び出しのうち、6日前だけを数える
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
                       for d in (6, 8)), encoding="utf-8")
EOF
uv run --quiet --script "$script" --db "$work/recent.sqlite3" collect --claude-dir "$work/recent" --codex-dir "$work/none" >/dev/null
equals "既定では直近7日を数える" "$(uv run --quiet --script "$script" --db "$work/recent.sqlite3" report --json | python3 -I -c 'import json, sys; print(sum(r["calls"] for r in json.load(sys.stdin)))' | tr -d '\r')" "1"

# 型の違う行や、中身の違う .meta.json があっても、その行だけを飛ばして続ける
db="$work/odd.sqlite3"
python3 -I - "$work/odd" <<'EOF'
import json, sys
from pathlib import Path
odd = Path(sys.argv[1])
def call(mid, skill=None, content=(), top=(), **usage):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": "o", "attributionSkill": skill, **dict(top),
                       "message": {"id": mid, "model": "claude-opus-5-5", "usage": {"input_tokens": 1, **usage}, "content": content}})
main = odd / "claude/p/o.jsonl"
sub = odd / "claude/p/o/subagents/agent-z.jsonl"
sub.parent.mkdir(parents=True)
# 辞書のトークン、辞書のスキル、数のcontent、Infinity、SQLiteに入らない大きな数、対になっていないサロゲート、
# idの無いサブエージェントの起動は飛ばし、文字列で書かれたトークンは数として読む。
# d2はサブエージェントも起こすが、1行として1回だけ数える
agent = {"type": "tool_use", "id": "t2", "name": "Agent"}
main.write_text("\n".join([call("bad", cache_creation="n/a"), call("a1"), call("d1", output_tokens={"x": 1}),
                           call("d2", skill={"x": 1}, content=[agent]), call("d3", output_tokens="5"), call("d4", content=5),
                           call("d5", output_tokens=float("inf")), call("d6", input_tokens=2**70),
                           call("d7", top={"cwd": "\ud800"}), call("d9", content=[{"type": "tool_use", "name": "Agent"}]),
                           # 集計に使う属性が数だと、reportで文字列と比べられないので飛ばす
                           call("d10", top={"cwd": 5}),
                           # 時刻の無い呼び出しはどの期間の集計にも入らないので、記録せずに数える。深い入れ子のJSONも飛ばす
                           call("d11", top={"timestamp": None}), "[" * 100000,
                           # JSONとして読めても、オブジェクトでない行
                           "null",
                           # 集計に使わない属性の形が変わっても、呼び出しは数える
                           call("d8", top={"effort": {"level": "high"}}),
                           # 使用量の無いassistantの行(サブエージェントを起こしたときのスキルも辞書)、messageが文字列の行、
                           # idの無い応答も、形の違う行として数える
                           json.dumps({"type": "assistant", "attributionSkill": {"x": 1},
                                       "message": {"content": [{"type": "tool_use", "id": "t", "name": "Agent"}]}}),
                           json.dumps({"type": "assistant", "message": "x"}),
                           json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z",
                                       "message": {"model": "claude-opus-5-5", "usage": {"input_tokens": 1}}}),
                           # 呼び出しは記録できるが、起こしたサブエージェントのidがSQLiteに入らない
                           call("d12", content=[{"type": "tool_use", "id": "\ud800", "name": "Agent"}])]) + "\n", encoding="utf-8")
# 読めないログ(名前が.jsonlのディレクトリ)は飛ばして、ほかのログを読む
(odd / "claude/p/dir.jsonl").mkdir()
sub.write_text(call("z1") + "\n", encoding="utf-8")
sub.with_suffix(".meta.json").write_text("null", encoding="utf-8")
# .meta.jsonの文字列でない値は使わず、呼び出しは数える。UTF-8として読めない.meta.jsonも同じ
(sub.parent / "agent-y.jsonl").write_text(call("y1") + "\n", encoding="utf-8")
(sub.parent / "agent-y.meta.json").write_text(json.dumps({"agentType": 5, "toolUseId": "t"}), encoding="utf-8")
(sub.parent / "agent-w.jsonl").write_text(call("w1") + "\n", encoding="utf-8")
(sub.parent / "agent-w.meta.json").write_bytes(b"\xff")
rollout = odd / "codex/sessions/r.jsonl"
rollout.parent.mkdir(parents=True)
usage = {"input_tokens": 1, "cached_input_tokens": 0, "output_tokens": 1}
text = {"input_tokens": "10", "cached_input_tokens": "4", "output_tokens": "1"}
rollout.write_text("\n".join(json.dumps(e) for e in [
    {"type": "session_meta", "payload": {"id": "r", "cwd": "C:/repo", "source": {"subagent": ["x"]}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:00Z", "payload": {"type": "token_count", "info": "x"}},
    # 枠の消費率だけを伝えるtoken_countは、使用量を持たないので数えない
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:00Z", "payload": {"type": "token_count", "info": None}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:01Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": usage, "last_token_usage": usage}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:02Z",
     "payload": {"type": "token_count", "info": {"total_token_usage": text, "last_token_usage": text}}},
    # 合計が無いと同じ呼び出しを見分けられないので、記録せずに数える。直前の呼び出しの分が無いものも数える
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:03Z", "payload": {"type": "token_count", "info": {"last_token_usage": usage}}},
    {"type": "event_msg", "timestamp": "2026-11-01T00:00:04Z", "payload": {"type": "token_count", "info": {"total_token_usage": usage}}},
]) + "\n", encoding="utf-8")
EOF
equals "型の違う行は飛ばして数え、ほかの行とログは読む" "$(collect "$work/odd" 2>/dev/null)" "5個のログを読み、9件の呼び出しを足した。形の違う19行を飛ばした"
equals "読めたログは読み直さない" "$(collect "$work/odd" 2>/dev/null)" "0個のログを読み、0件の呼び出しを足した"
equals "飛ばした行は、ログをまたいで足して集計に出す" "$(usage report --since 2026-01-01 | grep '形が違う')" "これまでに読んだログで、形が違うので記録に入れなかった行: 19行"
equals "文字列で書かれたトークンも数として集計する" "$(field --by source -- "rows['claude']['output'], rows['codex']['input'], rows['codex']['cache_read']")" "(5, 7, 4)"
equals ".meta.jsonの中身が無いか読めなくても、名前がagent-のログはサブエージェントとして分ける" "$(field --source claude --by agent-type -- "sorted(r['calls'] for r in rows.values())")" "[3, 4]"

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

# 再開では、サブエージェントのログが.meta.jsonを持たずに新しいセッションへ写され、forkのログは親の履歴を写して持つ。
# 写しを後の回に読んでも、元のログの種類、説明、スキルを残す。トークン数は、読み直した応答の最後の値にする
# 使い方: resume.py <ディレクトリ> <first|copy|first,copy> <元のセッションの名前>
db="$work/resume.sqlite3"
cat >"$work/resume.py" <<'EOF'
import json, sys
from pathlib import Path
base, phases, orig = Path(sys.argv[1]) / "claude/p", sys.argv[2].split(","), sys.argv[3]
def line(mid, output=1, skill=None, agent=False):
    return json.dumps({"type": "assistant", "timestamp": "2026-11-01T00:00:00Z", "sessionId": "A", "attributionSkill": skill,
                       "message": {"id": mid, "model": "claude-opus-5-5", "usage": {"input_tokens": 1, "output_tokens": output},
                                   "content": [{"type": "tool_use", "id": "toolu_5", "name": "Agent"}] if agent else []}}) + "\n"
def write(path, text, meta=None, mode="w"):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, mode, encoding="utf-8") as f:
        f.write(text)
    if meta:
        path.with_suffix(".meta.json").write_text(json.dumps(meta), encoding="utf-8")
if "first" in phases:
    # Mは書きかけで、出力が途中の値
    write(base / f"{orig}.jsonl", line("M", 1, "ship-task", agent=True))
    write(base / f"{orig}/subagents/agent-x.jsonl", line("X"), {"agentType": "general-purpose", "toolUseId": "toolu_5"})
if "copy" in phases:
    # 古い版のログでは、応答の最後の行も出力が途中の値(9)のことがあり、forkの写しが最後の値(12)を持つ
    write(base / f"{orig}.jsonl", line("M", 9, "ship-task", agent=True), mode="a")
    write(base / "B/subagents/agent-x.jsonl", line("X"))
    write(base / f"{orig}/subagents/agent-f.jsonl", line("M", 12, "ship-task", agent=True) + line("F"), {"agentType": "fork"})
EOF
python3 -I "$work/resume.py" "$work/resume" first A
collect "$work/resume" >/dev/null
python3 -I "$work/resume.py" "$work/resume" copy A
equals "写しのログからは、新しい応答だけを足す" "$(collect "$work/resume")" "3個のログを読み、1件の呼び出しを足した"
equals "写しを後から読んでも、元のログの種類を残す" "$(field --by agent-type -- "rows['general-purpose']['calls'], rows['fork']['calls'], len(rows)")" "(1, 1, 3)"
equals "写しを後から読んでも、親のスキルに数え、トークン数は大きい方にする" "$(field --by skill -- "rows['ship-task']['calls'], rows['ship-task']['output']")" "(2, 13)"

# 1回のcollectで、写しを元のログより先に読む(B/はZ/より先、Z/subagents/のforkはZ.jsonlより先に並ぶ)
db="$work/once.sqlite3"
python3 -I "$work/resume.py" "$work/once" first,copy Z
equals "写しと元のログを同じ回に読んでも、応答を1回だけ数える" "$(collect "$work/once")" "4個のログを読み、3件の呼び出しを足した"
equals "写しを先に読んでも、元のログの種類にする" "$(field --by agent-type -- "rows['general-purpose']['calls'], rows['fork']['calls'], len(rows)")" "(1, 1, 3)"
equals "写しを先に読んでも、親のスキルに数え、トークン数は大きい方にする" "$(field --by skill -- "rows['ship-task']['calls'], rows['ship-task']['output']")" "(2, 13)"

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
equals "--helpもUTF-8で出す" "$(usage --help | grep -c '使用量だけを抜き出して貯め')" "1"

# 大きい仕事の上限は、記録と同じディレクトリのweekly-capに、週の枠の%を1行で書く
db="$work/cap/usage.sqlite3"
equals "上限が無ければ、そう出す" "$(usage cap)" "上限なし"
equals "上限を決める" "$(usage cap 70)" "週の枠(全モデル)の上限を70%にした"
equals "上限はファイルに整数で書く" "$(cat "$work/cap/weekly-cap")" "70"
equals "今の上限を出す" "$(usage cap)" "70%"
for bad in 0 101 abc 7.5; do
  equals "範囲の外の上限($bad)は、終了コード2で断り、ファイルを変えない" "$(usage cap "$bad" 2>/dev/null; echo "rc=$?"; cat "$work/cap/weekly-cap")" "rc=2
70"
done
equals "上限を外す" "$(usage cap off)" "上限を外した"
equals "外すとファイルを消す" "$([ -e "$work/cap/weekly-cap" ] && echo exists || echo gone)" "gone"
equals "外した後に外しても、失敗しない" "$(usage cap off)" "上限を外した"
db="$work/usage.sqlite3"

if [ "$failures" -ne 0 ]; then
  printf '\n%d件の問題があります\n' "$failures"
  exit 1
fi
