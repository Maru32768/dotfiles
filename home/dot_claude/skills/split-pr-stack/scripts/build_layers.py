#!/usr/bin/env python3
"""Write the working tree of one split layer, derived from the final tree of the branch being split.

Copy this file to the scratchpad, fill in the CONFIG section, then:
  python3 -I build_layers.py <worktree> <layer>

Layer L's content of a file:
  below its first owner           -> BASE
  at or above its last owner      -> FINAL
  in between (shared files only)  -> TRANSFORMS[path](FINAL text), which removes the parts of higher layers
"""
import subprocess
import sys

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


def show(ref, path):
    r = subprocess.run(["git", "-C", WT, "show", f"{ref}:{path}"], capture_output=True)
    return r.stdout.decode() if r.returncode == 0 else None


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


def content_at_layer(path):
    owners = OWNERS[path]
    first, last = ORDER.index(owners[0]), ORDER.index(owners[-1])
    if L < first:
        return show(BASE, path)
    final = show(FINAL, path)
    if L >= last:
        return final
    return TRANSFORMS[path](final)


def main():
    changed = subprocess.run(
        ["git", "-C", WT, "diff", "--name-only", BASE, FINAL], capture_output=True, text=True, check=True
    ).stdout.split()
    assert sorted(changed) == sorted(OWNERS), f"OWNERS must cover exactly the changed files: {set(changed) ^ set(OWNERS)}"
    for path, owners in OWNERS.items():
        assert owners == sorted(owners, key=ORDER.index), f"{path}: owners out of ORDER order"
        if len(owners) > 1:
            assert path in TRANSFORMS, f"{path}: shared file without a transform"
        text = content_at_layer(path)
        full = f"{WT}/{path}"
        if text is None:
            subprocess.run(["rm", "-f", full], check=True)
        else:
            subprocess.run(["mkdir", "-p", full.rsplit("/", 1)[0]], check=True)
            with open(full, "w", encoding="utf-8") as f:
                f.write(text)


main()
