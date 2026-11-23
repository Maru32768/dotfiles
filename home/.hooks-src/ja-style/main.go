// ja-styleはClaude Code、Codex、Antigravityのフック。
// ファイル編集で足した行を｢日本語の表記｣の規則で検査し、違反をエージェントに返す。
//
// 引用、外部のデータ、履歴などの対象外は文脈でしか決まらないので、拒否はせず、
// 判断をエージェントに任せる。変えていない行は報告しない。一括で揃えさせないため。
// AntigravityのPostToolUseはモデルへの返答経路を持たないため、違反を一時ファイルに
// 溜めて次のPreInvocationでsystemMessageとして差し込む。
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
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

	reportHeader = "足した行に｢日本語の表記｣に合わない箇所がある。直す。引用、外部のデータ、履歴などの対象外か、プロジェクトに別の規則があれば、直さない。"

	maxReports   = 20
	maxLineRunes = 100
)

const (
	ja   = `\p{Han}\p{Hiragana}\p{Katakana}\x{30FC}\x{3005}`
	word = `[` + ja + `A-Za-z0-9]`
	sp   = `[ \t\x{3000}]+`
	mark = `[\x{FF62}\x{FF63}\x{FF65}]`
	// URLに入らず、日本語の文でURLの直後に来る文字。
	urlEnd = `\s\x{3000}\x{3001}\x{3002}\x{FF08}\x{FF09}\x{300C}\x{300D}\x{FF63}"|<>()`
)

