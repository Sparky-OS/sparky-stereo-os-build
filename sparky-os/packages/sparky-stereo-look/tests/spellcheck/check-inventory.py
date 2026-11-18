#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Check the ten required language entries against a real Sonnet inventory."""
import json
from pathlib import Path
import sys

state = json.loads(Path(sys.argv[1]).read_text())
required = ['en_US', 'pl_PL', 'pt_BR', 'fr_FR', 'de_DE', 'es_ES',
            'ja_JP', 'ko_KR', 'zh_CN', 'zh_TW']
available = set(state['dictionaries'].values())
missing = []
for language in required:
    present = language in available or language.split('_')[0] in available
    print(('PASS' if present else 'FAIL'), language, 'dictionary present' if present else 'dictionary missing')
    if not present:
        missing.append(language)
selected = state['pageSelectedLanguage']
locale = state['systemLocale']
matched = selected == locale or selected == locale.split('_')[0]
print(('PASS' if matched else 'FAIL'), 'page selection', repr(selected), 'system locale', repr(locale))
print('Missing:', ', '.join(missing) if missing else 'none')
raise SystemExit(1 if missing or not matched else 0)
