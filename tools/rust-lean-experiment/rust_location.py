#!/usr/bin/env python3
"""Resolve a manifest-bound Rust source with the existing content resolver."""
from pathlib import PurePosixPath
from lean import lang_rust
from lean.locate import Locator,Side


class RustLocator(Locator):
    def __init__(self,authored,projected,path):
        if PurePosixPath(path).suffix!='.rs':raise ValueError('explicit Rust resolution requires a bound .rs input')
        # consumers.choose treats a first-line #![attribute] as an interpreter.
        # These inputs already have an independently qualified Rust identity;
        # select its unchanged lexer explicitly, then reuse the content lookup.
        a,m=authored.decode('utf-8'),projected.decode('utf-8')
        self.a,self.m=Side(a,lang_rust.lex(a),False),Side(m,lang_rust.lex(m),False)


def locate(authored,projected,path,line,column):
    return RustLocator(authored,projected,path).find(line,column)
