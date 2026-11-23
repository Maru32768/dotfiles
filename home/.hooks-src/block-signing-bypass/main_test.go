package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

var deniedCommands = []string{
	"git commit --no-gpg-sign -m x",
	"git -C /tmp/r commit -m x --no-gpg-sign",
	"git rebase --no-gpg-sign main",
	"git tag --no-sign v1",
	"git -c commit.gpgsign=false commit -m x",
	"git -c commit.gpgSign=false commit -m x",
	"git -c 'commit.gpgsign=false' commit -m x",
	"git -c gpg.program=gpg commit -m x",
	"git -C /tmp/r -c gpg.program=/bin/true commit -m x",
	"git -c gpg.format=ssh commit -m x",
	"git -c user.signingkey=ABC commit -m x",
	"git config --global alias.ci '-c commit.gpgsign=false commit'",
	`git config alias.ci "-c commit.gpgsign=false commit"`,
	"git config --global includeIf.gitdir:/.path /tmp/x",
	"git config --global include.path /tmp/x",
	"git -c include.path=/tmp/x commit -m x",
	"git -c includeif.onbranch:main.path=/tmp/x commit -m x",
	`git -c "includeIf.onbranch:[ m]ain.path=/tmp/x" commit -m x`,
	"git config --local includeIf.gitdir:~/src/.dotfiles/.path /tmp/x",
	"git --config-env=commit.gpgsign=X commit -m x",
	"git config commit.gpgsign false",
	"git config --global commit.gpgsign false",
	"git config --global gpg.program gpg",
	"git config --global --unset commit.gpgsign",
	"git config --unset-all user.signingkey",
	"git config set commit.gpgsign false",
	"git config unset commit.gpgsign",
	"cd /tmp/r && git config --local commit.gpgsign false && git commit -m x",
	"GIT_CONFIG_GLOBAL=/dev/null git commit -m x",
	"GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign git commit -m x",
	"export GIT_CONFIG_NOSYSTEM=1",
	"HOME=/tmp git commit -m x",
	"XDG_CONFIG_HOME=/tmp git commit -m x",
	"git commit-tree HEAD^{tree} -m x",
	"git -C /tmp/r commit-tree abc -m x",
	"git fast-import < data",
	"echo '[commit] gpgsign = false' >> ~/.gitconfig",
	"sed -i '/gpgsign/d' ~/.gitconfig",
	"sed -i 's/true/false/' .git/config",
	"tee -a .git/config < x",
	"mv ~/.gitconfig ~/.gitconfig.bak",
	"rm ~/.gitconfig",
	"echo '[commit] gpgsign = false' >> ~/.gitconfig.local",
	"echo '[commit] gpgsign = false' >> ~/.GitConfig.local",
}

var allowedCommands = []string{
	"git config --get include.path",
	"git config --get includeIf.gitdir:~/work/.path",
	"ls",
	"git status",
	"git add -A && git commit -m 'normal commit'",
	"git commit -S -m x",
	"git -C /tmp/r commit -F - <<'EOF'\nmessage\nEOF",
	"git log -1 --show-signature",
	"git log --format='%h %G? %GK'",
	"git config --get commit.gpgsign",
	"git config commit.gpgsign",
	"git config get commit.gpgsign",
	"git config --global --get user.signingkey",
	"git config --list",
	`git config --show-origin --get-regexp '^(commit\.gpgsign|gpg\.|user\.signingkey)'`,
	"git config user.name",
	"git config --global core.editor vim",
	"cat ~/.gitconfig",
	"grep -n gpgsign ~/.gitconfig",
	"gpg --list-secret-keys --keyid-format=long",
	"echo test | gpg -u ABC --clearsign > /dev/null",
	"git -c core.pager=cat log -1",
	"PATH=/x:$PATH git status",
	"cp a.txt b.txt && rm c.txt",
	"git worktree add --detach /tmp/x REL_18_6",
}

var deniedFiles = []string{
	"/home/maru/.gitconfig",
	"/home/maru/.gitconfig.local",
	"/home/maru/work/r/.git/config",
	"/home/maru/.config/git/config",
	`C:\Users\maru3\.gitconfig`,
	`C:\Users\maru3\.gitconfig.local`,
	`C:\Users\maru3\work\r\.git\config`,
	`C:\Users\maru3\.config\git\config`,
	"/Users/maru/.GitConfig.local",
	"/Users/maru/work/r/.GIT/config",
	`C:\Users\maru3\.GITCONFIG`,
}

