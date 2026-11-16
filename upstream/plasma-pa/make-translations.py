#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the edition-only translation patch against the source tag's catalogues."""
import difflib
import json
import sys
from pathlib import Path
source = Path(sys.argv[1])
output = Path(sys.argv[2])
translations = {
    'pl': ['Pokaż wirtualne strumienie', 'Pokaż wirtualne urządzenia i strumienie'],
    'pt_BR': ['Mostrar fluxos virtuais', 'Mostrar dispositivos e fluxos virtuais'],
    'fr': ['Afficher les flux virtuels', 'Afficher les périphériques et les flux virtuels'],
    'de': ['Virtuelle Streams anzeigen', 'Virtuelle Geräte und Streams anzeigen'],
    'es': ['Mostrar flujos virtuales', 'Mostrar dispositivos y flujos virtuales'],
    'ja': ['仮想ストリームを表示', '仮想デバイスとストリームを表示'],
    'ko': ['가상 스트림 표시', '가상 장치 및 스트림 표시'],
    'zh_CN': ['显示虚拟音频流', '显示虚拟设备和音频流'],
    'zh_TW': ['顯示虛擬音訊串流', '顯示虛擬裝置與音訊串流'],
}
messages = [('kcm_pulseaudio', 'Show Virtual Streams'),
            ('plasma_applet_org.kde.plasma.volume', 'Show virtual devices and streams')]
patch = []
for language, strings in translations.items():
    for (domain, message), translated in zip(messages, strings):
        relative = f'po/{language}/{domain}.po'
        old = (source/relative).read_text()
        assert f'msgid {json.dumps(message)}' not in old
        new = old.rstrip('\n') + '\n\n#. Show client-less loopback and filter streams as well.\n'
        new += f'msgid {json.dumps(message)}\nmsgstr {json.dumps(translated,ensure_ascii=False)}\n'
        patch.append(f'diff --git a/{relative} b/{relative}\n')
        patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+relative,tofile='b/'+relative))
output.write_text(''.join(patch))
