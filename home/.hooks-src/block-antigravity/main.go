// block-antigravity は Claude Code と Codex の PreToolUse フック。
// Claude Code や Codex が Bash 経由で Antigravity (agy / antigravity / SDK) を
// 呼び出すのを止める。Antigravity には登録しない。
//
// ツール呼び出しの JSON を標準入力で受け取り、コマンド位置で Antigravity を
// 起動する操作を拒否する。git commit メッセージや grep 等の引数に
// "antigravity" や "agy" が含まれるだけのコマンドは通す。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

const maxRecursionDepth = 8

var (
	envAssignPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)
	pythonNameRegex  = regexp.MustCompile(`^(?:python(?:\d+(?:\.\d+)*)?|py|uv|uvx|pipx)$`)
	sdkRefPattern    = regexp.MustCompile(`(?i)\bgoogle[._-]antigravity\b`)
	dblQuoteEscape   = strings.NewReplacer(`\"`, `"`, `\\`, `\`, `\$`, `$`, "\\`", "`", "\\\n", "")
)

func normalizeCmdName(raw string) string {
	s := strings.TrimSpace(raw)
	if idx := strings.LastIndexAny(s, `/\`); idx >= 0 {
		s = s[idx+1:]
	}
	s = strings.ToLower(s)
	for _, ext := range []string{".exe", ".cmd", ".bat", ".ps1", ".sh"} {
		s = strings.TrimSuffix(s, ext)
	}
	return s
}

func isAntigravityTarget(raw string) bool {
	lower := strings.ToLower(strings.TrimSpace(raw))
	if strings.Contains(lower, "antigravity.app") {
		return true
	}
	base := normalizeCmdName(raw)
	return base == "agy" || base == "antigravity" || base == "antigravity-cli"
}

func stripEnvAssigns(args []string) []string {
	i := 0
	for i < len(args) && envAssignPattern.MatchString(args[i]) {
		i++
	}
	return args[i:]
}

func checkSimpleCommand(args []string, depth int) string {
	if depth > maxRecursionDepth {
		return ""
	}
	for {
		args = stripEnvAssigns(args)
		if len(args) == 0 {
			return ""
		}
		raw := args[0]
		base := normalizeCmdName(raw)
		rest := args[1:]

		if isAntigravityTarget(raw) {
			return "invoking Antigravity (" + raw + ")"
		}

		switch base {
		case "nohup", "time", "setsid":
			args = skipSimpleFlags(rest, nil)
			continue
		case "command":
			i := 0
			for i < len(rest) && strings.HasPrefix(rest[i], "-") {
				f := rest[i]
				if f == "--" {
					i++
					break
				}
				// `command -v agy` / `command -V agy` は存在確認のみで起動しない
				if strings.ContainsAny(f[1:], "vV") {
					return ""
				}
				i++
			}
			args = rest[i:]
			continue
		case "exec":
			args = skipSimpleFlags(rest, map[string]bool{"-a": true})
			continue
		case "env":
			i := 0
			for i < len(rest) {
				f := rest[i]
				if f == "--" {
					i++
					break
				}
				if f == "-S" || f == "--split-string" {
					if i+1 < len(rest) {
						if prob := commandProblemDepth(rest[i+1], depth+1); prob != "" {
							return prob
						}
						i += 2
						continue
					}
					break
				}
				if strings.HasPrefix(f, "--split-string=") {
					if prob := commandProblemDepth(strings.TrimPrefix(f, "--split-string="), depth+1); prob != "" {
						return prob
					}
					i++
					continue
				}
				if f == "-u" || f == "--unset" || f == "-C" || f == "--chdir" {
					i += 2
					continue
				}
				if strings.HasPrefix(f, "-") || envAssignPattern.MatchString(f) {
					i++
					continue
				}
				break
			}
			args = rest[min(i, len(rest)):]
			continue
		case "sudo":
			args = skipSimpleFlags(rest, map[string]bool{
				"-u": true, "-g": true, "-C": true, "-D": true, "-h": true, "-p": true, "-r": true, "-t": true, "-T": true, "-U": true,
			})
			continue
		case "nice":
			args = skipSimpleFlags(rest, map[string]bool{"-n": true})
			continue
		case "stdbuf":
			args = skipSimpleFlags(rest, map[string]bool{"-i": true, "-o": true, "-e": true})
			continue
		case "timeout":
			rem := skipSimpleFlags(rest, map[string]bool{"-k": true, "--kill-after": true, "-s": true, "--signal": true})
			if len(rem) > 1 {
				// 最初の位置引数は duration
				args = rem[1:]
				continue
			}
			return ""
		case "xargs":
			args = skipSimpleFlags(rest, map[string]bool{
				"-a": true, "-d": true, "-E": true, "-I": true, "-L": true, "-l": true, "-n": true, "-P": true, "-s": true,
			})
			continue
		case "mise":
			if len(rest) > 0 && (rest[0] == "exec" || rest[0] == "x") {
				for i := 1; i < len(rest); i++ {
					if rest[i] == "--" {
						args = rest[i+1:]
						goto nextIter
					}
				}
			}
			return ""
		case "op-run":
			// `op-run <vault> -- <cmd...>` または `op-run <vault> <cmd...>`
			for i := 0; i < len(rest); i++ {
				if rest[i] == "--" {
					args = rest[i+1:]
					goto nextIter
				}
			}
			rem := skipSimpleFlags(rest, nil)
			if len(rem) > 1 {
				args = rem[1:]
				continue
			}
			return ""
		case "sh", "bash", "zsh", "dash", "fish", "ksh":
			for i := 0; i < len(rest); i++ {
				f := rest[i]
				if f == "--" {
					break
				}
				if f == "-c" || (strings.HasPrefix(f, "-") && !strings.HasPrefix(f, "--") && strings.Contains(f[1:], "c")) {
					if i+1 < len(rest) {
						return commandProblemDepth(rest[i+1], depth+1)
					}
				}
			}
			return ""
		case "cmd":
			for i := 0; i < len(rest); i++ {
				fl := strings.ToLower(rest[i])
				if fl == "/c" || fl == "/k" {
					if i+1 < len(rest) {
						return commandProblemDepth(strings.Join(rest[i+1:], " "), depth+1)
					}
				}
			}
			return ""
		case "pwsh", "powershell":
			for i := 0; i < len(rest); i++ {
				fl := strings.ToLower(rest[i])
				if fl == "-c" || fl == "-command" {
					if i+1 < len(rest) {
						return commandProblemDepth(strings.Join(rest[i+1:], " "), depth+1)
					}
				}
			}
			return ""
		case "open":
			for i := 0; i < len(rest); i++ {
				if rest[i] == "-a" && i+1 < len(rest) {
					if isAntigravityTarget(rest[i+1]) {
						return "launching Antigravity with open -a"
					}
					i++
					continue
				}
				if strings.Contains(strings.ToLower(rest[i]), "antigravity.app") {
					return "launching Antigravity.app"
				}
			}
			return ""
		case "start", "start-process":
			for _, arg := range rest {
				if arg == "" || strings.HasPrefix(arg, "-") || strings.HasPrefix(arg, "/") {
					continue
				}
				if isAntigravityTarget(arg) {
					return "launching Antigravity (" + arg + ")"
				}
			}
			return ""
		default:
			if pythonNameRegex.MatchString(base) {
				joined := strings.Join(rest, " ")
				if sdkRefPattern.MatchString(joined) {
					return "running the Antigravity SDK"
				}
			}
			return ""
		}

	nextIter:
	}
}

func skipSimpleFlags(args []string, takesArg map[string]bool) []string {
	i := 0
	for i < len(args) {
		f := args[i]
		if f == "--" {
			return args[i+1:]
		}
		if !strings.HasPrefix(f, "-") || f == "-" {
			break
		}
		if takesArg != nil && takesArg[f] {
			i += 2
			continue
		}
		i++
	}
	if i > len(args) {
		return nil
	}
	return args[i:]
}

func commandProblemDepth(command string, depth int) string {
	if depth > maxRecursionDepth {
		return ""
	}
	file, err := syntax.NewParser().Parse(strings.NewReader(command), "")
	if err != nil {
		// PowerShellやcmdの中身はbashとして読めない(`& C:\...\agy.exe`)。拒否すると
		// それらを全部止め、通すと見逃すので、クォートを見ずに区切り記号と空白で分けて調べる。
		for _, part := range strings.FieldsFunc(command, func(r rune) bool { return strings.ContainsRune(";&|()\n", r) }) {
			args := strings.Fields(part)
			for i := range args {
				args[i] = strings.Trim(args[i], `"'`)
			}
			if problem := checkSimpleCommand(args, depth); problem != "" {
				return problem
			}
		}
		return ""
	}
	var problem string
	syntax.Walk(file, func(node syntax.Node) bool {
		if call, ok := node.(*syntax.CallExpr); ok && problem == "" {
			args := make([]string, len(call.Args))
			for i, word := range call.Args {
				args[i] = wordText(command, word)
			}
			problem = checkSimpleCommand(args, depth)
		}
		return problem == ""
	})
	return problem
}

