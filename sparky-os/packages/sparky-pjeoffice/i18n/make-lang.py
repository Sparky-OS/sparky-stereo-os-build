#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make lang/LANG (KEY="text", %s per argument) from lang_strings.py and check every language has the same keys and the same %s count.
Usage: make-lang.py LANG_DIR"""
import re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from lang_strings import ORDER, S

out = Path(sys.argv[1])
out.mkdir(exist_ok=True)
for key, texts in S.items():
    assert len(texts) == len(ORDER), key
    counts = {len(re.findall(r'%[0-9$]*s', t)) for t in texts}
    assert len(counts) == 1, (key, counts)
for index, code in enumerate(ORDER):
    # positional %N$s is read as the engine reads it; Korean/Chinese reorder with it
    lines = ['%s="%s"\n' % (key, texts[index].replace('"', '\\"')) for key, texts in S.items()]
    (out / code).write_text(''.join(lines), encoding='utf-8')
print('ok', len(ORDER), 'files', len(S), 'keys')
