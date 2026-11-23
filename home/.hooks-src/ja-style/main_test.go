package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

var badLines = map[string]string{
	"ＡＩを使う":                            fullwidthAlnum,
	"最大１００件":                           fullwidthAlnum,
	"更新間隔（分）":                          fullwidthParen,
	"「保存」を押す":                          kagi,
	"設計・開発":                            nakaguro,
	"AI を使う":                           spacing,
	"最大 100件":                          spacing,
	"Google Cloud の API":               spacing,
	"`chezmoi` で反映する":                  spacing,
	"更新間隔 (分)":                         parenSpace,
	"更新間隔(分) を見る":                      parenSpace,
	"更新間隔( 分)":                         parenSpace,
	"更新間隔(分 )":                         parenSpace,
	"｢保存｣ を押す":                         markSpace,
	"これは ｢保存｣":                         markSpace,
	"設計 ･ 開発":                          markSpace,
	"// 「保存」を押す":                       kagi,
	"サーバー APIを呼ぶ":                      spacing,
	"人々 100人":                          spacing,
	"詳しくは https://example.com/ を見る":    spacing,
	"`curl https://example.com` で取得する": spacing,
	"[リンク](https://example.com)を見て、ＡＩを使う":          fullwidthAlnum,
	"[リンク](https://example.com)でＡＩを使う":             fullwidthAlnum,
	"[Go](https://go.dev)とGo の違い":                  spacing,
	"https://example.com。ＡＩを使う":                    fullwidthAlnum,
	"https://example.com　ＡＩを使う":                    fullwidthAlnum,
	"｢https://example.com｣ を開く":                    markSpace,
	"https://example.com、ＡＩを使う":                    fullwidthAlnum,
	"https://example.com ＡＩを使う":                    fullwidthAlnum,
	"<https://example.com>でＡＩを使う":                  fullwidthAlnum,
	"https://example.com（英語）を見る":                   fullwidthParen,
	"https://example.com「保存」を押す":                   kagi,
	"https://example.com(英語、ＡＩ向け)を見る":              fullwidthAlnum,
	`{"url":"https://example.com","name":"ＡＩを使う"}`: fullwidthAlnum,
}

var goodLines = []string{
	"AIを使って最大100件の記事を要約する",
	"Google CloudのAPI",
	"更新間隔(分)、最大10件(無料)",
	"｢保存｣を押す",
	"設計･開発",
	"『本』と【注】",
	"`chezmoi source-path <file>`でソースを調べる",
	"`（）`は全角の括弧",
	"https://example.com/a_(b) を開く",
	"See https://example.com を開く",
	"https://ja.wikipedia.org/wiki/Go_(プログラミング言語) を参照する",
	"https://example.com/ＡＩ を見る",
	"[Go](https://ja.wikipedia.org/wiki/Go_(プログラミング言語)) を参照する",
	"[リンク](https://example.com) を見る",
	"http://localhost:8080 を開く",
	"``（`）``を使う",
	"- ｢保存｣を押す",
	"| ｢保存｣ | 押す |",
	"区切りの前後 / は残す",
	"**太字** の隣",
	"WSL (Ubuntu 26.04)",
	"plain English (with parens) only",
	"ＡＩ only",
}

func TestBadLines(t *testing.T) {
	for line, want := range badLines {
		if got := lineProblems(line); !contains(got, want) {
			t.Errorf("%q: got %q, want %q", line, got, want)
		}
	}
}

