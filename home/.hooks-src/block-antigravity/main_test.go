package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

var deniedCommands = []string{
	"agy",
	"agy -p 'fix the test'",
	"agy --help",
	"agy.exe -p hi",
	"agy.cmd -p hi",
	"/usr/local/bin/agy -p hi",
	"~/.local/bin/agy -p hi",
	`C:\Users\maru3\.local\bin\agy.exe -p hi`,
	"antigravity",
	"antigravity .",
	"antigravity-cli -p hello",
	"/Applications/Antigravity.app/Contents/MacOS/Antigravity",
	"open -a Antigravity .",
	`open -a "Antigravity.app" .`,
	"FOO=1 BAR=2 agy -p hi",
	"env agy -p hi",
	"env -i PATH=/usr/bin agy -p hi",
	`env -S "agy -p hi"`,
	"command agy -p hi",
	"exec agy -p hi",
	"nohup agy -p hi &",
	"timeout 60 agy -p hi",
	"sudo -u maru agy -p hi",
	"cd /tmp && agy -p hi",
	"ls || antigravity",
	"echo hello | agy -p",
	"echo hello | xargs agy -p",
	"result=$(agy -p hi)",
	`echo "$(antigravity-cli --version)"`,
	"result=`agy -p hi`",
	`bash -c 'agy -p hi'`,
	`sh -lc "cd /tmp && antigravity"`,
	`cmd.exe /c "agy.exe -p hi"`,
	`pwsh -Command "agy -p hi"`,
	`powershell -c "& C:\Users\maru3\bin\agy.exe"`,
	"start agy",
	"Start-Process antigravity",
	"mise exec -- agy -p hi",
	"op-run Personal -- agy -p hi",
	`python3 -c 'from google.antigravity import Agent'`,
	"python -m google.antigravity",
	"uv run --with google-antigravity script.py",
	"uvx google-antigravity",
	"if true; then agy -p hi; fi",
	"run() { agy -p hi; }; run",
	"while read -r line; do antigravity \"$line\"; done < list",
	`agy -p "unterminated`,
	"<<EOF agy -p hi",
	"xargs <<'EOF' agy",
	"< in time agy -p hi",
	"2>&1 nohup agy -p hi <<EOF",
	"cmd /c cmd /c cmd /c cmd /c cmd /c cmd /c cmd /c cmd /c cmd /c cmd /c agy",
	"env -u FOO -S 'agy -p hi'",
	"env --split-string='agy -p' hi",
	"mise x node -- agy -p hi",
	"echo `agy -p hi`\necho \"unterminated",
	"`agy -p hi`\necho \"x",
	"cat <<EOF\n`agy -p hi`\n",
	"cat <<EOF; echo x\n$(agy -p hi)\nEOF",
	"ag\\\ny -p hi",
	"2>&1 time agy -p hi",
	"2>/dev/null time bash &>/dev/null -c agy",
	"ag\\\ny -p hi\necho \"x",
	"bash -c \"\\\"agy\\\" -p hi\"\necho \"x",
	`pwsh -c "Write-Host hi; & 'C:\Program Files\agy.exe' -p hi"`,
	`pwsh -c "& C:\'Program Files'\agy.exe"`,
	"env agy -S x",
	"env agy --split-string=x",
	"env -S '-i' agy -p hi",
	"env -S '-u FOO' agy -p hi",
	"env --split-string=-i agy",
	`pwsh -c "& 'C:\Program Files\agy.exe' -p hi"`,
	`pwsh -c "& 'C:\Program Files (x86)\Antigravity\agy.exe'"`,
	`cmd /c "agy" -p "unterminated`,
	`bash -c "\"agy\" -p hi"`,
	"bash -c \"echo \\`agy\\`\"",
}

var allowedCommands = []string{
	"claude -p 'review this'",
	"codex review",
	"codex exec 'check this'",
	`git commit -m "Antigravityの設定を直す"`,
	`git commit -m "agyのフックを追加"`,
	"git log --grep=antigravity",
	"rg antigravity docs/",
	"grep -rn agy home/",
	"ls -la ~/.gemini/antigravity",
	"cat ~/.gemini/config/hooks.json",
	"cat ~/.gemini/config/skills.json",
	"ag pattern src/",
	`echo "strategy legacy pedagogy agy antigravity"`,
	"which agy",
	"command -v agy",
	"command -V antigravity",
	"mise ls",
	"python3 -c 'print(\"antigravity\")'",
	"git status",
	"cat <<'EOF'\nagy --help\nEOF",
	"cat <<EOF\nagy --help\nEOF",
	"cat <<-\"EOF\" # example\n\t$(agy --help)\n\tEOF",
	"cat <<'FIRST' <<'SECOND'\nagy --help\nFIRST\nantigravity --help\nSECOND",
	"cat <<E'OF'\nagy --help\nEOF",
	"cat <<''\nagy --help\n\n",
	"0<<'EOF' cat\nagy --help\nEOF",
	"printf '%s\\n' \"$(cat <<'EOF'\n)\nagy --help\nEOF\n)\"",
	"diff <(jq -S . a.json) <(jq -S . b.json) && echo same",
	"cat <",
	"cat >",
	"env -u",
	"echo hi # agy -p hi",
	`echo 'unterminated agy`,
	"cmd /c >",
	`foreach ($f in $files) { git commit -m "docs; agy usage" }`,
	`foreach ($f in Get-ChildItem) { Select-String -Path $f -Pattern "agy|antigravity" }`,
	"mise run test -- agy",
	`pwsh -c "Get-ChildItem | Where-Object { $_.Name -match 'agy' }"`,
}

func decide(t *testing.T, toolName, command string) bool {
	t.Helper()
	input, err := json.Marshal(map[string]any{
		"tool_name":  toolName,
		"tool_input": map[string]string{"command": command},
	})
	if err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer
	if err := run(bytes.NewReader(input), &stdout); err != nil {
		t.Fatal(err)
	}
	if stdout.Len() == 0 {
		return false
	}
	var output struct {
		HookSpecificOutput struct {
			HookEventName            string `json:"hookEventName"`
			PermissionDecision       string `json:"permissionDecision"`
			PermissionDecisionReason string `json:"permissionDecisionReason"`
		} `json:"hookSpecificOutput"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &output); err != nil {
		t.Fatalf("invalid output %q: %v", stdout.String(), err)
	}
	if output.HookSpecificOutput.HookEventName != "PreToolUse" ||
		output.HookSpecificOutput.PermissionDecision != "deny" ||
		output.HookSpecificOutput.PermissionDecisionReason == "" {
		t.Fatalf("unexpected output %q", stdout.String())
	}
	return true
}

func TestDeniedCommands(t *testing.T) {
	for _, command := range deniedCommands {
		if !decide(t, "Bash", command) {
			t.Errorf("should deny: %s", command)
		}
	}
}

func TestAllowedCommands(t *testing.T) {
	for _, command := range allowedCommands {
		if decide(t, "Bash", command) {
			t.Errorf("should allow: %s", command)
		}
	}
}

func TestNonBashToolsAreIgnored(t *testing.T) {
	if decide(t, "Edit", "agy -p hi") {
		t.Error("non-Bash tool should be allowed")
	}
}

func TestInvalidInputIsAnError(t *testing.T) {
	var stdout bytes.Buffer
	if err := run(strings.NewReader("not json"), &stdout); err == nil {
		t.Error("expected an error")
	}
	if stdout.Len() != 0 {
		t.Errorf("unexpected output %q", stdout.String())
	}
}
