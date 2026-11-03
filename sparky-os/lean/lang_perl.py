# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Perl: whole comment lines only, outside quotes, POD, heredocs and __END__/__DATA__.

Perl is the hardest language here to read without perl itself (quote-like operators with any
delimiter, `#` inside /x regular expressions, heredocs), so this handler removes only lines that are a
comment from their first non-blank character, skips POD (perlpod: kept, it is program documentation),
heredoc bodies (perlop "Quote and Quote-like Operators") and everything after __END__/__DATA__, keeps
`# line N "file"` directives (perlsyn "Plain Old Comments (Not!)"), and lets perl decide: B::Deparse
must print the same program for both texts (it prints the compiled op tree, never comments). Deparse
compiles the file, so it runs as an unprivileged user when the projection runs as root.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, is_notice, is_pointer

KEY = 'perl'
EXTS = frozenset({'.pl', '.pm'})
MARKER = '#'
LINE_DIRECTIVE = re.compile(r'#\s*line\s+\d+')
HEREDOC = re.compile(r'<<(~?)\s*(?:"([^"\n]*)"|\'([^\'\n]*)\'|([A-Za-z_]\w*))')
keep_empty_after = None
PAIRS = {'(': ')', '[': ']', '{': '}', '<': '>'}
QUOTES = frozenset(('q', 'qq', 'qx', 'qw', 'qr', 'm', 's', 'tr', 'y'))
WORD = re.compile(r'[A-Za-z_]\w*(?:::\w+)*')
VARIABLE = re.compile(r'[$@%](?:\#?[A-Za-z_]\w*(?:::\w+)*|\d+|[^\w\s])')
# Unambiguous expression contexts for a bare slash. This is not a Perl parser;
# prototypes and user-defined functions still need the unchanged Deparse gate.
TERM_AFTER = frozenset(('return', 'print', 'say', 'split', 'grep', 'map', 'not',
                        'and', 'or', 'xor', 'if', 'unless', 'while', 'until',
                        'eq', 'ne', 'lt', 'gt', 'le', 'ge', 'cmp', 'x'))


def quote_end(src, start, paired=True):
    """perlop, 'Finding the end': delimiters first, before interpolation or /x.

    Escaped delimiters and backslashes do not close a section; a backslash
    delimiter itself is the exception. Only the opening bracket's kind nests.
    """
    opening = src[start]
    closing = PAIRS.get(opening, opening) if paired else opening
    depth = 1
    p = start + 1
    while p < len(src):
        c = src[p]
        if c == '\\' and opening != '\\':
            p += 2
            continue
        if c == closing:
            depth -= 1
            if not depth:
                return p + 1
        elif opening != closing and c == opening:
            depth += 1
        p += 1
    return len(src)


def quote_gap(src, start):
    """A hash is a delimiter unless whitespace precedes it in an operator gap."""
    p = start
    while p < len(src) and src[p].isspace():
        p += 1
        if p < len(src) and src[p] == '#':
            end = src.find('\n', p)
            p = len(src) if end < 0 else end
    return p


def quote_like_end(src, start, operator):
    p = quote_end(src, start)
    if operator in ('s', 'tr', 'y') and p < len(src):
        if src[start] in PAIRS:
            p = quote_gap(src, p)
            if p < len(src):
                p = quote_end(src, p)
        else:
            # The middle delimiter closes the pattern and opens the replacement.
            p = quote_end(src, p - 1, paired=False)
    if operator in ('qr', 'm', 's', 'tr', 'y', '/'):
        while p < len(src) and src[p].isalpha():
            p += 1
    return p


def joiner(src, start, end):
    return ''


