package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

var badLines = map[string]string{
	"ＡＩを使う":                         fullwidthAlnum,
	"最大１００件":                        fullwidthAlnum,
	"更新間隔（分）":                       fullwidthParen,
	"「保存」を押す":                       kagi,
	"設計・開発":                         nakaguro,
	"AI を使う":                        spacing,
	"最大 100件":                       spacing,
	"Google Cloud の API":            spacing,
	"`chezmoi` で反映する":               spacing,
	"更新間隔 (分)":                      parenSpace,
	"更新間隔(分) を見る":                   parenSpace,
	"更新間隔( 分)":                      parenSpace,
	"更新間隔(分 )":                      parenSpace,
	"｢保存｣ を押す":                      markSpace,
	"これは ｢保存｣":                      markSpace,
	"設計 ･ 開発":                       markSpace,
	"// 「保存」を押す":                    kagi,
	"詳しくは https://example.com/ を見る": spacing,
	"[リンク](https://example.com)を見て、ＡＩを使う": fullwidthAlnum,
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

func runHook(t *testing.T, input map[string]any) (string, int) {
	t.Helper()
	data, _ := json.Marshal(input)
	var stderr bytes.Buffer
	code := run(bytes.NewReader(data), &stderr)
	return stderr.String(), code
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
