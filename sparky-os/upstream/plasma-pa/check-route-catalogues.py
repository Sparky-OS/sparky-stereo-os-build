#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read every routing label and failure from the actual binary package."""
import gettext
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

strings=json.loads((Path(__file__).parent/'routing-strings.json').read_text())
result={}
with tempfile.TemporaryDirectory(prefix='pa19-catalogues-',dir='/work19') as temporary:
    root=Path(temporary)
    subprocess.run(['dpkg-deb','-x',sys.argv[1],str(root)],check=True)
    for language in strings:
        if language=='en': continue
        path=root/'usr/share/locale'/language/'LC_MESSAGES/kcm_pulseaudio.mo'
        with path.open('rb') as f: catalogue=gettext.GNUTranslations(f)
        translated={message:catalogue.gettext(message) for message in strings['en']}
        for message,text in translated.items():
            assert text and text!=message,(language,message,'untranslated')
            assert sorted(re.findall(r'%[0-9]+',text))==sorted(re.findall(r'%[0-9]+',message)),(language,message,'placeholders')
        result[language]=translated
        print(language,len(translated),'routing labels and failures read from the built MO')
if len(sys.argv)>2: Path(sys.argv[2]).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('PASS: English source messages plus nine complete translated catalogues')
