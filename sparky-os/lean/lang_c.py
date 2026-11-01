# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""C and C++: `//` and `/* */` comments, outside string, character and raw string literals.

Ported from CGM's _lang_c_like (its literal scan and raw strings), with the 2026-10-09 counterexamples fixed
using the edition's qualified regression fixtures:
  - `int/**/value` became `intvalue`: a removed comment with code after it is one space, as in
    translation phase 3 (C23 5.1.1.2; GCC "Initial processing");
  - a raw string lost one of its blank lines: literals are never compacted.
From engine 0.1.20 a comment-only line goes completely, as in every other language, and the authored empty
lines stay as they are: the lean line numbers differ from the authored ones, with no `#line` and no empty
line where a comment was, and dpkg-stereo --resolve finds a lean location's authored line by its content
(Daniel, 2026-11-01: "simple - pick the line content and search it on the source"). Engines 0.1.17 to 0.1.19
kept every authored line (a removed comment left its line breaks), and engines up to 0.1.15 wrote `#line`
after every removed run; GCC paid for both (ORDER 303, ORDER 334). A comment with code before and after it
that holds line breaks becomes one line break, so the two pieces of code keep lines of their own, except
where a line break would end a directive early or start one (a `#` after a comment that began after code):
there it is one space, which is what the comment is to the compiler. A continuation stays one: an emptied
line that ended a backslash continuation takes that backslash with it.
Also: a `//` comment ending in a backslash continues on the next line (phase 2 splices it); C++14
digit separators (1'000) are not character literals; a lone quote in `#error` text is not a literal.
Kept comments: notices, the pointer line, and the fall-through comments GCC's -Wimplicit-fallthrough
reads. The pointer goes on a new first line, as in the other languages.
The check runs GCC's own preprocessor: with -fpreprocessed (no expansion) both texts give the same
tokens and the same directives; where the file preprocesses on its own, full preprocessing gives the same
tokens with `__LINE__` pinned to one value (a file whose own code expands `__LINE__` is named in the check,
since there its values follow the lean lines); and the lean text holds no line control (`#line` or a line
marker) the authored text did not.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, held_breaks, is_notice, is_pointer

KEY = 'c'
EXTS = frozenset({'.h', '.hh', '.hpp', '.hxx', '.c', '.cc', '.cpp', '.cxx', '.inl'})
GLSL_EXTS = frozenset({'.glsl', '.vert', '.frag', '.geom', '.comp', '.tesc', '.tese'})
MARKER = '//'
FALLTHROUGH = re.compile(r'fall(s| |-)?thr(ough|u)|\bnotreached\b|\blint\b', re.I)
RAW_PREFIX = ('R', 'u8R', 'uR', 'UR', 'LR')
RAW_OPEN = re.compile(r'"([^()\\\s]{0,16})\(')
# an #include directive's header-name between < and > is one token (C23 6.4.7): no comment starts inside it
HEADER_NAME = re.compile(r'#[ \t]*(?:include(?:_next)?|import|embed)[ \t]*<[^>\n]*>')
# line control (`#line`, C17 6.10.4) and GCC's line markers: the lean text must hold none the authored text lacks
LINE_CONTROL = re.compile(r'^[ \t]*(?:#|%:)[ \t]*(?:line\b|[0-9])', re.M)
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
    """The joiner for a removed comment with code after it on its line (core.render drop_lines): one space
    when it holds no line break a backslash does not splice (translation phase 3), or when its line breaks
    lie in an open directive or would start one (break_holders); otherwise one line break, so the code
    before it and the code after it keep lines of their own (the renderer makes it one space where nothing
    precedes the comment on its line)."""
    holders = break_holders(src, spans)

    def join(s, start, end):
        if start in holders or '\n' not in held_breaks(s, start, end).replace('\\\n', ''):
            return ' '
        return '\n'
    return join


def break_holders(src: str, spans: list) -> set:
    """Starts of the removable comments whose line breaks must not become a line break. A preprocessing
    directive is one logical line, opened by a `#` (or `%:`) that is its first token (C23 6.10; in C++20
    also `import`, `module` and `export` lines, taken as directives here whatever follows them): a line
    break ends it, a comment's line breaks do not (a backslash-newline joins lines before either). So a
    comment that holds a line break no backslash splices, lies in an open directive and has code after it
    on its last line, or follows code and is followed by a `#` (or one of those words) on its last line
    (that is no directive in the authored text), becomes one space, which is what it is to the compiler."""
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


def _tokens(pp: str) -> list:
    """The tokens of full preprocessing output (GCC -E), line markers aside. Its line layout follows the
    source lines (a `#` that follows a removed multi-line comment may start an output line in one text and
    not in the other), so only the token sequence is compared; the directive structure is the -fpreprocessed
    comparison's (_units)."""
    out = []
    for line in pp.split('\n'):
        t = line.strip()
        if re.match(r'#\s*line\b', t) or re.match(r'#\s+\d+(\s|$)', t):
            continue
        out.extend(t.split())
    return out


def _splice(text: str) -> str:
    """Translation phase 2 (C23 5.1.1.2): a backslash-newline joins two lines. GCC's -fpreprocessed
    mode skips it, so the check does it first, the same way for both texts."""
    return text.replace('\\\n', '')


def _line_controls(text: str) -> int:
    """How many line-control directives (`#line N`, `# N "file"`) the text's code holds, with comments and
    literals blanked and lines spliced."""
    buf = list(text)
    for sp in lex(text):
        for k in range(sp.start, sp.end):
            if buf[k] != '\n':
                buf[k] = ' '
    return len(LINE_CONTROL.findall(_splice(''.join(buf))))


# `__LINE__` pinned to one value for the full-preprocessing comparison: the lean lines differ from the authored
# ones on purpose, and every other token must stay the same
PIN_LINE = ('-U__LINE__', '-D__LINE__=0')
# the compiler's own line builtins (std::source_location reads them): no preprocessor can pin them
LINE_BUILTIN = re.compile(r'\b__builtin_(?:LINE|source_location)\b')


def line_uses(text: str, lang: str, pinned: str | None | bool = False) -> list:
    """What makes this file's own code carry line numbers: `__LINE__` expanded by its full preprocessing
    (the pinned and the free output differ; nothing to say where the file does not preprocess on its own),
    and the compiler's line builtins in its code."""
    out = []
    if pinned is False:          # not run yet (None: run, and the file does not preprocess on its own)
        pinned = _cpp(['-w', *PIN_LINE], text, lang)
    free = _cpp(['-w'], text, lang) if pinned is not None else None
    if free is not None and _tokens(free) != _tokens(pinned):
        out.append('__LINE__')
    buf = list(text)
    for sp in lex(text):
        for k in range(sp.start, sp.end):
            if buf[k] != '\n':
                buf[k] = ' '
    if LINE_BUILTIN.search(''.join(buf)):
        out.append('__builtin_LINE')
    return out


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
    if _line_controls(lean) != _line_controls(original):
        return False, 'the lean text holds line control (#line) the authored text does not'
    fa = _cpp(['-w', *PIN_LINE], original, lang)
    if fa is not None:
        fb = _cpp(['-w', *PIN_LINE], lean, lang)
        if fb is None or _tokens(fa) != _tokens(fb):
            return False, 'full preprocessing differs (its tokens, with __LINE__ pinned)'
    uses = line_uses(original, lang, fa)
    note = f'; its own code reads line numbers ({", ".join(uses)}): they follow the lean lines' if uses else ''
    if fa is not None:
        return True, 'GCC: same tokens and directives, and the same full preprocessing with __LINE__ pinned' + note
    return True, 'GCC: same tokens and directives (the file does not preprocess on its own)' + note
