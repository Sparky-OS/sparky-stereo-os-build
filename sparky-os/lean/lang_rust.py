# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Rust: `//` line comments and nested `/* */` block comments, outside string, character and raw string literals.

The Rust reference, "Comments": "Non-doc comments are interpreted as a form of whitespace", and
"Whitespace": "A Rust program has identical meaning if each whitespace element is replaced with any other
legal whitespace element, such as a single space character." So a comment-only line goes completely, a
comment after code goes with the blanks before it, a comment with code after it on its line becomes one
space, and the authored empty lines stay (as C, C++ and Zig: no line directive, no kept empty line, no
stored line map; dpkg-stereo --resolve finds a lean line by its content in the authored text).

Kept, because they are not comments to the compiler:
- doc comments. The reference: "Line doc comments beginning with exactly three slashes (///), and block doc
  comments (/** ... */), both outer doc comments, are interpreted as a special syntax for doc attributes";
  `//!` and `/*! ... */` are the inner ones. They are `#[doc = "..."]` attributes: rustdoc publishes them and
  runs their code blocks as tests, `#![deny(missing_docs)]` fails a build without them, and macros read them
  (clap's derive builds a program's --help from them, displaydoc its error messages).
- the interpreter line of a script (`#!` not followed by `[`), notices and SPDX lines, the pointer line.
Data, never edited: string, byte string, C string and raw string literals, character and byte literals.

