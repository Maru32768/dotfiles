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
	"slices"
	"sort"
	"strings"
	"unicode"
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
	TargetContent      string `json:"TargetContent"`
	ReplacementContent string `json:"ReplacementContent"`
	StartLine          int    `json:"StartLine"`
	EndLine            int    `json:"EndLine"`
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
	InvocationNum  *int   `json:"invocationNum"`
	ConversationID string `json:"conversationId"`
	Error          string `json:"error"`
	ToolCall       *struct {
		Name string `json:"name"`
		Args struct {
			replacementChunk
			Path              string             `json:"Path"`
			TargetFile        string             `json:"TargetFile"`
			FilePath          string             `json:"file_path"`
			Content           string             `json:"Content"`
			CodeContent       string             `json:"CodeContent"`
			Target            string             `json:"Target"`
			Replacement       string             `json:"Replacement"`
			AllowMultiple     bool               `json:"AllowMultiple"`
			ReplacementChunks []replacementChunk `json:"ReplacementChunks"`
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

func checkAmbiguousLines(path string, lines []string, inFence []bool, candidates, added []int, text []string) []string {
	var reports []string
	for _, offset := range added {
		fragment := text[offset]
		problems := lineProblems(fragment)
		for _, start := range candidates {
			if inFence[start+offset+1] {
				problems = nil
				break
			}
			actualProblems := lineProblems(lines[start+offset])
			problems = slices.DeleteFunc(problems, func(problem string) bool {
				return !slices.Contains(actualProblems, problem)
			})
		}
		if len(problems) > 0 {
			reports = append(reports, formatReportLine(path, 0, fragment, problems))
		}
	}
	return reports
}

func textLines(text string) []string {
	if text == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(strings.ReplaceAll(text, "\r\n", "\n"), "\n"), "\n")
}

func editedFileLines(cwd, path string) []string {
	disk := nativePath(path, runtime.GOOS)
	if cwd != "" && !filepath.IsAbs(disk) {
		disk = filepath.Join(nativePath(cwd, runtime.GOOS), disk)
	}
	data, err := os.ReadFile(disk)
	if err != nil {
		return nil
	}
	return textLines(string(data))
}

func normalizeCodexContext(line string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case '\u2010', '\u2011', '\u2012', '\u2013', '\u2014', '\u2015', '\u2212':
			return '-'
		case '\u2018', '\u2019', '\u201a', '\u201b':
			return '\''
		case '\u201c', '\u201d', '\u201e', '\u201f':
			return '"'
		case '\u00a0', '\u2002', '\u2003', '\u2004', '\u2005', '\u2006', '\u2007',
			'\u2008', '\u2009', '\u200a', '\u202f', '\u205f', '\u3000':
			return ' '
		default:
			return r
		}
	}, strings.TrimSpace(line))
}

func codexAnchor(lines []string, anchor string) int {
	for _, normalize := range []func(string) string{
		func(line string) string { return line },
		func(line string) string { return strings.TrimRightFunc(line, unicode.IsSpace) },
		strings.TrimSpace,
		normalizeCodexContext,
	} {
		wanted := normalize(anchor)
		if i := slices.IndexFunc(lines, func(line string) bool { return normalize(line) == wanted }); i >= 0 {
			return i
		}
	}
	return -1
}

