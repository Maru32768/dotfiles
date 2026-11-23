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
)

const maxRecursionDepth = 8

var (
	envAssignPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)
	pythonNameRegex  = regexp.MustCompile(`^(?:python(?:\d+(?:\.\d+)*)?|py|uv|uvx|pipx)$`)
	sdkRefPattern    = regexp.MustCompile(`(?i)\bgoogle[._-]antigravity\b`)
	redirPrefixRegex = regexp.MustCompile(`^(?:\d+|&)?(?:>>?|<<?|[<>]&).*`)
)

type parsedLine struct {
	commands [][]string
	embedded []string
}

// parseCommands はシェルコマンド列をクォートを考慮して単純コマンド単位に分解し、
// $(...) や `...` のコマンド置換の中身も再帰検査用に抜き出す。
func parseCommands(input string) parsedLine {
	var res parsedLine
	var curCmd []string
	var curTok strings.Builder
	hasTok := false

	flushTok := func() {
		if hasTok {
			curCmd = append(curCmd, curTok.String())
			curTok.Reset()
			hasTok = false
		}
	}
	flushCmd := func() {
		flushTok()
		if len(curCmd) > 0 {
			res.commands = append(res.commands, curCmd)
			curCmd = nil
		}
	}

	inSingle := false
	inDouble := false
	n := len(input)

	for i := 0; i < n; i++ {
		ch := input[i]

		if inSingle {
			if ch == '\'' {
				inSingle = false
			} else {
				curTok.WriteByte(ch)
			}
			continue
		}

		if inDouble {
			if ch == '\\' && i+1 < n {
				next := input[i+1]
				if next == '"' || next == '\\' || next == '$' || next == '`' || next == '\n' {
					curTok.WriteByte(next)
					i++
					continue
				}
			}
			if ch == '"' {
				inDouble = false
				continue
			}
			if ch == '$' && i+1 < n && input[i+1] == '(' {
				sub, end := extractParenSub(input, i+2)
				res.embedded = append(res.embedded, sub)
				curTok.WriteString(input[i:end])
				i = end - 1
				continue
			}
			if ch == '`' {
				sub, end := extractBacktickSub(input, i+1)
				res.embedded = append(res.embedded, sub)
				curTok.WriteString(input[i:end])
				i = end - 1
				continue
			}
			curTok.WriteByte(ch)
			continue
		}

		switch ch {
		case ' ', '\t', '\r':
			flushTok()
		case '\n', ';', '(', ')':
			flushCmd()
		case '|', '&':
			// リダイレクトの一部 (2>&1, &>, |&) はトークンとして残す
			if ch == '&' && hasTok && strings.HasSuffix(curTok.String(), ">") {
				curTok.WriteByte(ch)
				continue
			}
			if ch == '&' && !hasTok && i+1 < n && input[i+1] == '>' {
				hasTok = true
				curTok.WriteString("&>")
				i++
				continue
			}
			if i+1 < n && input[i+1] == ch {
				i++
			}
			flushCmd()
		case '#':
			if !hasTok {
				// コメント行の末尾まで飛ばす
				for i < n && input[i] != '\n' {
					i++
				}
				flushCmd()
			} else {
				curTok.WriteByte(ch)
			}
		case '\'':
			inSingle = true
			hasTok = true
		case '"':
			inDouble = true
			hasTok = true
		case '\\':
			if i+1 < n {
				if input[i+1] == '\n' {
					i++
					continue
				}
				// Windows パスのバックスラッシュはそのまま保持し、空白や記号のエスケープだけ外す
				next := input[i+1]
				if next == ' ' || next == '\t' || next == '"' || next == '\'' || next == ';' || next == '|' || next == '&' || next == '\\' {
					hasTok = true
					curTok.WriteByte(next)
					i++
					continue
				}
			}
			hasTok = true
			curTok.WriteByte(ch)
		case '$':
			if i+1 < n && input[i+1] == '(' {
				sub, end := extractParenSub(input, i+2)
				res.embedded = append(res.embedded, sub)
				hasTok = true
				curTok.WriteString(input[i:end])
				i = end - 1
				continue
			}
			hasTok = true
			curTok.WriteByte(ch)
		case '`':
			sub, end := extractBacktickSub(input, i+1)
			res.embedded = append(res.embedded, sub)
			hasTok = true
			curTok.WriteString(input[i:end])
			i = end - 1
		default:
			hasTok = true
			curTok.WriteByte(ch)
		}
	}
	flushCmd()
	return res
}

func extractParenSub(s string, start int) (string, int) {
	depth := 1
	inSingle := false
	inDouble := false
	for i := start; i < len(s); i++ {
		ch := s[i]
		if inSingle {
			if ch == '\'' {
				inSingle = false
			}
			continue
		}
		if inDouble {
			if ch == '\\' && i+1 < len(s) {
				i++
				continue
			}
			if ch == '"' {
				inDouble = false
			}
			continue
		}
		switch ch {
		case '\\':
			if i+1 < len(s) {
				i++
			}
		case '\'':
			inSingle = true
		case '"':
			inDouble = true
		case '(':
			depth++
		case ')':
			depth--
			if depth == 0 {
				return s[start:i], i + 1
			}
		}
	}
	return s[start:], len(s)
}

func extractBacktickSub(s string, start int) (string, int) {
	for i := start; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
			continue
		}
		if s[i] == '`' {
			return s[start:i], i + 1
		}
	}
	return s[start:], len(s)
}

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

// stripLeadingNoise はコマンド先頭にある環境変数代入やリダイレクトを除く。
func stripLeadingNoise(args []string) []string {
	i := 0
	for i < len(args) {
		tok := args[i]
		if envAssignPattern.MatchString(tok) {
			i++
			continue
		}
		if redirPrefixRegex.MatchString(tok) {
			// 単独の `>` / `>>` / `2>` などは次のトークン (ファイル名) も飛ばす
			if tok == ">" || tok == ">>" || tok == "<" || tok == "&>" || tok == "1>" || tok == "2>" || tok == "2>>" {
				i += 2
			} else {
				i++
			}
			continue
		}
		break
	}
	return args[i:]
}

func checkSimpleCommand(args []string, depth int) string {
	if depth > maxRecursionDepth {
		return ""
	}
	for {
		args = stripLeadingNoise(args)
		if len(args) == 0 {
			return ""
		}
		raw := args[0]
		base := normalizeCmdName(raw)
		rest := args[1:]

		if isAntigravityTarget(raw) {
			return "invoking Antigravity (" + raw + ")"
		}

		// PowerShell の呼び出し演算子 `&`
		if raw == "&" {
			args = rest
			continue
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
			args = rest[i:]
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
	parsed := parseCommands(command)
	for _, cmd := range parsed.commands {
		if problem := checkSimpleCommand(cmd, depth); problem != "" {
			return problem
		}
	}
	for _, sub := range parsed.embedded {
		if problem := commandProblemDepth(sub, depth+1); problem != "" {
			return problem
		}
	}
	return ""
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
