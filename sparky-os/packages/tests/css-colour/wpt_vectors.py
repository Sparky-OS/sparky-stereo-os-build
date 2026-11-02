"""Extract colour test vectors from web-platform-tests css/css-color (parsing and computed values).

Usage: python3 -I wpt_vectors.py WPT_CSS_COLOR_PARSING_DIR OUT.json
Each vector: {"file", "kind": "computed" | "valid" | "invalid", "specified", "expected"}.
Vectors that need a document (var(), em and other lengths, sibling-index(), color-layers()) are listed as skipped.
web-platform-tests is BSD-3-Clause; the vectors are its contributors' work (the files' own author links).
"""

import json
import os
import re
import sys

STR = r'(?:`([^`$]*)`|"([^"\\]*(?:\\.[^"\\]*)*)"|\'([^\'\\]*(?:\\.[^\'\\]*)*)\')'
CALLS = [
    ('computed', re.compile(r'fuzzy_test_computed_color\(\s*' + STR + r'\s*,\s*' + STR + r'(?:\s*,\s*([0-9.]+))?')),
    ('computed', re.compile(r'test_computed_value\(\s*["\'`]color["\'`]\s*,\s*' + STR + r'\s*,\s*' + STR)),
    ('valid', re.compile(r'test_valid_value\(\s*["\'`]color["\'`]\s*,\s*' + STR + r'(?:\s*,\s*' + STR + r')?')),
    ('invalid', re.compile(r'test_invalid_value\(\s*["\'`]color["\'`]\s*,\s*' + STR)),
]
NEEDS_DOCUMENT = re.compile(r'var\(|sibling-index|sibling-count|color-layers|\d(?:em|px|vw|vh|rem|ex|ch|cm|mm|in|pt|pc|q)\b|attr\(|env\(',
                            re.I)


def pick(groups, k):
    g = groups[3 * k:3 * k + 3]
    for x in g:
        if x is not None:
            return x
    return None


def main():
    src, out = sys.argv[1], sys.argv[2]
    vectors = []
    skipped = []
    for name in sorted(os.listdir(src)):
        if not name.endswith('.html') or not (name.startswith('color-') or name.startswith('alpha-')):
            continue
        text = open(os.path.join(src, name), encoding='utf-8').read()
        for kind, rx in CALLS:
            for m in rx.finditer(text):
                g = m.groups()
                spec = pick(g, 0)
                exp = pick(g, 1) if len(g) > 3 else None
                if spec is None:
                    continue
                v = {'file': name, 'kind': kind, 'specified': spec, 'expected': exp}
                if len(g) == 7 and g[6]:
                    v['epsilon'] = float(g[6])
                if NEEDS_DOCUMENT.search(spec) or (exp and NEEDS_DOCUMENT.search(exp)):
                    skipped.append(v)
                else:
                    vectors.append(v)
    json.dump({'vectors': vectors, 'skipped': skipped}, open(out, 'w'), indent=0)
    print(len(vectors), 'vectors,', len(skipped), 'skipped')


if __name__ == '__main__':
    main()