func matchingPatchStarts(lines, wanted []string, added []int, first int) []int {
	var starts []int
	for i := first; i+len(wanted) <= len(lines); i++ {
		matches := true
		for j, line := range wanted {
			actual := lines[i+j]
			if line != actual && (slices.Contains(added, j) || normalizeCodexContext(actual) != normalizeCodexContext(line)) {
				matches = false
				break
			}
		}
		if matches {
			starts = append(starts, i)
		}
	}
	return starts
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
	var result string
	if json.Unmarshal(call.ToolResponse, &result) == nil && strings.HasPrefix(result, "Exit code: ") &&
		!strings.HasPrefix(result, "Exit code: 0\n") {
		return nil
	}
	type patchChunk struct {
		anchor   string
		lines    []string
		added    []int
		oldLines int
		atEnd    bool
	}
	var reports []string
	for _, text := range extractPatchTexts(call) {
		var path string
		var create bool
		var chunks []patchChunk
		flush := func() {
			lines := editedFileLines(call.Cwd, path)
			var targets []int
			var fences []bool
			first := 0
			appendAt := len(lines)
			if !create {
				for _, chunk := range chunks {
					if chunk.oldLines == 0 {
						appendAt -= len(chunk.lines)
					}
				}
			}
			originalRegion := lines[:max(0, appendAt)]
			for _, chunk := range chunks {
				if len(chunk.lines) == 0 && chunk.anchor == "" {
					continue
				}
				if chunk.anchor != "" {
					anchor := codexAnchor(originalRegion[first:], chunk.anchor)
					if anchor < 0 {
						break
					}
					first += anchor + 1
				}
				start := first
				switch {
				case create:
					start = 0
				case chunk.oldLines == 0:
					start = appendAt
					appendAt += len(chunk.lines)
				default:
					locate := func() []int {
						if chunk.atEnd && len(chunk.lines) <= len(originalRegion)-first {
							eof := len(originalRegion) - len(chunk.lines)
							if starts := matchingPatchStarts(originalRegion, chunk.lines, chunk.added, eof); len(starts) > 0 {
								return starts
							}
						}
						return matchingPatchStarts(originalRegion, chunk.lines, chunk.added, first)
					}
					starts := locate()
					last := len(chunk.lines) - 1
					if len(starts) == 0 && last >= 0 && chunk.lines[last] == "" && !slices.Contains(chunk.added, last) {
						// Codexは終端の改行を表す空の文脈行を除いて再照合する。
						chunk.lines = chunk.lines[:last]
						starts = locate()
					}
					if len(starts) == 0 {
						continue
					}
					start = starts[0]
					if len(starts) > 1 {
						if fences == nil {
							fences = fenceMask(path, lines)
						}
						reports = append(reports, checkAmbiguousLines(path, lines, fences, starts, chunk.added, chunk.lines)...)
						first = start + len(chunk.lines)
						continue
					}
				}
				end := start + len(chunk.lines)
				if start < first || end > len(lines) {
					continue
				}
				if (create || chunk.oldLines == 0) && !slices.Equal(lines[start:end], chunk.lines) {
					continue
				}
				for _, offset := range chunk.added {
					targets = append(targets, start+offset+1)
				}
				if chunk.oldLines > 0 {
					first = end
				}
			}
			reports = append(reports, checkLines(path, lines, targets)...)
		}
		for _, line := range textLines(text) {
			switch {
			case strings.HasPrefix(line, "*** Move to: "):
				path = strings.TrimSpace(strings.TrimPrefix(line, "*** Move to: "))
			case patchFileHeader.MatchString(line):
				if path != "" {
					flush()
				}
				path = strings.TrimSpace(patchFileHeader.FindStringSubmatch(line)[1])
				create = strings.HasPrefix(line, "*** Add File: ")
				chunks = []patchChunk{{}}
			case strings.HasPrefix(line, "*** Delete File:"), line == "*** End Patch":
				if path != "" {
					flush()
					path = ""
				}
			case path != "" && strings.HasPrefix(line, "@@"):
				chunks = append(chunks, patchChunk{anchor: strings.TrimPrefix(strings.TrimPrefix(line, "@@"), " ")})
			case path != "":
				chunk := &chunks[len(chunks)-1]
				switch {
				case line == "*** End of File":
					chunk.atEnd = true
				case strings.HasPrefix(line, "+"):
					chunk.added = append(chunk.added, len(chunk.lines))
					chunk.lines = append(chunk.lines, line[1:])
				case strings.HasPrefix(line, " "):
					chunk.lines = append(chunk.lines, line[1:])
					chunk.oldLines++
				case line == "" && !create:
					chunk.lines = append(chunk.lines, "")
					chunk.oldLines++
				case strings.HasPrefix(line, "-"):
					chunk.oldLines++
				}
			}
		}
		if path != "" {
			flush()
		}
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
	lines := editedFileLines(call.Cwd, path)
	if firstNonEmpty(args.CodeContent, args.Content) != "" {
		targets := make([]int, len(lines))
		for i := range targets {
			targets[i] = i + 1
		}
		return checkLines(path, lines, targets)
	}
	chunks := args.ReplacementChunks
	if len(chunks) == 0 {
		chunk := args.replacementChunk
		chunk.TargetContent = firstNonEmpty(chunk.TargetContent, args.Target)
		chunk.ReplacementContent = firstNonEmpty(chunk.ReplacementContent, args.Replacement)
		chunks = []replacementChunk{chunk}
	}
	sort.SliceStable(chunks, func(i, j int) bool { return chunks[i].StartLine < chunks[j].StartLine })
	var targets []int
	var reports []string
	var fences []bool
	shift := 0
	for _, chunk := range chunks {
		before := textLines(chunk.TargetContent)
		after := textLines(chunk.ReplacementContent)
		delta := len(after) - len(before)
		first, last := 0, len(lines)
		if chunk.StartLine > 0 {
			first = max(0, chunk.StartLine-1+shift)
		}
		if chunk.EndLine > 0 {
			last = chunk.EndLine + shift + delta
		}
		rangeGrowth := 0
		if args.AllowMultiple && chunk.EndLine > 0 {
			rangeGrowth = delta
		}
		starts := replacementStarts(lines, after, first, last, rangeGrowth)
		if args.AllowMultiple {
			shift += max(1, len(starts)) * delta
		} else {
			shift += delta
		}
		starts = slices.Compact(starts)
		offsets := addedOffsets(before, after)
		if len(starts) > 1 {
			if fences == nil {
				fences = fenceMask(path, lines)
			}
			reports = append(reports, checkAmbiguousLines(path, lines, fences, starts, offsets, after)...)
			continue
		}
		for _, start := range starts {
			for _, offset := range offsets {
				targets = append(targets, start+offset+1)
			}
		}
	}
	slices.Sort(targets)
	return append(reports, checkLines(path, lines, slices.Compact(targets))...)
}

func replacementStarts(lines, replacement []string, first, last, rangeGrowth int) []int {
	text := strings.Join(replacement, "\n")
	if text == "" || first >= len(lines) {
		return nil
	}
	pending := strings.Join(lines[first:], "\n")
	var starts []int
	for {
		at := strings.Index(pending, text)
		if at < 0 {
			return starts
		}
		line := first + strings.Count(pending[:at], "\n")
		if line+len(replacement) > last {
			return starts
		}
		starts = append(starts, line)
		last += rangeGrowth
		first = line + len(replacement) - 1
		pending = pending[at+len(text):]
	}
}

func addedOffsets(before, after []string) []int {
	first := 0
	for first < min(len(before), len(after)) && before[first] == after[first] {
		first++
	}
	before, after = before[first:], after[first:]
	for len(before) > 0 && len(after) > 0 && before[len(before)-1] == after[len(after)-1] {
		before, after = before[:len(before)-1], after[:len(after)-1]
	}
	// 置換範囲に残った文脈行を除く。大きな置換でフックがタイムアウトするのを避ける。
	const maxCells = 1 << 20
	if len(after) > 0 && len(before) > maxCells/len(after) {
		return nil
	}
	width := len(after) + 1
	lcs := make([]int, (len(before)+1)*width)
	for i := len(before) - 1; i >= 0; i-- {
		for j := len(after) - 1; j >= 0; j-- {
			if before[i] == after[j] {
				lcs[i*width+j] = 1 + lcs[(i+1)*width+j+1]
			} else {
				lcs[i*width+j] = max(lcs[(i+1)*width+j], lcs[i*width+j+1])
			}
		}
	}
	var added []int
	for i, j := 0, 0; j < len(after); {
		switch {
		case i < len(before) && before[i] == after[j]:
			i++
			j++
		case i < len(before) && lcs[(i+1)*width+j] >= lcs[i*width+j+1]:
			i++
		default:
			added = append(added, first+j)
			j++
		}
	}
	return added
}

func runAntigravity(call toolCall, stdout io.Writer) int {
	queueFile := agyQueuePath(call.ConversationID)
	if call.isAntigravityPreInvocation() {
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

func (call toolCall) isAntigravityPreInvocation() bool {
	return call.InvocationNum != nil || call.HookEventName == "PreInvocation"
}

func run(stdin io.Reader, stdout, stderr io.Writer) int {
	var call toolCall
	if err := json.NewDecoder(stdin).Decode(&call); err != nil {
		fmt.Fprintln(stderr, "ja-style: read tool call:", err)
		return 1
	}

	if call.isAntigravityPreInvocation() || (call.ToolCall != nil && call.ToolCall.Name != "") {
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