var allowedFiles = []string{
	"/home/maru/work/r/README.md",
	"/home/maru/work/r/.gitignore",
	"/home/maru/work/r/.git-config-notes.md",
	`C:\Users\maru3\work\r\README.md`,
	"/home/maru/.gitconfig.local.example",
	"/home/maru/.gitconfig.bak",
}

func decidePayload(t *testing.T, payload any) bool {
	t.Helper()
	input, err := json.Marshal(payload)
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

func decide(t *testing.T, toolName, field, value string) bool {
	t.Helper()
	return decidePayload(t, map[string]any{
		"tool_name":  toolName,
		"tool_input": map[string]string{field: value},
	})
}

func decideAntigravity(t *testing.T, toolName, field, value string) bool {
	t.Helper()
	input, err := json.Marshal(map[string]any{
		"hookEventName": "PreToolUse",
		"toolCall": map[string]any{
			"id":   "toolu_01",
			"name": toolName,
			"args": map[string]string{field: value},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer
	if err := run(bytes.NewReader(input), &stdout); err != nil {
		t.Fatal(err)
	}
	var output map[string]string
	if err := json.Unmarshal(stdout.Bytes(), &output); err != nil {
		t.Fatalf("invalid Antigravity output %q: %v", stdout.String(), err)
	}
	if output["decision"] == "ask" && output["reason"] == "" {
		return false
	}
	if output["decision"] != "deny" || output["reason"] == "" {
		t.Fatalf("unexpected Antigravity output %q", stdout.String())
	}
	return true
}

func TestCommands(t *testing.T) {
	for _, command := range deniedCommands {
		if !decide(t, "Bash", "command", command) {
			t.Errorf("should deny: %s", command)
		}
	}
	for _, command := range allowedCommands {
		if decide(t, "Bash", "command", command) {
			t.Errorf("should allow: %s", command)
		}
	}
}

func TestFiles(t *testing.T) {
	for _, tool := range []string{"Edit", "Write"} {
		for _, path := range deniedFiles {
			if !decide(t, tool, "file_path", path) {
				t.Errorf("%s should deny: %s", tool, path)
			}
		}
		for _, path := range allowedFiles {
			if decide(t, tool, "file_path", path) {
				t.Errorf("%s should allow: %s", tool, path)
			}
		}
	}
}

func TestCodexApplyPatch(t *testing.T) {
	headers := []string{"Update File", "Add File", "Delete File", "Move to"}
	for _, header := range headers {
		for _, path := range deniedFiles {
			patch := "*** Begin Patch\n*** " + header + ": " + path + "\n*** End Patch\n"
			if !decidePayload(t, map[string]any{
				"tool_name":  "apply_patch",
				"tool_input": map[string]any{"cmd": []string{"apply_patch", patch}},
			}) {
				t.Errorf("apply_patch cmd should deny (%s): %s", header, path)
			}
			if !decidePayload(t, map[string]any{
				"tool_name":  "apply_patch",
				"tool_input": map[string]any{"command": patch},
			}) {
				t.Errorf("apply_patch command should deny (%s): %s", header, path)
			}
		}
	}
	for _, path := range allowedFiles {
		patch := "*** Begin Patch\n*** Update File: " + path + "\n@@\n-a\n+b\n*** End Patch\n"
		if decidePayload(t, map[string]any{
			"tool_name":  "apply_patch",
			"tool_input": map[string]any{"cmd": []string{"apply_patch", patch}},
		}) {
			t.Errorf("apply_patch should allow: %s", path)
		}
	}
}

func TestAntigravityCommands(t *testing.T) {
	for _, command := range deniedCommands {
		if !decideAntigravity(t, "run_command", "CommandLine", command) {
			t.Errorf("Antigravity should deny: %s", command)
		}
	}
	for _, command := range allowedCommands {
		if decideAntigravity(t, "run_command", "CommandLine", command) {
			t.Errorf("Antigravity should allow: %s", command)
		}
	}
}

func TestAntigravityFiles(t *testing.T) {
	cases := []struct {
		tool  string
		field string
	}{
		{"edit_file", "Path"},
		{"write_file", "Path"},
		{"replace_file_content", "TargetFile"},
		{"multi_replace_file_content", "TargetFile"},
		{"write_to_file", "TargetFile"},
	}
	for _, tc := range cases {
		for _, path := range deniedFiles {
			if !decideAntigravity(t, tc.tool, tc.field, path) {
				t.Errorf("Antigravity %s should deny: %s", tc.tool, path)
			}
		}
		for _, path := range allowedFiles {
			if decideAntigravity(t, tc.tool, tc.field, path) {
				t.Errorf("Antigravity %s should allow: %s", tc.tool, path)
			}
		}
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
