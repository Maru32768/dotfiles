// block-signing-bypass は Claude Code、Codex、Antigravity の PreToolUse フック。
// エージェントが git コミットの署名を回避するのを止める。
//
// ツール呼び出しの JSON を標準入力で受け取り、署名を無効化・差し替えする操作や、
// git commit を通らないコミット作成を拒否する。
// 入力 JSON の形から Claude Code / Codex (snake_case) と Antigravity (toolCall) を判別し、
// それぞれの形式に合わせて結果を標準出力へ返す。
// コマンド文字列の照合なので全ての回避方法は防げない。禁止フラグに言及しただけの
// コマンドも拒否する。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

const (
	signingKey    = `(?:commit\.gpgsign|tag\.gpgsign|tag\.forcesignannotated|rebase\.gpgsign|gpg\.[a-z0-9.]+|user\.signingkey|include\.path|includeif\..+?\.path)`
	gitConfigFile = `(?:\.gitconfig(?:\.local)?|\.git[/\\]config|\.config[/\\]git[/\\]config)`
)

var commandRules = []struct {
	pattern *regexp.Regexp
	label   string
}{
	{regexp.MustCompile(`(?i)--no-gpg-sign\b`), "--no-gpg-sign"},
	{regexp.MustCompile(`(?im)--no-sign(?:\s|$)`), "--no-sign"},
	{regexp.MustCompile(`(?im)(?:^|[\s'"])(?:-c|--config-env)[=\s]+['"]?` + signingKey),
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
	configFilePath   = regexp.MustCompile(`(?i)` + gitConfigFile + `$`)
	patchFileHeader  = regexp.MustCompile(`^\*\*\* (?:Update File|Add File|Delete File|Move to): (.+)$`)
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
	if configFilePath.MatchString(strings.TrimSpace(path)) {
		return "a direct edit of a git config file"
	}
	return ""
}

func patchProblem(patch string) string {
	for _, line := range strings.Split(patch, "\n") {
		line = strings.TrimRight(line, "\r")
		if m := patchFileHeader.FindStringSubmatch(line); m != nil {
			if problem := fileProblem(m[1]); problem != "" {
				return problem
			}
		}
	}
	return ""
}

type hookInput struct {
	// Claude Code / Codex 形式
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command  string          `json:"command"`
		FilePath string          `json:"file_path"`
		Input    string          `json:"input"`
		Patch    string          `json:"patch"`
		Cmd      json.RawMessage `json:"cmd"`
	} `json:"tool_input"`

	// Antigravity 形式 (camelCase)
	ToolCall *struct {
		Name string `json:"name"`
		Args struct {
			CommandLine string `json:"CommandLine"`
			Command     string `json:"command"`
			Path        string `json:"Path"`
			TargetFile  string `json:"TargetFile"`
			FilePath    string `json:"file_path"`
		} `json:"args"`
	} `json:"toolCall"`
}

func extractPatchTexts(input hookInput) []string {
	var texts []string
	if input.ToolInput.Input != "" {
		texts = append(texts, input.ToolInput.Input)
	}
	if input.ToolInput.Patch != "" {
		texts = append(texts, input.ToolInput.Patch)
	}
	if len(input.ToolInput.Cmd) > 0 {
		var s string
		if err := json.Unmarshal(input.ToolInput.Cmd, &s); err == nil && s != "" {
			texts = append(texts, s)
		} else {
			var arr []string
			if err := json.Unmarshal(input.ToolInput.Cmd, &arr); err == nil {
				texts = append(texts, arr...)
			}
		}
	}
	return texts
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func denyReason(problem string) string {
	return "Blocked: " + problem + ". Commit signing must not be bypassed. " +
		"Report the signing error to the user and let them sign or decide."
}

func run(stdin io.Reader, stdout io.Writer) error {
	var call hookInput
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		return fmt.Errorf("read tool call: %w", err)
	}

	if call.ToolCall != nil && call.ToolCall.Name != "" {
		var problem string
		if call.ToolCall.Name == "run_command" {
			problem = commandProblem(firstNonEmpty(call.ToolCall.Args.CommandLine, call.ToolCall.Args.Command))
		} else {
			problem = fileProblem(firstNonEmpty(call.ToolCall.Args.Path, call.ToolCall.Args.TargetFile, call.ToolCall.Args.FilePath))
		}
		if problem == "" {
			// Antigravity の PreToolUse は JSON オブジェクトを要求する。
			// "allow" を返すと確認プロンプトを飛ばすため、介入しないときは空オブジェクトを返す。
			_, err := io.WriteString(stdout, "{}\n")
			return err
		}
		return json.NewEncoder(stdout).Encode(map[string]string{
			"decision": "deny",
			"reason":   denyReason(problem),
		})
	}

	var problem string
	switch call.ToolName {
	case "Bash":
		problem = commandProblem(call.ToolInput.Command)
	case "apply_patch":
		for _, text := range extractPatchTexts(call) {
			if problem = patchProblem(text); problem != "" {
				break
			}
		}
	default:
		problem = fileProblem(call.ToolInput.FilePath)
	}
	if problem == "" {
		return nil
	}

	return json.NewEncoder(stdout).Encode(map[string]any{
		"hookSpecificOutput": map[string]string{
			"hookEventName":            "PreToolUse",
			"permissionDecision":       "deny",
			"permissionDecisionReason": denyReason(problem),
		},
	})
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "block-signing-bypass:", err)
		os.Exit(1)
	}
}
