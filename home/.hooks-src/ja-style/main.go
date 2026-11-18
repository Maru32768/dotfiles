// ja-style は Claude Code の PostToolUse フック。
// Edit と Write で足した行を、~/.claude/CLAUDE.md の｢日本語の表記｣の規則で検査し、
// 違反を Claude に返す。
//
// 引用、外部のデータ、履歴などの対象外は文脈でしか決まらないので、拒否はせず、
// 判断を Claude に任せる。前からある行は報告しない。一括で揃えさせないため。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

const (
	fullwidthAlnum = "全角の英数字は半角にする"
	fullwidthParen = "全角の丸括弧は半角の()にする"
	kagi           = "カギカッコは半角の｢｣にする"
	nakaguro       = "中黒は半角の･にする"
	spacing        = "日本語と英数字の間にスペースを入れない"
	parenSpace     = "丸括弧の内側と外側にスペースを入れない"
	markSpace      = "カギカッコと中黒の前後にスペースを入れない"

	maxReports   = 20
	maxLineRunes = 100
)

const (
	ja   = `\p{Han}\p{Hiragana}\p{Katakana}\x{30FC}\x{3005}`
	word = `[` + ja + `A-Za-z0-9]`
	sp   = `[ \t\x{3000}]+`
	mark = `[\x{FF62}\x{FF63}\x{FF65}]`
	// URL に入らず、日本語の文で URL の直後に来る文字。
	urlEnd = `\s\x{3000}\x{3001}\x{3002}\x{FF08}\x{FF09}\x{300C}\x{300D}\x{FF63}"|<>()`
)

var (
	hasJapanese = regexp.MustCompile(`[` + ja + `]`)
	codeSpan    = regexp.MustCompile("``.+?``|`[^`]+`")
	url         = regexp.MustCompile(`https?://(?:[^` + urlEnd + `]|\([^` + urlEnd + `]*\))+\)?`)
	rules       = []struct {
		pattern *regexp.Regexp
		problem string
	}{
		{regexp.MustCompile(`[\x{FF10}-\x{FF19}\x{FF21}-\x{FF3A}\x{FF41}-\x{FF5A}]`), fullwidthAlnum},
		{regexp.MustCompile(`[\x{FF08}\x{FF09}]`), fullwidthParen},
		{regexp.MustCompile(`[\x{300C}\x{300D}]`), kagi},
		{regexp.MustCompile(`\x{30FB}`), nakaguro},
		{regexp.MustCompile(`[` + ja + `]` + sp + `[A-Za-z0-9]|[A-Za-z0-9]` + sp + `[` + ja + `]`), spacing},
		{regexp.MustCompile(`[` + ja + `]` + sp + `\(|\)` + sp + `[` + ja + `]|\(` + sp + `[` + ja + `]|[` + ja + `]` + sp + `\)`), parenSpace},
		{regexp.MustCompile(word + sp + mark + `|` + mark + sp + word), markSpace},
	}
)

func lineProblems(line string) []string {
	// コードの中身は検査しないが、コードと日本語の間のスペースは検査するため、英字に置き換える。
	// URL は、前のスペースを検査し、規則で残す後ろのスペースは検査しないように、英字と記号に置き換える。
	// 日本語を含む URL があるので、文字の種類では終わりを決められない。空白、句読点、閉じカギカッコと、
	// 対応の無い閉じ括弧(Markdown のリンクの終わり)で見分ける。
	line = url.ReplaceAllString(codeSpan.ReplaceAllString(line, "x"), "x/")
	if !hasJapanese.MatchString(line) {
		return nil
	}
	var problems []string
	for _, rule := range rules {
		if rule.pattern.MatchString(line) {
			problems = append(problems, rule.problem)
		}
	}
	return problems
}

type hunk struct {
	NewStart int      `json:"newStart"`
	Lines    []string `json:"lines"`
}

func addedLines(patch []hunk) []int {
	var added []int
	for _, h := range patch {
		n := h.NewStart
		for _, l := range h.Lines {
			switch {
			case strings.HasPrefix(l, "+"):
				added = append(added, n)
				n++
			case strings.HasPrefix(l, " "):
				n++
			}
		}
	}
	return added
}

type toolCall struct {
	ToolInput struct {
		FilePath string `json:"file_path"`
	} `json:"tool_input"`
	ToolResponse struct {
		Type            string `json:"type"`
		StructuredPatch []hunk `json:"structuredPatch"`
	} `json:"tool_response"`
}

func report(call toolCall) ([]string, error) {
	create := call.ToolResponse.Type == "create"
	targets := addedLines(call.ToolResponse.StructuredPatch)
	if !create && len(targets) == 0 {
		return nil, nil
	}
	path := call.ToolInput.FilePath
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	if create {
		targets = nil
		for i := range lines {
			targets = append(targets, i+1)
		}
	}

	inFence := make([]bool, len(lines)+1)
	switch strings.ToLower(filepath.Ext(path)) {
	case ".md", ".markdown", ".mdx":
		open := false
		for i, l := range lines {
			t := strings.TrimLeft(l, " ")
			fence := strings.HasPrefix(t, "```") || strings.HasPrefix(t, "~~~")
			inFence[i+1] = open || fence
			if fence {
				open = !open
			}
		}
	}

	var reports []string
	for _, n := range targets {
		if n < 1 || n > len(lines) || inFence[n] {
			continue
		}
		problems := lineProblems(lines[n-1])
		if len(problems) == 0 {
			continue
		}
		// 1行のJSONやバンドルしたJSを書いたときに、報告がClaudeの文脈を埋めないように切る。
		line := []rune(lines[n-1])
		if len(line) > maxLineRunes {
			line = append(line[:maxLineRunes], '…')
		}
		reports = append(reports, fmt.Sprintf("%s:%d: %s: %s", path, n, strings.Join(problems, "、"), string(line)))
	}
	return reports, nil
}

func run(stdin io.Reader, stderr io.Writer) int {
	var call toolCall
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		fmt.Fprintln(stderr, "ja-style: read tool call:", err)
		return 1
	}
	reports, err := report(call)
	if err != nil {
		fmt.Fprintln(stderr, "ja-style:", err)
		return 1
	}
	if len(reports) == 0 {
		return 0
	}
	fmt.Fprintln(stderr, "足した行に、~/.claude/CLAUDE.mdの｢日本語の表記｣に合わない箇所がある。直す。引用、外部のデータ、履歴などの対象外か、プロジェクトに別の規則があれば、直さない。")
	if len(reports) > maxReports {
		fmt.Fprintf(stderr, "(%d件のうち最初の%d件)\n", len(reports), maxReports)
		reports = reports[:maxReports]
	}
	fmt.Fprintln(stderr, strings.Join(reports, "\n"))
	return 2
}

func main() {
	os.Exit(run(os.Stdin, os.Stderr))
}
