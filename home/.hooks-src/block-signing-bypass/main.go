// block-signing-bypass は Claude Code の PreToolUse フック。
// Claude が git コミットの署名を回避するのを止める。
//
// ツール呼び出しの JSON を標準入力で受け取り、署名を無効化・差し替えする操作や、
// git commit を通らないコミット作成を拒否する。
// コマンド文字列の照合なので全ての回避方法は防げない。禁止フラグに言及しただけの
// コマンドも拒否する。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
)

const (
	signingKey    = `(?:commit\.gpgsign|tag\.gpgsign|tag\.forcesignannotated|rebase\.gpgsign|gpg\.[a-z0-9.]+|user\.signingkey)`
	gitConfigFile = `(?:\.gitconfig|\.git[/\\]config|\.config[/\\]git[/\\]config)`
)

var commandRules = []struct {
	pattern *regexp.Regexp
	label   string
}{
	{regexp.MustCompile(`(?i)--no-gpg-sign\b`), "--no-gpg-sign"},
	{regexp.MustCompile(`(?im)--no-sign(?:\s|$)`), "--no-sign"},
	{regexp.MustCompile(`(?im)(?:^|\s)(?:-c|--config-env)[=\s]+['"]?` + signingKey),
		"a signing setting overridden with -c or --config-env"},
	{regexp.MustCompile(`(?i)\bGIT_CONFIG\w*=`), "a GIT_CONFIG_* environment override"},
	{regexp.MustCompile(`(?i)\b(?:HOME|XDG_CONFIG_HOME)=\S*[^;&|\n]*\bgit\b`),
		"git run with a different config home"},
	{regexp.MustCompile(`(?i)\bgit\b[^;&|\n]*\b(?:commit-tree|fast-import)\b`),
		"a commit created without git commit"},
	{regexp.MustCompile(`(?i)(?:>|\btee\b|\bsed\s+-\S*i|\bperl\s+-\S*i|\bmv\b|\bcp\b|\brm\b)[^;&|\n]*` + gitConfigFile),
		"a direct write to a git config file"},
}

// git config の読み取りは許可し、値の設定や削除だけを止める。
var (
	commandSeparator = regexp.MustCompile(`[;\n|]|&&`)
	configCall       = regexp.MustCompile(`(?i)\bgit\b.*\bconfig\b`)
	hasSigningKey    = regexp.MustCompile(`(?i)` + signingKey)
	configRead       = regexp.MustCompile(`(?i)\s(?:--get\S*|--list|-l|get|list)(?:\s|$)`)
	configValue      = regexp.MustCompile(`(?i)` + signingKey + `['"]?\s+\S`)
	configRemove     = regexp.MustCompile(`(?i)\s(?:--unset\S*|unset|--remove-section|remove-section|--rename-section|rename-section|--replace-all|--add|set)\s`)
	configFilePath   = regexp.MustCompile(gitConfigFile + `$`)
)

func commandProblem(command string) string {
	for _, rule := range commandRules {
		if rule.pattern.MatchString(command) {
			return rule.label
		}
	}
	for _, part := range commandSeparator.Split(command, -1) {
		if !configCall.MatchString(part) || !hasSigningKey.MatchString(part) || configRead.MatchString(part) {
			continue
		}
		if configValue.MatchString(part) || configRemove.MatchString(part) {
			return "a signing setting changed with git config"
		}
	}
	return ""
}

func fileProblem(path string) string {
	if configFilePath.MatchString(path) {
		return "a direct edit of a git config file"
	}
	return ""
}

type toolCall struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command  string `json:"command"`
		FilePath string `json:"file_path"`
	} `json:"tool_input"`
}

func run(stdin io.Reader, stdout io.Writer) error {
	var call toolCall
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		return fmt.Errorf("read tool call: %w", err)
	}

	var problem string
	if call.ToolName == "Bash" {
		problem = commandProblem(call.ToolInput.Command)
	} else {
		problem = fileProblem(call.ToolInput.FilePath)
	}
	if problem == "" {
		return nil
	}

	return json.NewEncoder(stdout).Encode(map[string]any{
		"hookSpecificOutput": map[string]string{
			"hookEventName":      "PreToolUse",
			"permissionDecision": "deny",
			"permissionDecisionReason": "Blocked: " + problem + ". Commit signing must not be bypassed. " +
				"Report the signing error to the user and let them sign or decide.",
		},
	})
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "block-signing-bypass:", err)
		os.Exit(1)
	}
}
