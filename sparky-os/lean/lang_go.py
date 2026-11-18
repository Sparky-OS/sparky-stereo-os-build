# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Go: `//` line comments and `/* */` general comments, outside interpreted strings, raw strings and rune literals.

The Go specification, "Comments": "A general comment containing no newlines acts like a space. Any other
comment acts like a newline." So a general comment without a newline becomes one space, and one with newlines
keeps its newlines, so the automatic semicolons ("Semicolons": inserted after a line's final token) land where
they did. A comment-only line becomes an empty line: no line goes, so every position stays and `go build`
gives the same program (ORDER 108 milestone 9: the authored and the projected OpenLinkHub have byte-identical
.text, .rodata and .gopclntab).

Gone from the build input, the HR text keeps them: doc comments (the compiler never reads them; `go doc`, godoc
and gopls are not part of a build), `//` and `/* */` of every other kind.
Kept, because the toolchain reads them:
- directives: `//go:build`, `//go:generate`, `//go:embed`, `//go:linkname`, `//go:noinline` and the other `//go:`
  pragmas, `//export NAME` (cgo), `// +build`, `//line` and `/*line */`;
- the cgo preamble: the comment group directly before `import "C"` is C source for the C compiler;
- `// Code generated ... DO NOT EDIT.` (tools read the marker), licence, copyright and SPDX lines.
Data, never edited: interpreted strings, raw strings, rune literals (struct tags are strings).
Left as authored, with the reason: a test file (`go test` compares the `// Output:` comment of an Example), a
`testdata` file, a file with a `//go:generate` line (a generator may read source text), a file with a byte-order
mark, a file `go/parser` does not accept.
The check is the consumer's: go/scanner's own token stream, the automatic semicolons included, must be equal
for both texts (a helper built once with the installed go), and go/parser must accept the lean text.
"""

from __future__ import annotations

import atexit
import hashlib
import os
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, is_notice, is_pointer

KEY = 'go'
EXTS = frozenset({'.go'})
MARKER = ''                                      # no pointer line: positions stay
DROP_LINES = False
NEXT = re.compile(r'//|/\*|"|`|\'')
DIRECTIVE = re.compile(r'//go:|//export\s|// \+build|//line\s|/\*line\s')
GENERATED = re.compile(r'//\s*Code generated .* DO NOT EDIT\.')
PREAMBLE = re.compile(r'[ \t\r\n]*import[ \t]*"C"')
HELPER = r'''package main

import (
	"fmt"
	"go/parser"
	"go/scanner"
	"go/token"
	"os"
	"bufio"
	"strings"
)

func main() {
	list, _ := os.ReadFile(os.Args[1])
	out, _ := os.Create(os.Args[1] + ".out")
	w := bufio.NewWriter(out)
	for _, name := range strings.Split(strings.TrimSpace(string(list)), "\n") {
		src, err := os.ReadFile(name)
		fmt.Fprintf(w, "== %s\n", name)
		if err != nil {
			fmt.Fprintln(w, "invalid")
			continue
		}
		var s scanner.Scanner
		bad := 0
		fset := token.NewFileSet()
		s.Init(fset.AddFile("", fset.Base(), len(src)), src, func(token.Position, string) { bad++ }, 0)
		var lines []string
		for {
			_, tok, lit := s.Scan()
			if tok == token.EOF {
				break
			}
			lines = append(lines, tok.String()+"\t"+strings.ReplaceAll(lit, "\n", "\\n"))
		}
		if _, err := parser.ParseFile(token.NewFileSet(), name, src, parser.SkipObjectResolution); err != nil || bad > 0 {
			fmt.Fprintln(w, "invalid")
			continue
		}
		for _, l := range lines {
			fmt.Fprintln(w, l)
		}
	}
	fmt.Fprintln(w, "== end")
	w.Flush()
	out.Close()
}
'''

INVALID = 'invalid'
_built = None
_temporary = None
_digests = {}


def keep_empty_after(line: str) -> bool:
    return True                                  # an emptied line stays an empty line


keep_empty_after.keep_all = True


def joiner(src: str, start: int, end: int) -> str:
    return ' '                                   # a general comment without a newline acts like a space


def _classify(raw: str, a: int, b: int) -> Span:
    if DIRECTIVE.match(raw):
        return Span(a, b, KEEP, 'directive: the compiler, cgo or go generate reads it')
    if GENERATED.match(raw):
        return Span(a, b, KEEP, 'generated-code marker: tools read it')
    if is_pointer(raw):
        return Span(a, b, KEEP, 'pointer line')
    if is_notice(raw):
        return Span(a, b, KEEP, 'licence or copyright notice')
    return Span(a, b, COMMENT)


def _segments(src: str, span: Span) -> list:
    """A removable general comment that spans lines becomes one span for each of its lines: the newlines
    between them stay in the text, so the comment's line breaks (it acts like a newline) and every position stay."""
    if span.kind != COMMENT or '\n' not in src[span.start:span.end]:
        return [span]
    out, at = [], span.start
    while True:
        nl = src.find('\n', at, span.end)
        if nl < 0:
            out.append(Span(at, span.end, COMMENT))
            return out
        if nl > at:
            out.append(Span(at, nl, COMMENT))
        at = nl + 1


def lex(src: str) -> list:
    """Spans of comments (COMMENT or KEEP) and literals, in order."""
    spans = []
    i, n = 0, len(src)
    while True:
        m = NEXT.search(src, i)
        if not m:
            break
        i = m.start()
        what = m.group(0)
        if what == '//':
            end = src.find('\n', i)
            end = n if end < 0 else end
            spans.append(_classify(src[i:end], i, end))
            i = end
        elif what == '/*':
            j = src.find('*/', i + 2)
            if j < 0:
                raise ValueError('unterminated general comment')
            spans.append(_classify(src[i:j + 2], i, j + 2))
            i = j + 2
        elif what == '"':
            j = i + 1
            while True:
                if j >= n or src[j] == '\n':
                    raise ValueError('unterminated string literal')
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == '"':
                    break
                j += 1
            spans.append(Span(i, j + 1, LITERAL, 'string literal'))
            i = j + 1
        elif what == '`':
            j = src.find('`', i + 1)
            if j < 0:
                raise ValueError('unterminated raw string literal')
            spans.append(Span(i, j + 1, LITERAL, 'raw string literal'))
            i = j + 1
        else:                                    # a rune literal
            j = i + 1
            while True:
                if j >= n or src[j] == '\n':
                    raise ValueError('unterminated rune literal')
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == "'":
                    break
                j += 1
            spans.append(Span(i, j + 1, LITERAL, 'rune literal'))
            i = j + 1
    # the cgo preamble: the comment group directly before `import "C"`
    for k in range(len(spans) - 1, -1, -1):
        sp = spans[k]
        if sp.kind not in (COMMENT, KEEP) or not PREAMBLE.match(src, sp.end):
            continue
        if src.count('\n', sp.end, PREAMBLE.match(src, sp.end).end()) > 1:
            continue                              # a blank line between: not the preamble
        j = k
        spans[j] = Span(sp.start, sp.end, KEEP, 'cgo preamble: C source for the C compiler')
        while j > 0:
            prev = spans[j - 1]
            gap = src[prev.end:spans[j].start]
            if prev.kind in (COMMENT, KEEP) and gap.strip() == '' and gap.count('\n') <= 1:
                spans[j - 1] = Span(prev.start, prev.end, KEEP, 'cgo preamble: C source for the C compiler')
                j -= 1
            else:
                break
    out = []
    for sp in spans:
        out.extend(_segments(src, sp))
    return out


def code_text(src: str, literals=True) -> str:
    out = list(src)
    for sp in lex(src):
        if sp.kind == LITERAL and not literals:
            continue
        for k in range(sp.start, sp.end):
            if out[k] != '\n':
                out[k] = ' '
    return ''.join(out)


def refuse(src: str) -> str | None:
    if '\0' in src:
        return 'carries binary data'
    if src.startswith('﻿'):
        return 'a byte-order mark: no qualified adapter'
    try:
        spans = lex(src)
    except ValueError:
        return None                               # the authored check names it
    if any(sp.kind == KEEP and src.startswith('//go:generate', sp.start) for sp in spans):
        return 'a //go:generate line: a generator may read this file as text'
    return None


def go() -> str | None:
    return os.environ.get('LEAN_GO') or shutil.which('go')


def _close():
    if _temporary is not None:
        _temporary.cleanup()


atexit.register(_close)


def _helper():
    """The token helper, built once per process with the installed go: go/scanner's token stream (the automatic
    semicolons included) of each listed file, and go/parser's verdict."""
    global _built, _temporary
    if _built is not None:
        return _built
    _temporary = tempfile.TemporaryDirectory(prefix='lean-go-')
    d = _temporary.name
    with open(os.path.join(d, 'main.go'), 'w', encoding='utf-8') as f:
        f.write(HELPER)
    with open(os.path.join(d, 'go.mod'), 'w', encoding='utf-8') as f:
        f.write('module leantokens\n\ngo 1.21\n')
    r = subprocess.run([go(), 'build', '-buildvcs=false', '-o', os.path.join(d, 'tokens'), '.'], capture_output=True, timeout=600, cwd=d, env=_env(d))
    if r.returncode != 0:
        raise OSError('go could not build the token helper: ' + r.stderr.decode('utf-8', 'replace').strip().split('\n')[-1])
    _built = d
    return d


def _env(d):
    return dict(os.environ, GOFLAGS='', GOPROXY='off', GOTOOLCHAIN='local', GO111MODULE='on', GOCACHE=os.path.join(d, 'cache'),
                GOPATH=os.path.join(d, 'path'), CGO_ENABLED='0', HOME=d)


def token_streams(*texts):
    """Each text's token stream as go/scanner reads it, or ['invalid'] when the scanner or the parser refuses it."""
    d = _helper()
    with tempfile.TemporaryDirectory(prefix='lean-go-in-') as work:
        names = []
        for k, text in enumerate(texts):
            p = os.path.join(work, f'f{k}.go')
            with open(p, 'w', encoding='utf-8', newline='') as f:
                f.write(text)
            names.append(p)
        listing = os.path.join(work, 'list')
        with open(listing, 'w', encoding='utf-8') as f:
            f.write(''.join(name + '\n' for name in names))
        r = subprocess.run([os.path.join(d, 'tokens'), listing], capture_output=True, timeout=600, cwd=work)
        if r.returncode != 0 or not os.path.exists(listing + '.out'):
            raise OSError('the token helper failed: ' + r.stderr.decode('utf-8', 'replace').strip()[-300:])
        with open(listing + '.out', encoding='utf-8') as f:
            out = f.read()
    blocks = re.split(r'(?m)^== ', out)[1:]
    if not blocks or blocks[-1] != 'end\n':
        raise OSError('the token helper printed an incomplete answer')
    streams = [block.split('\n')[1:-1] for block in blocks[:-1]]
    if len(streams) != len(texts):
        raise OSError('the token helper printed an incomplete answer')
    return streams


def _key(text: str) -> str:
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def prime(texts, batch=400):
    todo = {}
    for text in texts:
        todo.setdefault(_key(text), text)
    todo = [(k, t) for k, t in todo.items() if k not in _digests]
    for at in range(0, len(todo), batch):
        part = todo[at:at + batch]
        for (k, _), stream in zip(part, token_streams(*(t for _, t in part))):
            _digests[k] = INVALID if stream == ['invalid'] else hashlib.sha256('\n'.join(stream).encode('utf-8')).hexdigest()


def token_digest(text: str) -> str:
    k = _key(text)
    if k not in _digests:
        prime([text])
    return _digests[k]


def authored_refusal(text: str) -> str | None:
    """An authored file go/scanner and go/parser do not accept is retained: the consumer check needs them."""
    if not go():
        return 'go unavailable; authored file retained'
    try:
        digest = token_digest(text)
    except (OSError, subprocess.SubprocessError) as e:
        return f'go could not read the authored file: {e}'
    if digest == INVALID:
        return "authored file holds text go/scanner or go/parser does not accept; consumer qualification unavailable"
    return None


def verify(original: str, lean: str) -> tuple:
    try:
        prime([original, lean])
        a, b = token_digest(original), token_digest(lean)
        if INVALID in (a, b):
            return False, "go/scanner or go/parser refuses the " + ('authored' if a == INVALID else 'lean') + ' text'
        if a != b:
            x, y = token_streams(original, lean)
            k = next((k for k, (p, q) in enumerate(zip(x, y)) if p != q), min(len(x), len(y)))
            return False, f"go/scanner reads different tokens (token {k + 1})"
        if original.count('\n') != lean.count('\n'):
            return False, 'the number of lines changed'
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    return True, "go/scanner: the same tokens, semicolons included; go/parser accepts it; every line stays"
