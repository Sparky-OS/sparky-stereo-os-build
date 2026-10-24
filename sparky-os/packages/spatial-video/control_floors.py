# SPDX-License-Identifier: MIT
"""Keep spatial-video consumers on the backend that implements their route."""
import re

QT = '6.11.2-3+stereo3d10+lc1'
MPV = '1:0.41.0-dmo9+stereo3d7+lc1'

def set_floors(project, text):
    if project in ('mpv', 'qt', 'vlc') and 'libstereo-av-dev' not in text:
        text = text.replace('Build-Depends:', 'Build-Depends: libstereo-av-dev (>= 1.12.0-1+lc1),', 1)
    if project == 'gwenview' and 'qt6-multimedia-private-dev' not in text:
        text = text.replace('Build-Depends:', f'Build-Depends: qt6-multimedia-private-dev (>= {QT}),', 1)
    if project in ('gwenview', 'dragon'):
        text = re.sub(r'\bqt6-multimedia-dev(?: \([^)]*\))?', f'qt6-multimedia-dev (>= {QT})', text)
    binary = {'dragon': 'dragonplayer', 'gwenview': 'gwenview', 'haruna': 'haruna'}.get(project)
    floors = {
        'gwenview': [('libqt6multimedia6', QT), ('libqt6multimediawidgets6', QT)],
        'dragon': [('libqt6multimedia6', QT), ('qml6-module-qtmultimedia', QT)],
        'haruna': [('libmpv2', MPV)],
    }.get(project, [])
    paragraphs = text.split('\n\n')
    for i, paragraph in enumerate(paragraphs):
        if not binary or not paragraph.startswith('Package: ' + binary + '\n'):
            continue
        for name, version in floors:
            value = f'{name} (>= {version})'
            pattern = re.escape(name) + r'(?: \([^)]*\))?'
            if re.search(pattern, paragraph):
                paragraph = re.sub(pattern, value, paragraph, count=1)
            else:
                paragraph = paragraph.replace('Depends:', 'Depends: ' + value + ',', 1)
        paragraphs[i] = paragraph
    return '\n\n'.join(paragraphs)