func TestGoodLines(t *testing.T) {
	for _, line := range goodLines {
		if got := lineProblems(line); len(got) != 0 {
			t.Errorf("%q: got %q, want none", line, got)
		}
	}
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func TestAddedLines(t *testing.T) {
	patch := []hunk{
		{NewStart: 3, Lines: []string{" a", "-b", "+c", "+d", " e"}},
		{NewStart: 10, Lines: []string{"+x", `\ No newline at end of file`}},
	}
	if got, want := addedLines(patch), []int{4, 5, 10}; !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestNativePath(t *testing.T) {
	cases := []struct{ path, goos, want string }{
		{"/c/Users/a.md", "windows", "c:/Users/a.md"},
		{"/C/Users/a.md", "windows", "C:/Users/a.md"},
		{"/c/Users/a/b.md", "windows", "c:/Users/a/b.md"},
		{"C:\\Users\\a.md", "windows", "C:\\Users\\a.md"},
		{"/tmp/a.md", "windows", "/tmp/a.md"},
		{"/c/Users/a.md", "linux", "/c/Users/a.md"},
	}
	for _, c := range cases {
		if got := nativePath(c.path, c.goos); got != c.want {
			t.Errorf("nativePath(%q, %q) = %q, want %q", c.path, c.goos, got, c.want)
		}
	}
}

func TestGitBashPathIsRead(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Git Bashの形のパスはWindowsでだけ直す")
	}
	native := filepath.ToSlash(write(t, "a.md", "AI を使う\n"))
	path := "/" + strings.ToLower(native[:1]) + native[2:]
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "create"},
	})
	if code != 2 || !strings.Contains(out, path+":1:") {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func runHook(t *testing.T, input map[string]any) (string, int) {
	t.Helper()
	data, _ := json.Marshal(input)
	var stdout, stderr bytes.Buffer
	code := run(bytes.NewReader(data), &stdout, &stderr)
	return stderr.String(), code
}

func runHookAll(t *testing.T, input map[string]any) (string, string, int) {
	t.Helper()
	data, _ := json.Marshal(input)
	var stdout, stderr bytes.Buffer
	code := run(bytes.NewReader(data), &stdout, &stderr)
	return stdout.String(), stderr.String(), code
}

func write(t *testing.T, name, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestEditReportsOnlyAddedLines(t *testing.T) {
	path := write(t, "a.md", "古い （行）\n新しい （行）\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Edit",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"filePath": path, "structuredPatch": []hunk{{NewStart: 1, Lines: []string{" 古い （行）", "+新しい （行）"}}}},
	})
	if code != 2 || !strings.Contains(out, path+":2:") || strings.Contains(out, path+":1:") {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func TestWriteCreateChecksAllLines(t *testing.T) {
	path := write(t, "a.txt", "ok\nAI を使う\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "create", "filePath": path, "structuredPatch": []hunk{}},
	})
	if code != 2 || !strings.Contains(out, path+":2:") {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func TestMarkdownFenceIsSkipped(t *testing.T) {
	path := write(t, "a.md", "```\n「コード」\n```\n「本文」\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "create", "filePath": path},
	})
	if code != 2 || strings.Contains(out, path+":2:") || !strings.Contains(out, path+":4:") {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func TestWriteUpdateReportsOnlyAddedLines(t *testing.T) {
	path := write(t, "a.md", "古い （行）\nAIを使う\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "update", "structuredPatch": []hunk{{NewStart: 1, Lines: []string{" 古い （行）", "+AIを使う"}}}},
	})
	if code != 0 || out != "" {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func TestLongLineReportIsBounded(t *testing.T) {
	path := write(t, "a.json", strings.Repeat("（日本「・ A", 50000)+"\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "create"},
	})
	if code != 2 || len(out) > 2000 || strings.Count(out, path+":1:") != 1 {
		t.Errorf("code %d, %d bytes, output:\n%.500s", code, len(out), out)
	}
}

func TestIndentedFenceIsSkipped(t *testing.T) {
	path := write(t, "a.md", "- 例\n\n  ```\n  「コード」\n  ```\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Write",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"type": "create"},
	})
	if code != 0 || out != "" {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func TestCleanEditIsSilent(t *testing.T) {
	path := write(t, "a.md", "AIを使う\n")
	out, code := runHook(t, map[string]any{
		"tool_name":     "Edit",
		"tool_input":    map[string]any{"file_path": path},
		"tool_response": map[string]any{"filePath": path, "structuredPatch": []hunk{{NewStart: 1, Lines: []string{"+AIを使う"}}}},
	})
	if code != 0 || out != "" {
		t.Errorf("code %d, output:\n%s", code, out)
	}
}

func runCodexPatch(t *testing.T, cwd, patch string) (string, string, int) {
	t.Helper()
	return runHookAll(t, map[string]any{
		"cwd":           cwd,
		"tool_name":     "apply_patch",
		"tool_input":    map[string]any{"command": patch},
		"tool_response": "Exit code: 0\nSuccess. Updated the following files:\nM a.md",
	})
}

func TestCodexApplyPatchReportsAddedLinesOnly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "a.md")
	if err := os.WriteFile(path, []byte("古い （行）\n新しい （行）\n```\n「コード」\n```\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	patch := "*** Begin Patch\n*** Update File: a.md\n@@\n 古い （行）\n+新しい （行）\n ```\n+「コード」\n ```\n*** End Patch\n"
	stdout, stderr, code := runCodexPatch(t, dir, patch)
	if code != 0 || stderr != "" {
		t.Fatalf("code %d, stderr %q", code, stderr)
	}
	var resp struct {
		HookSpecificOutput struct {
			HookEventName     string `json:"hookEventName"`
			AdditionalContext string `json:"additionalContext"`
		} `json:"hookSpecificOutput"`
	}
	if err := json.Unmarshal([]byte(stdout), &resp); err != nil {
		t.Fatalf("invalid json %q: %v", stdout, err)
	}
	ctx := resp.HookSpecificOutput.AdditionalContext
	if resp.HookSpecificOutput.HookEventName != "PostToolUse" ||
		!strings.Contains(ctx, "a.md:2:") ||
		strings.Contains(ctx, "a.md:1:") ||
		strings.Contains(ctx, "a.md:4:") {
		t.Errorf("unexpected context:\n%s", ctx)
	}
}

func TestAntigravityPostToolUseQueuesForPreInvocation(t *testing.T) {
	origDir := agyQueueDir
	agyQueueDir = t.TempDir()
	t.Cleanup(func() { agyQueueDir = origDir })

	path := write(t, "a.md", "古い （行）\n新しい （行）\n")
	stdout, stderr, code := runHookAll(t, map[string]any{
		"hookEventName":  "PostToolUse",
		"conversationId": "conv-1",
		"toolCall": map[string]any{
			"name": "replace_file_content",
			"args": map[string]any{
				"TargetFile":         path,
				"TargetContent":      "前の行",
				"ReplacementContent": "新しい （行）",
				"StartLine":          2,
				"EndLine":            2,
			},
		},
	})
	if code != 0 || stderr != "" || strings.TrimSpace(stdout) != "{}" {
		t.Fatalf("PostToolUse: code %d, stdout %q, stderr %q", code, stdout, stderr)
	}

	stdout, stderr, code = runHookAll(t, map[string]any{
		"conversationId":  "conv-1",
		"invocationNum":   1,
		"initialNumSteps": 2,
	})
	if code != 0 || stderr != "" {
		t.Fatalf("PreInvocation: code %d, stderr %q", code, stderr)
	}
	var resp struct {
		InjectSteps []struct {
			SystemMessage struct {
				SystemMessage string `json:"systemMessage"`
			} `json:"systemMessage"`
		} `json:"injectSteps"`
	}
	if err := json.Unmarshal([]byte(stdout), &resp); err != nil {
		t.Fatalf("PreInvocation invalid json %q: %v", stdout, err)
	}
	if len(resp.InjectSteps) != 1 {
		t.Fatalf("PreInvocation injectSteps len = %d", len(resp.InjectSteps))
	}
	msg := resp.InjectSteps[0].SystemMessage.SystemMessage
	if !strings.Contains(msg, path+":2:") || strings.Contains(msg, path+":1:") {
		t.Errorf("PreInvocation message:\n%s", msg)
	}

	// 2回目のPreInvocationではキューが空になっている。
	stdout, _, code = runHookAll(t, map[string]any{
		"conversationId":  "conv-1",
		"invocationNum":   2,
		"initialNumSteps": 3,
	})
	if code != 0 || strings.TrimSpace(stdout) != "{}" {
		t.Errorf("second PreInvocation: code %d, stdout %q", code, stdout)
	}
}

func TestAntigravityReplacementChecksOnlyChangedLinesInRange(t *testing.T) {
	dir := t.TempDir()
	originalQueue := agyQueueDir
	agyQueueDir = dir
	t.Cleanup(func() { agyQueueDir = originalQueue })
	path := write(t, "a.md", "新しい （行）\n\n既存の （文）\n新しい （行）\n")
	_, stderr, code := runHookAll(t, map[string]any{
		"conversationId": "conv-edit",
		"toolCall": map[string]any{
			"name": "replace_file_content",
			"args": map[string]any{
				"TargetFile": path, "StartLine": 3, "EndLine": 4,
				"TargetContent": "既存の （文）\n前の行", "ReplacementContent": "既存の （文）\n新しい （行）",
			},
		},
	})
	if code != 0 || stderr != "" {
		t.Fatalf("PostToolUse: code %d, stderr %q", code, stderr)
	}
	got, _, code := runHookAll(t, map[string]any{"conversationId": "conv-edit", "invocationNum": 1})
	if code != 0 || !strings.Contains(got, "a.md:4:") ||
		strings.Contains(got, "a.md:1:") || strings.Contains(got, "a.md:3:") {
		t.Fatalf("PreInvocation: code %d, output %s", code, got)
	}
}

func TestAntigravityLargeReplacementStillChecksNewProse(t *testing.T) {
	originalQueue := agyQueueDir
	agyQueueDir = t.TempDir()
	t.Cleanup(func() { agyQueueDir = originalQueue })
	middle := strings.Repeat("共通の文\n", 1097) + "既存の （文）\n"
	before := "前の始まり\n" + middle + "前の終わり\n"
	after := "新しい （始まり）\n" + middle + "新しい （終わり）\n"
	path := write(t, "a.md", after)
	_, stderr, code := runHookAll(t, map[string]any{
		"conversationId": "conv-large",
		"toolCall": map[string]any{
			"name": "replace_file_content",
			"args": map[string]any{
				"TargetFile": path, "StartLine": 1, "EndLine": 1100,
				"TargetContent": before, "ReplacementContent": after,
			},
		},
	})
	if code != 0 || stderr != "" {
		t.Fatalf("PostToolUse: code %d, stderr %q", code, stderr)
	}
	got, _, code := runHookAll(t, map[string]any{"conversationId": "conv-large", "invocationNum": 1})
	if code != 0 || !strings.Contains(got, "a.md:1:") || !strings.Contains(got, "a.md:1100:") ||
		strings.Contains(got, "a.md:1099:") {
		t.Fatalf("PreInvocation: code %d, output %s", code, got)
	}
}

func TestAntigravityDoesNotGuessLineNumbersForRepeatedReplacement(t *testing.T) {
	dir := t.TempDir()
	originalQueue := agyQueueDir
	agyQueueDir = dir
	t.Cleanup(func() { agyQueueDir = originalQueue })
	path := write(t, "a.md", "前置き新しい （行）\n続き。\n対象外\n新しい （行）\n続き\n")
	_, stderr, code := runHookAll(t, map[string]any{
		"conversationId": "conv-multiple",
		"toolCall": map[string]any{
			"name": "replace_file_content",
			"args": map[string]any{
				"TargetFile": path, "StartLine": 1, "EndLine": 3, "AllowMultiple": true,
				"TargetContent": "置換前", "ReplacementContent": "新しい （行）\n続き",
			},
		},
	})
	if code != 0 || stderr != "" {
		t.Fatalf("PostToolUse: code %d, stderr %q", code, stderr)
	}
	got, _, code := runHookAll(t, map[string]any{"conversationId": "conv-multiple", "invocationNum": 1})
	if code != 0 || !strings.Contains(got, "a.md: ") ||
		strings.Contains(got, "a.md:1:") || strings.Contains(got, "a.md:4:") {
		t.Fatalf("PreInvocation: code %d, output %s", code, got)
	}
}

func TestAntigravityInlineReplacementWithTwoMatchesOnOneLine(t *testing.T) {
	path := write(t, "a.md", "「表示」と「表示」\n")
	dir := t.TempDir()
	originalQueue := agyQueueDir
	agyQueueDir = dir
	t.Cleanup(func() { agyQueueDir = originalQueue })
	_, stderr, code := runHookAll(t, map[string]any{
		"conversationId": "conv-inline",
		"toolCall": map[string]any{
			"name": "replace_file_content",
			"args": map[string]any{
				"TargetFile": path, "StartLine": 1, "EndLine": 1,
				"TargetContent": "TODO", "ReplacementContent": "「表示」",
			},
		},
	})
	if code != 0 || stderr != "" {
		t.Fatalf("PostToolUse: code %d, stderr %q", code, stderr)
	}
	got, _, code := runHookAll(t, map[string]any{"conversationId": "conv-inline", "invocationNum": 1})
	if code != 0 || strings.Count(got, "a.md:1:") != 1 {
		t.Fatalf("PreInvocation: code %d, output %s", code, got)
	}
}

func TestAntigravityLaterChunkUsesShiftFromAmbiguousReplacement(t *testing.T) {
	path := write(t, "a.md", "「表示」\n追記\n境目\n「表示」\n追記\n変更した （行）\n")
	input, err := json.Marshal(map[string]any{
		"toolCall": map[string]any{
			"name": "multi_replace_file_content",
			"args": map[string]any{
				"TargetFile": path,
				"ReplacementChunks": []map[string]any{
					{"StartLine": 1, "EndLine": 4, "TargetContent": "TODO", "ReplacementContent": "「表示」\n追記"},
					{"StartLine": 5, "EndLine": 5, "TargetContent": "前の行", "ReplacementContent": "変更した （行）"},
				},
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	var call toolCall
	if err := json.Unmarshal(input, &call); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(reportAntigravityPostTool(call), "\n")
	if !strings.Contains(got, "a.md:6:") || strings.Contains(got, "a.md:1:") || strings.Contains(got, "a.md:4:") {
		t.Fatalf("reports: %s", got)
	}
}

func TestAntigravityInlineDeletionKeepsFollowingChunkOnSameLine(t *testing.T) {
	path := write(t, "a.md", "作業の説明\n変更した （行）\n")
	input, err := json.Marshal(map[string]any{
		"toolCall": map[string]any{
			"name": "multi_replace_file_content",
			"args": map[string]any{
				"TargetFile": path,
				"ReplacementChunks": []map[string]any{
					{"StartLine": 1, "EndLine": 1, "TargetContent": "TODO ", "ReplacementContent": ""},
					{"StartLine": 2, "EndLine": 2, "TargetContent": "前の行", "ReplacementContent": "変更した （行）"},
				},
			},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	var call toolCall
	if err := json.Unmarshal(input, &call); err != nil {
		t.Fatal(err)
	}
	got := strings.Join(reportAntigravityPostTool(call), "\n")
	if !strings.Contains(got, "a.md:2:") {
		t.Fatalf("reports: %s", got)
	}
}

func TestCodexPatchUsesContextToLocateDuplicateLine(t *testing.T) {
	path := write(t, "a.md", "新しい （行）\n\n対象の節\n新しい （行）\n最後の行\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@ 対象の節\n-前の行\n+新しい （行）\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:4:") || strings.Contains(got, "a.md:1:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchReportsEveryAppendChunk(t *testing.T) {
	path := write(t, "a.md", "最初の行\n追加した （行）\n「新しい行」\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@\n+追加した （行）\n@@\n+「新しい行」\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:2:") || !strings.Contains(got, "a.md:3:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchEndOfFileReplacementBeforeAppend(t *testing.T) {
	path := write(t, "a.md", "最初の行\n新しい （行）\n新しい （行）\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@\n-前の末尾\n+新しい （行）\n*** End of File\n@@\n+新しい （行）\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:2:") || !strings.Contains(got, "a.md:3:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchWithFinalNewlineContext(t *testing.T) {
	path := write(t, "a.md", "新しい （行）\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@\n-前の行\n+新しい （行）\n \n*** End of File\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:1:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchAcceptsEquivalentContext(t *testing.T) {
	path := write(t, "a.md", "  見出し\n  文脈\n追加した （行）\n“表示”を選ぶ\n値—1\n追加した （項目）\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@ 見出し\n 文脈\n+追加した （行）\n@@ \"表示\"を選ぶ\n 値-1\n+追加した （項目）\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:3:") || !strings.Contains(got, "a.md:6:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchIgnoresHeadingIntroducedByLaterChunk(t *testing.T) {
	path := write(t, "a.md", "  対象の節\n新しい （行）\n境目\n対象の節\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@ 対象の節\n-前の行\n+新しい （行）\n@@ 境目\n-別の見出し\n+対象の節\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md:2:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}

func TestCodexPatchWithIndistinguishableLinesOmitsLineNumber(t *testing.T) {
	path := write(t, "a.md", "新しい （行）\n\n新しい （行）\n")
	patch := "*** Begin Patch\n*** Update File: a.md\n@@\n-前の行\n+新しい （行）\n*** End Patch\n"
	got, stderr, code := runCodexPatch(t, filepath.Dir(path), patch)
	if code != 0 || stderr != "" || !strings.Contains(got, "a.md: ") ||
		strings.Contains(got, "a.md:1:") || strings.Contains(got, "a.md:3:") {
		t.Fatalf("PostToolUse: code %d, output %s, stderr %q", code, got, stderr)
	}
}
