#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Generate package records and the native lookup from the same pinned profiles."""
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
debian = root / 'debian'
profiles = json.loads((debian / 'profiles.json').read_text())
messages = json.loads((debian / 'model-missing.json').read_text())
common = json.loads((debian / 'model-installer-messages.json').read_text())
def cpp(text):
    return json.dumps(text, ensure_ascii=False)

edition = debian / 'edition'
edition.mkdir(exist_ok=True)
files = {}
for p in profiles:
    for f in p['files']:
        files.setdefault(f['file'], dict(f, package=p['package']))
(edition / 'edition_model_files.h').write_text('#pragma once\n#include <cstdint>\nstruct EditionModelFile { const char* file; const char* sha256; uint64_t bytes; const char* package; };\ninline constexpr EditionModelFile kEditionModelFiles[] = {\n'+''.join('{'+','.join([cpp(f['file']),cpp(f['sha256']),str(f['bytes'])+'ULL',cpp(f['package'])])+'},\n' for f in files.values())+'};\n')
generated = {}
for p in profiles:
    for name in p.get('generated_verified', []):
        generated.setdefault(name, p['package'])
with (edition / 'edition_model_files.h').open('a') as output:
    output.write('struct EditionGeneratedModel { const char* file; const char* package; };\ninline constexpr EditionGeneratedModel kEditionGeneratedModels[] = {\n'+''.join('{'+cpp(name)+','+cpp(package)+'},\n' for name,package in generated.items())+'};\n')
text = '#pragma once\nstruct EditionModelMessage { const char* language; const char* text; };\n'
for array, rows in [('kEditionModelMessages', messages), ('kEditionGraphicsMessages', {k:v['graphics'] for k,v in common.items()})]:
    text += 'inline constexpr EditionModelMessage '+array+'[] = {\n'+''.join('{'+cpp(k)+','+cpp(v)+'},\n' for k,v in rows.items())+'};\n'
(edition / 'edition_model_messages.h').write_text(text)
folder = debian / 'model-profiles'
folder.mkdir(exist_ok=True)
for p in profiles:
    p['version'] = '2026.11.12-1+stereo3d1+lc1'
    (folder / (p['package']+'.json')).write_text(json.dumps(p,ensure_ascii=False,indent=2)+'\n')
    (debian / (p['package']+'.postinst')).write_text('#!/bin/sh\nexec /usr/lib/sparky-stereo-apt/model-postinst "$@"\n')
    (debian / (p['package']+'.postrm')).write_text('#!/bin/sh\nexec /usr/lib/sparky-stereo-apt/model-postrm "$@"\n')