Line numbers move: `line!()`, `column!()`, `Location::caller()` and with them every panic message, every
`#[track_caller]` report and the debug line tables name lean lines, as `__LINE__` and `assert` do in C since
engine 0.1.20. `lines(text)` names every explicit use, so a build's report lists the files whose own code
reads its position.
Left as authored, with the reason: a file with cargo-script frontmatter; a file another file reads as data
with `include_str!` or `include_bytes!` (read_as_data); a crate whose build script or procedural macro
reads Rust source text (source_readers names them: a generator that reads comments is a consumer no
compiler check sees).
The check is the consumer's: rustc's own lexer (proc_macro::TokenStream, through a helper built with the
installed rustc) gives both texts the same token stream, doc attributes compared byte for byte.
"""

from __future__ import annotations

import atexit
import hashlib
import os
import posixpath
import re
import shutil
import subprocess
import tempfile

from .core import COMMENT, KEEP, LITERAL, Span, is_notice, is_pointer

KEY = 'rust'
EXTS = frozenset({'.rs'})
MARKER = '//'
DROP_LINES = True
NEXT = re.compile(r'//|/\*|"|\'|(?<![A-Za-z0-9_])[bc]?r#*"')
STRING_STOP = re.compile(r'\\|"')
POSITION = re.compile(r'\b(line|column)\s*!\s*[(\[{]|\bLocation\s*::\s*caller\s*\(|#\s*\[\s*track_caller\s*\]')
INCLUDE = re.compile(r'\b(include_str|include_bytes)\s*!\s*[(\[{]')
INCLUDE_PATH = re.compile(r'\s*"((?:[^"\\\n]|\\.)*)"\s*[)\]}]')
FRONTMATTER = re.compile(r'(?:#![^\[\n][^\n]*\n)?(?:[ \t]*\n)*---')
# what a build script or a procedural macro does when it reads source text instead of tokens
READ = re.compile(r'\bread_to_string\s*\(|\bFile\s*::\s*open\s*\(|\bfs\s*::\s*read\s*\(|\bread_dir\s*\(|\bWalkDir\s*::\s*new\s*\(|\bglob\s*\(')
SPAN_TEXT = re.compile(r'\bsource_text\s*\(|\blocal_file\s*\(|\bsource_file\s*\(')
PARSE_FILE = re.compile(r'\bparse_file\s*\(')
RS_LITERAL = re.compile(r'"(?:\.\.?/)*(?:src|tests|examples|benches)(?:/[^"\n]*)?"|"[^"\n]*/[^"\n/]*\.rs"')
HELPER = r'''extern crate proc_macro;
use proc_macro::{Delimiter, Spacing, TokenStream, TokenTree};
use std::fmt::Write as _;
use std::str::FromStr;

fn dump(stream: TokenStream, out: &mut String) {
    for tree in stream {
        match tree {
            TokenTree::Group(g) => {
                let (open, close) = match g.delimiter() {
                    Delimiter::Parenthesis => ("(", ")"),
                    Delimiter::Brace => ("{", "}"),
                    Delimiter::Bracket => ("[", "]"),
                    Delimiter::None => ("<none>", "</none>"),
                };
                let _ = writeln!(out, "G\t{}", open);
                dump(g.stream(), out);
                let _ = writeln!(out, "G\t{}", close);
            }
            TokenTree::Ident(i) => { let _ = writeln!(out, "I\t{}", i); }
            TokenTree::Punct(p) => {
                let _ = writeln!(out, "P\t{}\t{}", p.as_char(), if p.spacing() == Spacing::Joint { "joint" } else { "alone" });
            }
            TokenTree::Literal(l) => { let _ = writeln!(out, "L\t{}", l.to_string().replace('\\', "\\\\").replace('\n', "\\n")); }
        }
    }
}

#[proc_macro]
pub fn lean_tokens(_input: TokenStream) -> TokenStream {
    std::panic::set_hook(Box::new(|_| {}));
    let list = std::env::var("LEAN_RUST_LIST").expect("LEAN_RUST_LIST");
    let mut out = String::new();
    for name in std::fs::read_to_string(&list).expect("list").lines() {
        let text = std::fs::read_to_string(name).expect("input");
        let _ = writeln!(out, "== {}", name);
        // the lexer answers some errors with a panic instead of an Err: both mean it does not accept the text
        match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| TokenStream::from_str(&text))) {
            Ok(Ok(stream)) => dump(stream, &mut out),
            _ => { let _ = writeln!(out, "invalid"); }
        }
    }
    out.push_str("== end\n");
    std::fs::write(format!("{}.out", list), out).expect("output");
    TokenStream::new()
}
'''

INVALID = 'invalid'
_built = None
_temporary = None
_digests = {}


def keep_empty_after(line: str) -> bool:
    return False                                 # Rust has no line continuation outside literals


def joiner(src: str, start: int, end: int) -> str:
    return ' '                                   # the reference: any whitespace element may be a single space


def _comment(raw: str, a: int, b: int) -> Span:
    if raw.startswith('///') and not raw.startswith('////'):
        return Span(a, b, KEEP, 'outer doc comment: a #[doc] attribute (rustdoc, missing_docs, macros read it)')
    if raw.startswith('//!'):
        return Span(a, b, KEEP, 'inner doc comment: a #![doc] attribute')
    if raw.startswith('/**') and not raw.startswith('/***') and raw != '/**/':
        return Span(a, b, KEEP, 'outer block doc comment: a #[doc] attribute')
    if raw.startswith('/*!'):
        return Span(a, b, KEEP, 'inner block doc comment: a #![doc] attribute')
    if is_pointer(raw):
        return Span(a, b, KEEP, 'pointer line')
    if is_notice(raw):
        return Span(a, b, KEEP, 'licence or copyright notice')
    return Span(a, b, COMMENT)


def lex(src: str) -> list:
    """Spans of comments (COMMENT or KEEP) and literals, in order. Follows the reference's lexer: block comments
    nest; `'` opens a character literal only when it closes after one character or an escape, else it is a
    lifetime or a label; `r`, `br` and `cr` followed by hashes and a quote open a raw string that ends at a quote
    followed by as many hashes."""
    spans = []
    i, n = 0, len(src)
    if src.startswith('#!') and not src.startswith('#!['):
        end = src.find('\n')
        end = n if end < 0 else end
        spans.append(Span(0, end, KEEP, 'interpreter line'))
        i = end
    while True:
        m = NEXT.search(src, i)
        if not m:
            break
        i = m.start()
        what = m.group(0)
        if what == '//':
            end = src.find('\n', i)
            end = n if end < 0 else end
            spans.append(_comment(src[i:end], i, end))
            i = end
        elif what == '/*':
            depth, j = 1, i + 2
            while depth:
                a, b = src.find('/*', j), src.find('*/', j)
                if b < 0:
                    raise ValueError('unterminated block comment')
                if 0 <= a < b:
                    depth, j = depth + 1, a + 2
                else:
                    depth, j = depth - 1, b + 2
            spans.append(_comment(src[i:j], i, j))
            i = j
        elif what == '"':
            j = i + 1
            while True:
                q = STRING_STOP.search(src, j)
                if not q:
                    raise ValueError('unterminated string literal')
                if q.group(0) == '"':
                    j = q.start()
                    break
                j = q.start() + 2
            spans.append(Span(i, j + 1, LITERAL, 'string literal'))
            i = j + 1
        elif what == "'":
            if i + 1 < n and src[i + 1] == '\\':
                j = src.find("'", i + 3)
                if j < 0 or '\n' in src[i:j]:
                    raise ValueError('unterminated character literal')
                spans.append(Span(i, j + 1, LITERAL, 'character literal'))
                i = j + 1
            elif i + 2 < n and src[i + 2] == "'" and src[i + 1] not in "'\n":
                spans.append(Span(i, i + 3, LITERAL, 'character literal'))
                i += 3
            else:
                i += 1                           # a lifetime or a label
        else:                                    # r"...", r#"..."#, br and cr forms
            close = '"' + '#' * what.count('#')
            j = src.find(close, m.end())
            if j < 0:
                raise ValueError('unterminated raw string literal')
            spans.append(Span(i, j + len(close), LITERAL, 'raw string literal'))
            i = j + len(close)
    return spans


def code_text(src: str, literals=True) -> str:
    """The text with its comments (and its literals) blanked, offsets kept: what the compiler reads as code."""
    out = list(src)
    for sp in lex(src):
        if sp.kind == LITERAL and not literals:
            continue
        if sp.why == 'interpreter line':
            continue
        for k in range(sp.start, sp.end):
            if out[k] != '\n':
                out[k] = ' '
    return ''.join(out)


def refuse(src: str) -> str | None:
    if '\0' in src:
        return 'carries binary data'
    if FRONTMATTER.match(src):
        return 'cargo-script frontmatter: no qualified adapter'
    return None


def lines(src: str) -> list:
    """The 1-based authored lines whose own code reads its position (line!(), column!(), Location::caller(),
    #[track_caller]): their values name lean lines after the projection."""
    try:
        code = code_text(src)
    except ValueError:
        return []
    return sorted({code.count('\n', 0, m.start()) + 1 for m in POSITION.finditer(code)})


def embedded(path: str, src: str):
    """The payload paths this file reads with include_str! or include_bytes!, each with the reason it stays
    authored: a literal path relative to this file's folder; a path built any other way (concat!, env!) names
    this file's whole crate folder upwards from here (the trailing '/')."""
    try:
        code = code_text(src)
    except ValueError:
        return []
    here = posixpath.dirname(path)
    out = []
    for call in INCLUDE.finditer(code):
        why = f'read as data by {call.group(1)}! in {path}'
        m = INCLUDE_PATH.match(src, call.end())
        if m and '\\' not in m.group(1):
            out.append((posixpath.normpath(posixpath.join(here, m.group(1))), why))
        else:
            out.append((here.rstrip('/') + '/', why + ' (a computed path)'))
    return out


def source_reader(path: str, src: str, macro: bool = False) -> str | None:
    """Why this build script (or, with `macro`, this procedural-macro source) counts as a reader of Rust source
    text, or None. A macro that asks a span for its source text or file reads its callers' files as text. A build
    script reads source text when it opens files and names a source folder (src, tests, examples, benches) or a
    `.rs` file by a path with a folder in it, or when it parses a file with syn::parse_file (wasm-bindgen-shared
    hashes src/lib.rs and src/tys.rs into the schema version its tools compare). A bare file name such as
    "generated.rs", written into OUT_DIR, is not a source path."""
    try:
        code, text = code_text(src), code_text(src, literals=False)
    except ValueError:
        return f'{path} could not be read; treated as a reader of source text'
    if macro:
        m = SPAN_TEXT.search(code)
        return f'{path} calls {m.group(0).rstrip("( ")}(), which gives a macro the source text of its caller' if m else None
    if PARSE_FILE.search(code):
        return f'{path} calls parse_file(), which reads a Rust file as text'
    named = RS_LITERAL.search(text)
    if READ.search(code) and named:
        return f'{path} opens files and names Rust source paths ({named.group(0)})'
    return None


def rustc() -> str | None:
    return os.environ.get('LEAN_RUSTC') or shutil.which('rustc')


def _close():
    if _temporary is not None:
        _temporary.cleanup()


atexit.register(_close)


def _helper():
    """The token helper, a procedural macro built once per process with the installed rustc: it hands each
    listed file to proc_macro's TokenStream::from_str, which is the compiler's own lexer."""
    global _built, _temporary
    if _built is not None:
        return _built
    _temporary = tempfile.TemporaryDirectory(prefix='lean-rust-')
    d = _temporary.name
    with open(os.path.join(d, 'lean_tokens.rs'), 'w', encoding='utf-8') as f:
        f.write(HELPER)
    with open(os.path.join(d, 'driver.rs'), 'w', encoding='utf-8') as f:
        f.write('extern crate lean_tokens;\nlean_tokens::lean_tokens!();\n')
    r = subprocess.run([rustc(), '--edition', '2021', '--crate-type', 'proc-macro', '--crate-name', 'lean_tokens',
                        '-O', '--out-dir', d, 'lean_tokens.rs'],
                       capture_output=True, timeout=600, cwd=d)
    if r.returncode != 0:
        raise OSError('rustc could not build the token helper: '
                      + r.stderr.decode('utf-8', 'replace').strip().split('\n')[-1])
    _built = d
    return d


def token_streams(*texts):
    """Each text's token stream as rustc's lexer reads it, or ['invalid'] when the lexer refuses it."""
    d = _helper()
    with tempfile.TemporaryDirectory(prefix='lean-rust-in-') as work:
        names = []
        for k, text in enumerate(texts):
            p = os.path.join(work, f'f{k}.rs')
            with open(p, 'w', encoding='utf-8', newline='') as f:
                f.write(text)
            names.append(p)
        listing = os.path.join(work, 'list')
        with open(listing, 'w', encoding='utf-8') as f:
            f.write(''.join(name + '\n' for name in names))
        env = dict(os.environ, LEAN_RUST_LIST=listing)
        r = subprocess.run([rustc(), '--edition', '2021', '--crate-type', 'lib', '--emit', 'metadata', '-L', d,
                            '--out-dir', work, os.path.join(d, 'driver.rs')],
                           capture_output=True, timeout=600, cwd=work, env=env)
        # a text the lexer refuses also makes rustc report an error; the helper's answer is what counts
        if not os.path.exists(listing + '.out'):
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
    """Read many texts in few rustc runs and remember each one's token digest, so the per-file checks of a
    whole source tree (authored_refusal, verify) cost one compiler start per batch instead of two per file."""
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
    """An authored file rustc's lexer does not accept is retained: the consumer check needs rustc to read it."""
    if not rustc():
        return 'rustc unavailable; authored file retained'
    try:
        digest = token_digest(text)
    except (OSError, subprocess.SubprocessError) as e:
        return f'rustc could not read the authored file: {e}'
    if digest == INVALID:
        return "authored file holds text rustc's lexer does not accept (edition 2021); consumer qualification unavailable"
    return None


def verify(original: str, lean: str) -> tuple:
    try:
        prime([original, lean])
        a, b = token_digest(original), token_digest(lean)
        if INVALID in (a, b):
            return False, "rustc's lexer refuses the " + ('authored' if a == INVALID else 'lean') + ' text'
        if a != b:
            x, y = token_streams(original, lean)
            k = next((k for k, (p, q) in enumerate(zip(x, y)) if p != q), min(len(x), len(y)))
            return False, f"rustc's lexer reads different tokens (token {k + 1})"
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    return True, "rustc's lexer: the same tokens, doc attributes included"