// wordTextは、クォートを外した語を返す。クォートの外のバックスラッシュは、
// Windowsのパス(C:\Users\...)を壊さないように残す。
func wordText(src string, word *syntax.Word) string {
	var b strings.Builder
	for _, part := range word.Parts {
		switch part := part.(type) {
		case *syntax.SglQuoted:
			b.WriteString(part.Value)
		case *syntax.DblQuoted:
			for _, inner := range part.Parts {
				if lit, ok := inner.(*syntax.Lit); ok {
					b.WriteString(dblQuoteEscape.Replace(lit.Value))
				} else {
					b.WriteString(src[inner.Pos().Offset():inner.End().Offset()])
				}
			}
		default:
			b.WriteString(src[part.Pos().Offset():part.End().Offset()])
		}
	}
	return b.String()
}

func commandProblem(command string) string {
	return commandProblemDepth(command, 0)
}

type toolCall struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

func run(stdin io.Reader, stdout io.Writer) error {
	var call toolCall
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		return fmt.Errorf("read tool call: %w", err)
	}
	if call.ToolName != "Bash" {
		return nil
	}
	problem := commandProblem(call.ToolInput.Command)
	if problem == "" {
		return nil
	}

	return json.NewEncoder(stdout).Encode(map[string]any{
		"hookSpecificOutput": map[string]string{
			"hookEventName":      "PreToolUse",
			"permissionDecision": "deny",
			"permissionDecisionReason": "Blocked: " + problem + ". Invoking Antigravity from Claude Code or Codex is not allowed. " +
				"Use Claude Code or Codex directly, or ask the user to run Antigravity.",
		},
	})
}

func main() {
	if err := run(os.Stdin, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "block-antigravity:", err)
		os.Exit(1)
	}
}
