"""C, C++ and GLSL: `//` and `/* */` comments, outside string, character and raw string literals.

Ported from CGM's _lang_c_like (its literal scan, raw strings and LineMap), with the 2026-10-09
counterexamples fixed (sparky-stereo-os.private research/lean-code-2026-10-09/handler-probes.json):
  - `int/**/value` became `intvalue`: a removed comment with code after it is one space, as in
    translation phase 3 (C23 5.1.1.2; GCC "Initial processing");
  - a raw string lost one of its blank lines: literals are never compacted;
  - `__LINE__` changed from 4 to 3: for C and C++ the renderer adds `#line N` before the first line
    after every removed run (and after every conditional directive while the numbering is shifted), so
    the compiler, `__LINE__`, `assert` and debug information keep the authored line numbers; the
    origin mapping takes part in the compiler's own location handling (LEAN-CODE-POLICY.md, C and C++).
Also: a `//` comment ending in a backslash continues on the next line (phase 2 splices it); C++14
digit separators (1'000) are not character literals; a lone quote in `#error` text is not a literal.
Kept comments: notices, the pointer line, and the fall-through comments GCC's -Wimplicit-fallthrough
reads. The check runs GCC's own preprocessor: with -fpreprocessed (no expansion) both texts give the
same tokens and the same directives, and where the file preprocesses on its own, full preprocessing
gives the same output, `__LINE__` values included.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, is_notice, is_pointer

KEY = 'c'
EXTS = frozenset({'.h', '.hh', '.hpp', '.hxx', '.c', '.cc', '.cpp', '.cxx', '.inl'})
GLSL_EXTS = frozenset({'.glsl', '.vert', '.frag', '.geom', '.comp', '.tesc', '.tese'})
MARKER = '//'
FALLTHROUGH = re.compile(r'fall(s| |-)?thr(ough|u)|\bnotreached\b|\blint\b', re.I)
RAW_PREFIX = ('R', 'u8R', 'uR', 'UR', 'LR')
RAW_OPEN = re.compile(r'"([^()\\\s]{0,16})\(')
CONDITIONAL = re.compile(r'^[ \t]*#[ \t]*(if|ifdef|ifndef|elif|elifdef|elifndef|else|endif)\b')


def keep_empty_after(line: str) -> bool:
    k, n = len(line), 0
    while k > 0 and line[k - 1] == '\\':
        n += 1
        k -= 1
    return n % 2 == 1


def joiner(src: str, start: int, end: int) -> str:
    return ' '


def lex(src: str) -> list:
    s, n = src, len(src)
    spans = []
    i = 0
    while i < n:
        c = s[i]
        nx = s[i + 1] if i + 1 < n else ''
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
    if '\0' in src:
        return 'carries binary data'
    if '??/' in src:
        return 'uses trigraphs'
    return None


def line_directives(text: str, origin: list, src: str):
    """Add `#line N` so every MR line keeps its authored number for the compiler; returns new
    (text, origin). A directive goes before the first line after any shift, and again after every
    conditional directive while lines are shifted (a skipped group would ignore one inside it). Never
    after a line ending in a backslash (a directive cannot start inside a continued line)."""
    starts = [0]
    for k, ch in enumerate(src):
        if ch == '\n':
            starts.append(k + 1)
    import bisect

    def src_line(off):
        return bisect.bisect_right(starts, off)

    lines = text.split('\n')
    out, out_origin = [], []
    pos = 0
    believed = 1           # the line number the compiler believes the next MR line has
    prev = ''
    prev_conditional = False
    for idx, line in enumerate(lines):
        o = origin[pos] if pos < len(origin) else -1
        if line == '' and pos < len(origin):
            o = origin[pos]  # the newline's origin
        real = src_line(o) if o >= 0 else None
        natural = len(out) + 1
        need = real is not None and (real != believed or (prev_conditional and real != natural))
        if need and not keep_empty_after(prev):
            d = f'#line {real}'
            out.append(d)
            out_origin.extend([-1] * (len(d) + 1))
            believed = real
        out.append(line)
        seg = origin[pos:pos + len(line) + 1]
        out_origin.extend(seg if len(seg) == len(line) + 1 else seg + [-1] * (len(line) + 1 - len(seg)))
        pos += len(line) + 1
        believed += 1
        prev_conditional = bool(CONDITIONAL.match(line))
        prev = line
    new = '\n'.join(out)
    return new, out_origin[:len(new)]


def _cpp(args, text, lang):
    gcc = shutil.which('gcc') or shutil.which('cc')
    if not gcc:
        return None
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'f.' + ('cc' if lang == 'c++' else 'c'))
        with open(p, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(text)
        r = subprocess.run([gcc, '-E', '-x', lang, *args, p], capture_output=True, timeout=120)
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


def _splice(text: str) -> str:
    """Translation phase 2 (C23 5.1.1.2): a backslash-newline joins two lines. GCC's -fpreprocessed
    mode skips it, so the check does it first, the same way for both texts."""
    return text.replace('\\\n', '')


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
    fa = _cpp(['-P', '-w'], original, lang)
    if fa is not None:
        fb = _cpp(['-P', '-w'], lean, lang)
        if fb is None or _units(fa) != _units(fb):
            return False, 'full preprocessing differs'
        return True, 'GCC: same tokens and directives, and the same full preprocessing'
    return True, 'GCC: same tokens and directives (the file does not preprocess on its own)'