def lex(src: str) -> list:
    spans = []
    lines = src.split('\n')
    pos = 0
    pod = False
    pending = []
    i = 0
    offs = []
    resume = 0
    term = True
    previous = ''
    for ln in lines:
        offs.append(pos)
        pos += len(ln) + 1
    while i < len(lines):
        line = lines[i]
        a = offs[i]
        if pending:
            delim, indent = pending.pop(0)
            j = i
            while j < len(lines):
                t = lines[j].strip() if indent else lines[j]
                if t == delim:
                    break
                j += 1
            if j > i:
                spans.append(Span(offs[i], offs[j - 1] + len(lines[j - 1]), LITERAL, 'heredoc body'))
            i = j + 1
            continue
        if resume > a:
            # A quote begun on an earlier line owns even POD/data-looking text.
            if resume >= a + len(line):
                i += 1
                continue
        elif pod:
            if line.startswith('=cut'):
                pod = False
            i += 1
            continue
        elif re.match(r'=[a-zA-Z]', line):
            pod = True
            i += 1
            continue
        elif line.startswith(('__END__', '__DATA__')):
            break
        t = line.lstrip(' \t')
        if resume <= a and t.startswith('#'):
            if i == 0 and t.startswith('#!'):
                spans.append(Span(a, a + len(line), KEEP, 'interpreter line'))
            elif LINE_DIRECTIVE.match(t):
                spans.append(Span(a, a + len(line), KEEP, 'line directive read by perl'))
            elif is_pointer(t) or is_notice(t):
                spans.append(Span(a, a + len(line), KEEP, 'notice or pointer'))
            else:
                spans.append(Span(a + len(line) - len(t), a + len(line), COMMENT))
        else:
            p = max(a, resume)
            end = a + len(line)
            while p < end:
                c = src[p]
                if c.isspace():
                    p += 1
                    continue
                if c == '#':
                    break  # Inline comments stay, but cannot open quotes/heredocs.
                m = HEREDOC.match(src, p)
                if m:
                    pending.append((m.group(2) or m.group(3) or m.group(4), bool(m.group(1))))
                    p = m.end()
                    term, previous = False, 'heredoc'
                    continue
                m = VARIABLE.match(src, p)
                if m:
                    p = m.end()
                    term, previous = False, 'variable'
                    continue
                word = WORD.match(src, p)
                operator = ''
                delimiter = p
                if word:
                    name = word.group()
                    delimiter = quote_gap(src, word.end())
                    if (name in QUOTES and previous not in ('->', '::', 'sub', 'package')
                            and delimiter < len(src) and not src.startswith('=>', delimiter)
                            and not (previous == '{' and src[delimiter] == '}')):
                        operator = name
                    else:
                        p = word.end()
                        term, previous = name in TERM_AFTER, name
                        continue
                elif c in "'\"`":
                    operator = c
                elif c == '/' and term:
                    operator = '/'
                if operator:
                    stop = quote_like_end(src, delimiter, operator)
                    spans.append(Span(p, stop, LITERAL, 'quoted construct'))
                    p = resume = stop
                    term, previous = False, 'quote'
                    continue
                pair = src[p:p + 2]
                if pair in ('->', '::', '++', '--', '//', '/=', '=>', '=~', '!~'):
                    p += 2
                    if pair not in ('++', '--'):
                        term = True
                    previous = pair
                    continue
                term = c not in ')]}' and not c.isdigit()
                previous = c
                p += 1
        i += 1
    return spans


def refuse(src):
    if '\0' in src:
        return 'carries binary data'
    if '__LINE__' in src or 'caller' in src and 'line' in src:
        return 'uses line numbers (__LINE__, caller)'
    if re.search(r'\$0|__FILE__', src) and re.search(r'\bopen\b', src):
        return 'may read its own source'
    return None


def deparse(text: str):
    perl = shutil.which('perl')
    if not perl:
        return None
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, 'f.pl')
        with open(p, 'w', encoding='utf-8', errors='surrogateescape') as f:
            f.write(text)
        os.chmod(d, 0o755)
        os.chmod(p, 0o644)
        cmd = [perl, '-MO=Deparse,-q', p]
        if os.geteuid() == 0 and shutil.which('setpriv'):
            cmd = ['setpriv', '--reuid=nobody', '--regid=nogroup', '--clear-groups', *cmd]
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=120, cwd=d)
        except subprocess.TimeoutExpired:
            return None
        if r.returncode != 0:
            return None
        return r.stdout.decode('utf-8', 'surrogateescape').replace(p, 'FILE')


def authored_refusal(text: str) -> str | None:
    """An authored file perl does not compile on its own is retained: B::Deparse, the consumer check, needs it."""
    if not shutil.which('perl'):
        return 'perl unavailable; authored script retained'
    if deparse(text) is None:
        return 'authored script is not compiled by perl on its own; consumer qualification unavailable'
    return None


def verify(original, lean, interpreter=''):
    a = deparse(original)
    if a is None:
        return False, 'perl could not compile the authored file on its own'
    b = deparse(lean)
    if a != b:
        return False, 'B::Deparse prints a different program'
    return True, 'B::Deparse prints the same program'