var (
	hasJapanese     = regexp.MustCompile(`[` + ja + `]`)
	codeSpan        = regexp.MustCompile("``.+?``|`[^`]+`")
	url             = regexp.MustCompile(`https?://(?:[^` + urlEnd + `]|\([^` + urlEnd + `]*\))+\)?`)
	patchFileHeader = regexp.MustCompile(`^\*\*\* (?:Update File|Add File|Move to): (.+)$`)
	safeID          = regexp.MustCompile(`[^A-Za-z0-9._-]`)
	rules           = []struct {
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

	agyQueueDir = os.TempDir()
)

func lineProblems(line string) []string {
	// コードの中身は検査しないが、コードと日本語の間のスペースは検査するため、英字に置き換える。
	// URLは、前のスペースを検査し、規則で残す後ろのスペースは検査しないように、英字と記号に置き換える。
	// 日本語を含むURLがあるので、文字の種類では終わりを決められない。空白、句読点、閉じカギカッコと、
	// 対応の無い閉じ括弧(Markdownのリンクの終わり)で見分ける。
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

type replacementChunk struct {
	ReplacementContent string `json:"ReplacementContent"`
}

type toolCall struct {
	// Claude Code / Codex 形式
	Cwd       string `json:"cwd"`
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		FilePath string          `json:"file_path"`
		Command  string          `json:"command"`
		Input    string          `json:"input"`
		Patch    string          `json:"patch"`
		Cmd      json.RawMessage `json:"cmd"`
	} `json:"tool_input"`
	ToolResponse json.RawMessage `json:"tool_response"`

	// Antigravity 形式 (camelCase)
	HookEventName  string `json:"hookEventName"`
	ConversationID string `json:"conversationId"`
	Error          string `json:"error"`
	ToolCall       *struct {
		Name string `json:"name"`
		Args struct {
			Path               string             `json:"Path"`
			TargetFile         string             `json:"TargetFile"`
			FilePath           string             `json:"file_path"`
			Content            string             `json:"Content"`
			CodeContent        string             `json:"CodeContent"`
			Replacement        string             `json:"Replacement"`
			ReplacementContent string             `json:"ReplacementContent"`
			ReplacementChunks  []replacementChunk `json:"ReplacementChunks"`
		} `json:"args"`
	} `json:"toolCall"`
}

var gitBashDrive = regexp.MustCompile(`^/([A-Za-z])(/|$)`)

// WindowsのClaude Codeは、Git Bashの形のパス(/c/Users/...)をそのままフックに渡すことがある。
func nativePath(path, goos string) string {
	if goos != "windows" {
		return path
	}
	return gitBashDrive.ReplaceAllString(path, "$1:/")
}

func fenceMask(path string, lines []string) []bool {
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
	return inFence
}

func formatReportLine(path string, lineNum int, rawLine string, problems []string) string {
	// 1行のJSONやバンドルしたJSを書いたときに、報告がエージェントの文脈を埋めないように切る。
	line := []rune(rawLine)
	if len(line) > maxLineRunes {
		line = append(line[:maxLineRunes], '…')
	}
	if lineNum > 0 {
		return fmt.Sprintf("%s:%d: %s: %s", path, lineNum, strings.Join(problems, "、"), string(line))
	}
	return fmt.Sprintf("%s: %s: %s", path, strings.Join(problems, "、"), string(line))
}

func formatMessage(reports []string) string {
	var b strings.Builder
	b.WriteString(reportHeader)
	b.WriteByte('\n')
	if len(reports) > maxReports {
		fmt.Fprintf(&b, "(%d件のうち最初の%d件)\n", len(reports), maxReports)
		reports = reports[:maxReports]
	}
	b.WriteString(strings.Join(reports, "\n"))
	return b.String()
}

func checkLines(path string, lines []string, targets []int) []string {
	inFence := fenceMask(path, lines)
	var reports []string
	for _, n := range targets {
		if n < 1 || n > len(lines) || inFence[n] {
			continue
		}
		problems := lineProblems(lines[n-1])
		if len(problems) == 0 {
			continue
		}
		reports = append(reports, formatReportLine(path, n, lines[n-1], problems))
	}
	return reports
}

func checkMatchingLines(displayPath, diskPath string, addedTexts []string) []string {
	if len(addedTexts) == 0 {
		return nil
	}
	counts := make(map[string]int, len(addedTexts))
	for _, s := range addedTexts {
		counts[s]++
	}
	if data, err := os.ReadFile(diskPath); err == nil {
		lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
		var targets []int
		for i, l := range lines {
			if counts[l] > 0 {
				targets = append(targets, i+1)
				counts[l]--
			}
		}
		return checkLines(displayPath, lines, targets)
	}
	var reports []string
	for _, l := range addedTexts {
		if problems := lineProblems(l); len(problems) > 0 {
			reports = append(reports, formatReportLine(displayPath, 0, l, problems))
		}
	}
	return reports
}

func report(call toolCall) ([]string, error) {
	var response struct {
		Type            string `json:"type"`
		StructuredPatch []hunk `json:"structuredPatch"`
	}
	if len(call.ToolResponse) > 0 {
		if err := json.Unmarshal(call.ToolResponse, &response); err != nil {
			return nil, err
		}
	}
	create := response.Type == "create"
	targets := addedLines(response.StructuredPatch)
	if !create && len(targets) == 0 {
		return nil, nil
	}
	path := call.ToolInput.FilePath
	data, err := os.ReadFile(nativePath(path, runtime.GOOS))
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
	return checkLines(path, lines, targets), nil
}

func extractPatchTexts(call toolCall) []string {
	var texts []string
	for _, s := range []string{call.ToolInput.Input, call.ToolInput.Patch, call.ToolInput.Command} {
		if s != "" {
			texts = append(texts, s)
		}
	}
	if len(call.ToolInput.Cmd) > 0 {
		var s string
		if err := json.Unmarshal(call.ToolInput.Cmd, &s); err == nil && s != "" {
			texts = append(texts, s)
		} else {
			var arr []string
			if err := json.Unmarshal(call.ToolInput.Cmd, &arr); err == nil {
				texts = append(texts, arr...)
			}
		}
	}
	return texts
}

func reportCodexPatch(call toolCall) []string {
	type fileAdds struct {
		path  string
		lines []string
	}
	var files []*fileAdds
	byPath := map[string]*fileAdds{}
	for _, text := range extractPatchTexts(call) {
		var cur *fileAdds
		for _, raw := range strings.Split(text, "\n") {
			line := strings.TrimRight(raw, "\r")
			if m := patchFileHeader.FindStringSubmatch(line); m != nil {
				p := strings.TrimSpace(m[1])
				if cur = byPath[p]; cur == nil {
					cur = &fileAdds{path: p}
					byPath[p] = cur
					files = append(files, cur)
				}
				continue
			}
			if strings.HasPrefix(line, "*** ") {
				if strings.HasPrefix(line, "*** Delete File:") || strings.HasPrefix(line, "*** End Patch") {
					cur = nil
				}
				continue
			}
			if cur != nil && strings.HasPrefix(line, "+") && !strings.HasPrefix(line, "+++") {
				cur.lines = append(cur.lines, line[1:])
			}
		}
	}
	var reports []string
	for _, f := range files {
		disk := nativePath(f.path, runtime.GOOS)
		if call.Cwd != "" && !filepath.IsAbs(disk) {
			disk = filepath.Join(nativePath(call.Cwd, runtime.GOOS), disk)
		}
		reports = append(reports, checkMatchingLines(f.path, disk, f.lines)...)
	}
	return reports
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

func agyQueuePath(conversationID string) string {
	id := safeID.ReplaceAllString(conversationID, "_")
	if id == "" {
		id = "default"
	}
	return filepath.Join(agyQueueDir, "ja-style-agy-"+id+".txt")
}

func reportAntigravityPostTool(call toolCall) []string {
	if call.Error != "" || call.ToolCall == nil {
		return nil
	}
	args := call.ToolCall.Args
	path := firstNonEmpty(args.Path, args.TargetFile, args.FilePath)
	if path == "" {
		return nil
	}
	disk := nativePath(path, runtime.GOOS)
	if call.Cwd != "" && !filepath.IsAbs(disk) {
		disk = filepath.Join(nativePath(call.Cwd, runtime.GOOS), disk)
	}
	var texts []string
	for _, s := range []string{args.Replacement, args.ReplacementContent, args.Content, args.CodeContent} {
		if s != "" {
			texts = append(texts, s)
		}
	}
	for _, ch := range args.ReplacementChunks {
		if ch.ReplacementContent != "" {
			texts = append(texts, ch.ReplacementContent)
		}
	}
	var added []string
	for _, t := range texts {
		added = append(added, strings.Split(strings.ReplaceAll(t, "\r\n", "\n"), "\n")...)
	}
	return checkMatchingLines(path, disk, added)
}

func runAntigravity(call toolCall, stdout io.Writer) int {
	queueFile := agyQueuePath(call.ConversationID)
	if call.HookEventName == "PreInvocation" {
		data, err := os.ReadFile(queueFile)
		if err != nil || len(bytesTrimSpace(data)) == 0 {
			_, _ = io.WriteString(stdout, "{}\n")
			return 0
		}
		_ = os.Remove(queueFile)
		var lines []string
		for _, l := range strings.Split(strings.TrimSpace(string(data)), "\n") {
			if l != "" {
				lines = append(lines, l)
			}
		}
		_ = json.NewEncoder(stdout).Encode(map[string]any{
			"injectSteps": []map[string]any{
				{
					"systemMessage": map[string]string{
						"systemMessage": formatMessage(lines),
					},
				},
			},
		})
		return 0
	}

	if reports := reportAntigravityPostTool(call); len(reports) > 0 {
		if f, err := os.OpenFile(queueFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600); err == nil {
			_, _ = f.WriteString(strings.Join(reports, "\n") + "\n")
			_ = f.Close()
		}
	}
	_, _ = io.WriteString(stdout, "{}\n")
	return 0
}

func bytesTrimSpace(b []byte) []byte {
	return []byte(strings.TrimSpace(string(b)))
}

func run(stdin io.Reader, stdout, stderr io.Writer) int {
	var call toolCall
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		fmt.Fprintln(stderr, "ja-style: read tool call:", err)
		return 1
	}

	if call.HookEventName == "PreInvocation" || (call.ToolCall != nil && call.ToolCall.Name != "") {
		return runAntigravity(call, stdout)
	}

	if call.ToolName == "apply_patch" {
		reports := reportCodexPatch(call)
		if len(reports) == 0 {
			return 0
		}
		_ = json.NewEncoder(stdout).Encode(map[string]any{
			"hookSpecificOutput": map[string]string{
				"hookEventName":     "PostToolUse",
				"additionalContext": formatMessage(reports),
			},
		})
		return 0
	}

	reports, err := report(call)
	if err != nil {
		fmt.Fprintln(stderr, "ja-style:", err)
		return 1
	}
	if len(reports) == 0 {
		return 0
	}
	fmt.Fprintln(stderr, formatMessage(reports))
	return 2
}

func main() {
	os.Exit(run(os.Stdin, os.Stdout, os.Stderr))
}
