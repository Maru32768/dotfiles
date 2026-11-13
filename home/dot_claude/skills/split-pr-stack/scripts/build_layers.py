#!/usr/bin/env python3
"""Write the working tree of one split layer, derived from the final tree of the branch being split.

Copy this file to the scratchpad, fill in the CONFIG section, then:
  python3 -I build_layers.py <worktree> <layer>

Layer L's content of a file:
  below its first owner           -> BASE
  at or above its last owner      -> FINAL
  in between (shared files only)  -> TRANSFORMS[path](FINAL text), which removes the parts of higher layers

The file is taken from BASE or FINAL with git restore, so its mode, symlink, and binary content carry
over as they are. A shared file must be text.
"""
import subprocess
import sys
from collections import Counter

# ---- CONFIG -----------------------------------------------------------------------------------
FINAL = "<sha of the branch being split>"
BASE = "<sha the stack is rooted on>"
ORDER = ["A1", "A2", "B1"]
OWNERS = {
    # path -> owning layers in ORDER order; the first one introduces the change, the last one completes it
    "path/to/only_in_a1.kt": ["A1"],
    "path/to/shared.kt": ["A2", "B1"],
}
# -----------------------------------------------------------------------------------------------

WT = sys.argv[1]
L = ORDER.index(sys.argv[2])


def git(*args, paths=None):
    """Run git in WT; `paths` are passed as literal pathspecs on stdin, so any number of any names fit."""
    if paths is not None:
        args = (*args, "--pathspec-from-file=-", "--pathspec-file-nul")
    stdin = "\0".join(paths).encode("utf-8") if paths is not None else None
    return subprocess.run(["git", "-C", WT, "--literal-pathspecs", *args], input=stdin, stdout=subprocess.PIPE, check=True).stdout


def split_nul(out):
    return [p for p in out.decode("utf-8").split("\0") if p]


def below(name):
    """True when the layer being written comes before `name`, so `name`'s content must be absent."""
    return L < ORDER.index(name)


def cut(text, snippet):
    assert text.count(snippet) == 1, f"expected exactly one occurrence of: {snippet[:80]!r}"
    return text.replace(snippet, "", 1)


def replace_once(text, old, new):
    assert text.count(old) == 1, f"expected exactly one occurrence of: {old[:80]!r}"
    return text.replace(old, new, 1)


def cut_lines(text, start, end=None, blank=True):
    """Remove from the line starting with `start` to the first following line equal to `end`, inclusive.

    A preceding `@Test` line goes with the block. With `blank`, one separating blank line goes too
    (the preceding one, else the following one), so the surrounding spacing stays as in FINAL.
    """
    lines = text.split("\n")
    hits = [i for i, ln in enumerate(lines) if ln.startswith(start)]
    assert len(hits) == 1, f"expected exactly one line starting with {start!r}, got {len(hits)}"
    s = e = hits[0]
    if end is not None:
        e = next(i for i in range(s, len(lines)) if lines[i] == end)
    if s > 0 and lines[s - 1].strip() == "@Test":
        s -= 1
    if blank:
        if s > 0 and lines[s - 1] == "":
            s -= 1
        elif e + 1 < len(lines) and lines[e + 1] == "":
            e += 1
    return "\n".join(lines[:s] + lines[e + 1:])


def cut_test(text, name, indent="    "):
    return cut_lines(text, f"{indent}fun `{name}`", f"{indent}}}")


def cut_para(text, prefix):
    """Remove a one-line Markdown paragraph and the blank line that follows it."""
    lines = text.split("\n")
    hits = [i for i, ln in enumerate(lines) if ln.startswith(prefix)]
    assert len(hits) == 1, f"paragraph {prefix!r}: {len(hits)} hits"
    i = hits[0]
    assert lines[i + 1] == "", f"paragraph {prefix!r} is not followed by a blank line"
    return "\n".join(lines[:i] + lines[i + 2:])


# ---- TRANSFORMS (CONFIG, continued) ----------------------------------------------------------
# Every shared path (more than one owner) needs one: FINAL text -> text at layer L, removing what
# the layers above L add. Use below(), cut(), cut_lines(), cut_test(), cut_para(), replace_once().


def t_shared(t):
    if below("B1"):
        t = cut(t, "import example.OnlyUsedByB1\n")
    return t


TRANSFORMS = {
    "path/to/shared.kt": t_shared,
}
# -----------------------------------------------------------------------------------------------


def main():
    changed = split_nul(git("diff-tree", "-r", "-z", "--name-only", "--no-renames", BASE, FINAL))
    assert sorted(changed) == sorted(OWNERS), f"OWNERS must cover exactly the changed files: {set(changed) ^ set(OWNERS)}"
    for path, owners in OWNERS.items():
        assert owners == sorted(owners, key=ORDER.index), f"{path}: owners out of ORDER order"
        if len(owners) > 1:
            assert path in TRANSFORMS, f"{path}: shared file without a transform"
    source = {path: BASE if L < ORDER.index(owners[0]) else FINAL for path, owners in OWNERS.items()}
    files = {ref: set(split_nul(git("ls-tree", "-r", "-z", "--name-only", "--full-tree", ref))) for ref in (BASE, FINAL)}
    kept = {path: ref for path, ref in source.items() if path in files[ref]}
    icase = git("config", "--type=bool", "--default=false", "core.ignorecase").strip() == b"true"

    def simple_upper(c):
        """One character for one, as NTFS maps case: straße.txt and strasse.txt are two files there, ᾀ and ᾈ one."""
        return next((u for u in (c.upper(), c.title()) if len(u) == 1), c)

    def fold(path):
        return "".join(map(simple_upper, path)) if icase else path

    places = Counter(fold(path) for path in kept)
    dirs = {place[:i] for place in places for i, c in enumerate(place) if c == "/"}
    clash = sorted((dirs & places.keys()) | {place for place, n in places.items() if n > 1})
    assert not clash, f"OWNERS puts two entries at the same place on disk in {ORDER[L]}: {clash}"
    between = [path for path, owners in OWNERS.items() if ORDER.index(owners[0]) <= L < ORDER.index(owners[-1])]
    texts = {path: TRANSFORMS[path](git("show", f"{FINAL}:{path}").decode("utf-8")) for path in between}
    # Remove first, then restore: when a file becomes a directory, or a rename changes only the case, both
    # paths share one place on disk, and removing one after restoring the other would undo the restore.
    gone = [path for path in source if path not in kept]
    if gone:
        git("rm", "-r", "-q", "-f", "--ignore-unmatch", paths=gone)
    for ref in (BASE, FINAL):
        paths = [path for path, r in kept.items() if r == ref]
        if paths:
            git("restore", f"--source={ref}", "--staged", "--worktree", paths=paths)
    for path, text in texts.items():
        with open(f"{WT}/{path}", "w", encoding="utf-8", newline="") as f:
            f.write(text)
    if texts:
        git("add", paths=list(texts))


main()
