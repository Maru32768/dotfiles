// block-antigravity は Claude Code と Codex の PreToolUse フック。
// Claude Code や Codex が Bash 経由で Antigravity (agy / antigravity / SDK) を
// 呼び出すのを止める。Antigravity には登録しない。
//
// ツール呼び出しの JSON を標準入力で受け取り、コマンド位置で Antigravity を
// 起動する操作を拒否する。bashとして読めるコマンドなら、git commit メッセージや
// grep 等の引数に "antigravity" や "agy" が含まれるだけのものは通す。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"mvdan.cc/sh/v3/syntax"
)

var (
	envAssignPattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*=`)
	pythonNameRegex  = regexp.MustCompile(`^(?:python(?:\d+(?:\.\d+)*)?|py|uv|uvx|pipx)$`)
	sdkRefPattern    = regexp.MustCompile(`(?i)\bgoogle[._-]antigravity\b`)
	litEscape        = regexp.MustCompile(`\\([^\w.\-])`)
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

func checkSimpleCommand(args []string) string {
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
			rem := skipSimpleFlags(rest, map[string]bool{
				"-u": true, "--unset": true, "-C": true, "--chdir": true, "-S": true, "--split-string": true,
			})
			// -Sで分けた語は、envのオプションとして読み直される(`env -S '-i' agy`)。
			for i, f := range rest[:len(rest)-len(rem)] {
				if f == "-S" || f == "--split-string" {
					return commandProblem("env " + strings.Join(rest[i+1:], " "))
				}
				if split, ok := strings.CutPrefix(f, "--split-string="); ok {
					return commandProblem("env " + strings.Join(append([]string{split}, rest[i+1:]...), " "))
				}
			}
			args = rem
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
			if i := slices.Index(rest, "--"); i >= 0 && (rest[0] == "exec" || rest[0] == "x") {
				args = rest[i+1:]
				continue
			}
			return ""
		case "op-run":
			// `op-run <vault> -- <cmd...>` または `op-run <vault> <cmd...>`
			if i := slices.Index(rest, "--"); i >= 0 {
				args = rest[i+1:]
				continue
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
						return commandProblem(rest[i+1])
					}
				}
			}
			return ""
		case "cmd":
			for i := 0; i < len(rest); i++ {
				fl := strings.ToLower(rest[i])
				if fl == "/c" || fl == "/k" {
					if i+1 < len(rest) {
						return commandProblem(strings.Join(rest[i+1:], " "))
					}
				}
			}
			return ""
		case "pwsh", "powershell":
			for i := 0; i < len(rest); i++ {
				fl := strings.ToLower(rest[i])
				if fl == "-c" || fl == "-command" {
					if i+1 < len(rest) {
						return commandProblem(strings.Join(rest[i+1:], " "))
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
		if takesArg[f] {
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

// 入れ子の文字列(`bash -c`の引数など)は親より必ず短いので、再帰は深さを限らなくても終わる。
func commandProblem(command string) string {
	// bashは構文エラーのある行より前の行を実行するので、読み終えた文は構文木で調べる。
	// mvdanの反復は途中でbreakするとpanicすることがあるので、最後まで回す。
	// heredocの中身は後から文に入るので、読み終えてから調べる。
	var stmts []*syntax.Stmt
	var err error
	for stmt, stmtErr := range syntax.NewParser().StmtsSeq(strings.NewReader(command)) {
		if stmtErr != nil {
			err = stmtErr
			continue
		}
		stmts = append(stmts, stmt)
	}
	var problem string
	end := 0
	for _, stmt := range stmts {
		syntax.Walk(stmt, func(node syntax.Node) bool {
			if call, ok := node.(*syntax.CallExpr); ok && problem == "" {
				args := make([]string, len(call.Args))
				for i, word := range call.Args {
					args[i] = wordText(command, word)
				}
				problem = checkSimpleCommand(args)
			}
			return problem == ""
		})
		end = int(stmt.End().Offset())
	}
	if err == nil || problem != "" {
		return problem
	}
	// 残りは、PowerShellやcmdの中身(`& 'C:\Program Files\agy.exe'`)か、bashとして読めない部分。
	// 3つの言語の字句を正しく読めないので、クォートも位置も見ずに、名前が1語でもあれば拒否する。
	rest := command[end:]
	if sdkRefPattern.MatchString(rest) {
		return "running the Antigravity SDK"
	}
	for _, word := range strings.FieldsFunc(rest, func(r rune) bool {
		return unicode.IsSpace(r) || strings.ContainsRune("\"'`;&|(){}[]<>=,$#@", r)
	}) {
		if isAntigravityTarget(word) {
			return "invoking Antigravity (" + word + ")"
		}
	}
	return ""
}

// wordTextは、クォートを外した語を返す。クォートの外のバックスラッシュは、
// Windowsのパス(C:\Users\...)を壊さないように、英数字と`.`、`_`、`-`の前では残す。
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
		case *syntax.Lit:
			b.WriteString(litEscape.ReplaceAllString(strings.ReplaceAll(part.Value, "\\\n", ""), "$1"))
		default:
			b.WriteString(src[part.Pos().Offset():part.End().Offset()])
		}
	}
	return b.String()
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
