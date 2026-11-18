#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Check the ten required language entries against a real Sonnet inventory."""
import json
from pathlib import Path
import sys

state = json.loads(Path(sys.argv[1]).read_text())
required = ['en_US', 'pl_PL', 'pt_BR', 'fr_FR', 'de_DE', 'es_ES',
            'ko_KR']
available = set(state['dictionaries'].values())
missing = []
for language in required:
    present = language in available or language.split('_')[0] in available
    print(('PASS' if present else 'FAIL'), language, 'dictionary present' if present else 'dictionary missing')
    if not present:
        missing.append(language)
for language in ('ja_JP', 'zh_CN', 'zh_TW'):
    print('NONE', language, 'no word-list spelling dictionary; preserve Sonnet choice for Latin-letter words')
selected = state['pageSelectedLanguage']
locale = state['systemLocale']
matched = locale in ('ja_JP', 'zh_CN', 'zh_TW') or selected == locale or selected == locale.split('_')[0]
print(('PASS' if matched else 'FAIL'), 'page selection', repr(selected), 'system locale', repr(locale))
print('Missing:', ', '.join(missing) if missing else 'none')
enabled = state['checkerEnabledByDefault']
uppercase = state['checkUppercase']
if __import__('os').environ.get('EXPECT_USER') == '1':
    enabled = not enabled
    uppercase = not uppercase
print('PASS' if enabled and not uppercase else 'FAIL', 'recorded nondefault Sonnet keys')
raise SystemExit(1 if missing or not matched or not enabled or uppercase else 0)
