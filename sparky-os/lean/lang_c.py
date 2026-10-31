# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""C and C++: `//` and `/* */` comments, outside string, character and raw string literals.

Ported from CGM's _lang_c_like (its literal scan, raw strings and LineMap), with the 2026-10-09
counterexamples fixed using the edition's qualified regression fixtures:
  - `int/**/value` became `intvalue`: a removed comment with code after it is one space, as in
    translation phase 3 (C23 5.1.1.2; GCC "Initial processing");
  - a raw string lost one of its blank lines: literals are never compacted;
  - `__LINE__` changed from 4 to 3: for C and C++ every authored line keeps its number. A removed
    comment leaves the line breaks it held (phase 3 keeps new-line characters; a comment's own line
    breaks are white space to the compiler wherever no directive is open), so the compiler, `__LINE__`,
    `assert` and debug line tables see the authored line numbers with no `#line` directive, and no line
    is deleted or collapsed. Where a comment's line breaks would end a directive early, or start one (a
    `#` after a comment that began after code), an empty comment keeps them instead: `/*` and `*/`
    around the same line breaks (ORDER 303: GCC spent more on `#line` than the comments cost).
Also: a `//` comment ending in a backslash continues on the next line (phase 2 splices it); C++14
digit separators (1'000) are not character literals; a lone quote in `#error` text is not a literal.
Kept comments: notices, the pointer line, and the fall-through comments GCC's -Wimplicit-fallthrough
reads. The pointer goes on a line a removed comment emptied, so it moves no line either.
The check runs GCC's own preprocessor: with -fpreprocessed (no expansion) both texts give the same
tokens and the same directives, and every logical line starts on the same line; where the file
preprocesses on its own, full preprocessing gives the same output on the same lines, `__LINE__` values
included; and the lean text holds no line control (`#line` or a line marker) the authored text did not.
"""

from __future__ import annotations

import bisect
import os
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, held_breaks, is_notice, is_pointer, line_starts

KEY = 'c'
EXTS = frozenset({'.h', '.hh', '.hpp', '.hxx', '.c', '.cc', '.cpp', '.cxx', '.inl'})
GLSL_EXTS = frozenset({'.glsl', '.vert', '.frag', '.geom', '.comp', '.tesc', '.tese'})
MARKER = '//'
FALLTHROUGH = re.compile(r'fall(s| |-)?thr(ough|u)|\bnotreached\b|\blint\b', re.I)
RAW_PREFIX = ('R', 'u8R', 'uR', 'UR', 'LR')
RAW_OPEN = re.compile(r'"([^()\\\s]{0,16})\(')
# an #include directive's header-name between < and > is one token (C23 6.4.7): no comment starts inside it
HEADER_NAME = re.compile(r'#[ \t]*(?:include(?:_next)?|import|embed)[ \t]*<[^>\n]*>')
# an empty comment that only holds line breaks: what a removed comment leaves where its line breaks would
# otherwise end or start a directive
BREAKS_ONLY = re.compile(r'/\*[ \t]*(?:\\?\n[ \t]*)+\*/\Z')
# line control (`#line`, C17 6.10.4) and GCC's line markers: the lean text must hold none the authored text lacks
LINE_CONTROL = re.compile(r'^[ \t]*(?:#|%:)[ \t]*(?:line\b|[0-9])', re.M)
LINE_MARKER = re.compile(r'#[ \t]*([0-9]+)[ \t]+"((?:[^"\\]|\\.)*)"')
# C++20 module and import lines are directives too ([cpp.pre], [cpp.module], [cpp.import]): line breaks end them
WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
LINE_WORDS = frozenset({'import', 'module', 'export'})


def keep_empty_after(line: str) -> bool:
    k, n = len(line), 0
    while k > 0 and line[k - 1] == '\\':
        n += 1
        k -= 1
    return n % 2 == 1


def joiner(src: str, start: int, end: int) -> str:
    return ' '


def joiner_for(src: str, spans: list):
    """The joiner of the line-keeping render (core.render keep_lines) for a removed comment with code after
    it: one space when it holds no line break (translation phase 3); otherwise the line breaks it held,
    each as it was (a backslash-newline stays one, after the space when nothing else separates the tokens),
    which are white space to the compiler wherever no directive is open; where a line break would end a
    directive early or start one, an empty comment holds the same line breaks."""
    holders = break_holders(src, spans)

    def join(s, start, end):
        breaks = held_breaks(s, start, end)
        if start in holders:
            return '/*' + breaks + '*/'
        if '\n' in breaks.replace('\\\n', ''):
            return breaks
        return ' ' + breaks
    return join


def break_holders(src: str, spans: list) -> set:
    """Starts of the removable comments whose line breaks must stay inside a comment. A preprocessing
    directive is one logical line, opened by a `#` (or `%:`) that is its first token (C23 6.10; in C++20
    also `import`, `module` and `export` lines, taken as directives here whatever follows them): a line
    break ends it, a comment's line breaks do not (a backslash-newline joins lines before either). So a
    comment that holds a line break no backslash splices, lies in an open directive and has code after it
    on its last line, or follows code and is followed by a `#` (or one of those words) on its last line
    (that is no directive in the authored text), keeps its line breaks in an empty comment, which is
    always the same to the compiler as the comment it replaces."""
    out = set()
    n = len(src)
    at_span = {sp.start: sp for sp in spans}
    in_dir = False      # the logical line is a directive
    has_tok = False     # the logical line has a token before this point
    i = 0
    while i < n:
        sp = at_span.get(i)
        if sp is not None and sp.end > i:
            if sp.kind == COMMENT and '\n' in held_breaks(src, sp.start, sp.end).replace('\\\n', ''):
                if in_dir and not _blank_tail(src, sp.end):
                    out.add(sp.start)
                elif has_tok and _directive_after(src, sp.end, at_span):
                    out.add(sp.start)
            if sp.kind == LITERAL:
                has_tok = True
            i = sp.end
            continue
        c = src[i]
        if c == '\\' and src.startswith('\n', i + 1):
            i += 2              # phase 2: a backslash-newline splices two lines into one logical line
            continue
        if c == '\n':
            in_dir = has_tok = False
        elif c not in ' \t\f\v\r':
            if not has_tok and _opens_directive(src, i):
                in_dir = True
            has_tok = True
        i += 1
    return out


def _opens_directive(src: str, i: int) -> bool:
    if src[i] == '#' or src.startswith('%:', i):
        return True
    m = WORD.match(src, i)
    return bool(m) and m.group() in LINE_WORDS


def _blank_tail(src: str, end: int) -> bool:
    nl = src.find('\n', end)
    return src[end: nl if nl >= 0 else len(src)].strip(' \t\f\v') == ''


def _directive_after(src: str, end: int, at_span: dict) -> bool:
    """True when the first token after `end` on its logical line could open a directive."""
    i, n = end, len(src)
    while i < n:
        sp = at_span.get(i)
        if sp is not None and sp.kind in (COMMENT, KEEP) and sp.end > i:
            i = sp.end
            continue
        c = src[i]
        if c == '\\' and src.startswith('\n', i + 1):
            i += 2
            continue
        if c in ' \t\f\v\r':
            i += 1
            continue
        return _opens_directive(src, i)
    return False


def lex(src: str) -> list:
    s, n = src, len(src)
    spans = []
    i = 0
    while i < n:
        c = s[i]
        nx = s[i + 1] if i + 1 < n else ''
        if c == '#':
            k = i - 1
            while k >= 0 and s[k] in ' \t':
                k -= 1
            if k < 0 or s[k] == '\n':
                m = HEADER_NAME.match(s, i)
                if m:
                    i = m.end()
                    continue
        if c == '/' and nx == '/':
            j = i + 2
            while j < n:
                if s[j] == '\n':
                    # a backslash-newline continues the comment (splicing comes before comments)
                    k, bs = j - 1, 0
                    while k > i and s[k] == '\\':
                        bs += 1
                        k -= 1
                    if bs % 2 == 1:
                        j += 1
                        continue
                    break
                j += 1
            _comment(spans, s, i, j)
            i = j
            continue
        if c == '/' and nx == '*':
            j = s.find('*/', i + 2)
            j = n if j < 0 else j + 2
            _comment(spans, s, i, j)
            i = j
            continue
        if c.isalpha() or c == '_':
            j = i
            while j < n and (s[j].isalnum() or s[j] == '_'):
                j += 1
            word = s[i:j]
            if j < n and s[j] == '"' and word in RAW_PREFIX:
                m = RAW_OPEN.match(s, j)
                if m:
                    end = s.find(')' + m.group(1) + '"', m.end())
                    if end >= 0:
                        end += len(m.group(1)) + 2
                        spans.append(Span(i, end, LITERAL, 'raw string literal'))
                        i = end
                        continue
            i = j
            continue
        if c.isdigit() or (c == '.' and nx.isdigit()):
            # a preprocessing number (C23 6.4.8): digits, letters, '.', signs after e/p, and C++14 digit separators
            j = i + 1
            while j < n:
                d = s[j]
                if d.isalnum() or d in '._':
                    j += 1
                elif d in '+-' and s[j - 1] in 'eEpP':
                    j += 1
                elif d == "'" and j + 1 < n and (s[j + 1].isalnum() or s[j + 1] == '_'):
                    j += 1
                else:
                    break
            i = j
            continue
        if c in '"\'':
            j = i + 1
            closed = False
            while j < n and s[j] != '\n':
                if s[j] == '\\':
                    j += 2
                    continue
                if s[j] == c:
                    closed = True
                    break
                j += 1
            i = j + 1 if closed else i + 1   # a lone quote (as in #error text) is just a character
            continue
        i += 1
    return spans


def _comment(spans, s, i, j):
    text = s[i:j]
    if is_pointer(text):
        spans.append(Span(i, j, KEEP, 'pointer line'))
    elif BREAKS_ONLY.match(text):
        spans.append(Span(i, j, KEEP, 'an empty comment holding line breaks a directive needs'))
    elif FALLTHROUGH.search(text) and len(text) < 80:
        spans.append(Span(i, j, KEEP, 'read by the compiler (-Wimplicit-fallthrough) or lint'))
    elif is_notice(text):
        spans.append(Span(i, j, KEEP, 'licence or copyright notice'))
    else:
        spans.append(Span(i, j, COMMENT))


def refuse(src: str):
    if src.startswith('\ufeff'):
        return 'UTF-8 byte-order mark requires qualified pointer placement'
    if '\0' in src:
        return 'carries binary data'
    if '??/' in src:
        return 'uses trigraphs'
    if re.search(r'^[ \t]*#[ \t]*(?:cmakedefine(?:01)?|mesondefine)\b', src, re.M):
        return 'build-system template requires generation before C qualification'
    if re.search(r'^[ \t]*#!', src, re.M):
        # Some sources retain a generator in a disabled #if branch. Its shell
        # quoting/comment rules are not C rules; preserve the entire mixed file.
        return 'contains an embedded interpreter script'
    for span in lex(src):
        if span.kind not in (COMMENT, KEEP):
            continue
        text = src[span.start:span.end]
        if ((text.startswith(('/**', '/*!')) and len(text) > 4)
                or text.startswith(('///', '//!', '//:', '//=', '//~', '/*<'))):
            # These comments feed documentation, bindings or translations.
            # Even retaining the comment while emptying lines between it and
            # its declaration can break a textual consumer. Leave the entire
            # file unchanged until that consumer has a qualified adapter.
            return 'structured documentation or annotations require consumer qualification'
    return None


def pointer_line(src: str, spans: list, text: str) -> int | None:
    """MR line (0-based) for the pointer: the first line a removed comment emptied, so the pointer moves
    no line. It must be empty in the MR, held only removed comment text in the authored file, and be
    neither a continuation of the line before (a backslash-newline would splice the pointer into it) nor
    inside a comment the MR keeps. None when there is no such line: the pointer then takes a new last line,
    after every authored line, which also moves none."""
    starts = line_starts(src)
    count = len(starts)
    code = [False] * count
    removed = [False] * count

    def line_of(off):
        return bisect.bisect_right(starts, off) - 1

    i = 0
    for sp in spans:
        if sp.kind != COMMENT:
            continue
        for li in range(line_of(sp.start), line_of(max(sp.start, sp.end - 1)) + 1):
            removed[li] = True
        for off in range(i, sp.start):
            if src[off] not in ' \t\f\v\r\n':
                code[line_of(off)] = True
        i = sp.end
    for off in range(i, len(src)):
        if src[off] not in ' \t\f\v\r\n':
            code[line_of(off)] = True
    mr = text.split('\n')
    mr_starts = line_starts(text)
    inside = set()
    for sp in lex(text):
        if '\n' in text[sp.start:sp.end]:
            inside.update(range(bisect.bisect_right(mr_starts, sp.start) - 1,
                                bisect.bisect_right(mr_starts, sp.end - 1)))
    for li in range(min(count, len(mr))):
        if (removed[li] and not code[li] and mr[li].strip(' \t\f\v') == '' and li not in inside
                and not (li > 0 and mr[li - 1].endswith('\\'))):
            return li
    return None


def place_pointer(text: str, origin: list, src: str, spans: list, pointer: str):
    """The pointer on the line pointer_line() picks, or on a new last line; returns new (text, origin). The
    pointer's characters have no authored origin; the line keeps its own line break and its number."""
    li = pointer_line(src, spans, text)
    if li is None:
        if text and not text.endswith('\n'):
            text, origin = text + '\n', origin + [-1]
        add = pointer + '\n'
        return text + add, origin + [-1] * len(add)
    p = 0
    for _ in range(li):
        p = text.index('\n', p) + 1
    e = text.find('\n', p)
    e = len(text) if e < 0 else e
    return text[:p] + pointer + text[e:], origin[:p] + [-1] * len(pointer) + origin[e:]


def _cpp(args, text, lang):
    gcc = shutil.which('gcc') or shutil.which('cc')
    if not gcc:
        return None
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'f.' + ('cc' if lang == 'c++' else 'c'))
        with open(p, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(text)
        # Both sides must have the same logical filename and clock. Otherwise
        # __FILE__ (including uses hidden in system-header macros), __BASE_FILE__
        # and time macros produce differences caused only by our test fixtures.
        os.utime(p, (0, 0))
        env = dict(os.environ, SOURCE_DATE_EPOCH='0')
        r = subprocess.run([gcc, '-E', '-x', lang, *args, os.path.basename(p)],
                           cwd=d, env=env, capture_output=True, timeout=120)
        if r.returncode != 0:
            return None
        return r.stdout.decode('utf-8', 'surrogateescape')


def _units(pp: str) -> list:
    out = []
    for line in pp.split('\n'):
        t = line.strip()
        if not t or re.match(r'#\s*line\b', t) or re.match(r'#\s+\d+\s', t):
            continue
        if t.startswith('#'):
            out.append(' '.join(t.split()))
        else:
            out.extend(t.split())
    return out


def _located(pp: str) -> list:
    """(file, line, unit) for every unit of GCC's -E output, the line counted from its line markers and
    line breaks. Equal lists mean every token stands on the same line of the same file, so `__LINE__`,
    diagnostics and debug line tables see the same numbers."""
    out = []
    name, line = '', 1
    for raw in pp.split('\n'):
        t = raw.strip()
        m = LINE_MARKER.match(t) if t.startswith('#') else None
        if m:
            name, line = m.group(2), int(m.group(1))
            continue
        if t.startswith('#'):
            out.append((name, line, ' '.join(t.split())))
        else:
            out.extend((name, line, u) for u in t.split())
        line += 1
    return out


def _splice(text: str) -> str:
    """Translation phase 2 (C23 5.1.1.2): a backslash-newline joins two lines. GCC's -fpreprocessed
    mode skips it, so the check does it first, the same way for both texts."""
    return text.replace('\\\n', '')


def _splice_keeping_lines(text: str) -> str:
    """Translation phase 2 for the line check: each backslash-newline joins its two lines, and the line
    breaks it took go after the logical line, so every logical line starts on its own physical line in
    both texts (GCC's -fpreprocessed mode does no splicing of its own)."""
    lines = text.split('\n')
    out, joined, extra = [], [], 0
    for k, line in enumerate(lines):
        if line.endswith('\\') and k < len(lines) - 1:
            joined.append(line[:-1])
            extra += 1
            continue
        joined.append(line)
        out.append(''.join(joined))
        out.extend([''] * extra)
        joined, extra = [], 0
    return '\n'.join(out)


def _line_controls(text: str) -> int:
    """How many line-control directives (`#line N`, `# N "file"`) the text's code holds, with comments and
    literals blanked and lines spliced."""
    buf = list(text)
    for sp in lex(text):
        for k in range(sp.start, sp.end):
            if buf[k] != '\n':
                buf[k] = ' '
    return len(LINE_CONTROL.findall(_splice(''.join(buf))))


def verify(original: str, lean: str, interpreter: str = 'c') -> tuple:
    lang = 'c++' if interpreter == 'c++' else 'c'
    a = _cpp(['-fpreprocessed', '-dD', '-P'], _splice(original), lang)
    b = _cpp(['-fpreprocessed', '-dD', '-P'], _splice(lean), lang)
    if a is None:
        return False, 'GCC could not read the authored file'
    if b is None:
        return False, 'GCC could not read the lean file'
    if _units(a) != _units(b):
        return False, 'GCC sees different tokens or directives'
    la = _cpp(['-fpreprocessed', '-dD'], _splice_keeping_lines(original), lang)
    lb = _cpp(['-fpreprocessed', '-dD'], _splice_keeping_lines(lean), lang)
    if la is None or lb is None or _located(la) != _located(lb):
        return False, 'GCC sees a logical line start on another line'
    if _line_controls(lean) != _line_controls(original):
        return False, 'the lean text holds line control (#line) the authored text does not'
    fa = _cpp(['-w'], original, lang)
    if fa is not None:
        fb = _cpp(['-w'], lean, lang)
        if fb is None or _located(fa) != _located(fb):
            return False, 'full preprocessing differs (its tokens, or the lines they stand on)'
        return True, 'GCC: same tokens, directives and lines, and the same full preprocessing on the same lines'
    return True, 'GCC: same tokens, directives and lines (the file does not preprocess on its own)'
