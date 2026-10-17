#!/usr/bin/env python3
"""Writes show.qml and the translation sources from slides.json, the approved slide texts (the artwork's installer-slides/slides.json).
usage: make-slideshow.py SLIDES_JSON BRANDING_DIR TRANSLATIONS_DIR
The texts are never retyped: every string in show.qml is read from the JSON, and the check at the end parses the QML back and compares.
Translation sources: one .ts per language, English the source language; a language's .qm is built only from finished translations.
"""
import sys, json, re, os
from xml.sax.saxutils import escape

LANGS = ['pl', 'pt_BR', 'fr', 'ja', 'ko', 'zh_CN', 'zh_TW']

def q(s): return json.dumps(s, ensure_ascii=False)

def main(slides_json, branding, trans):
    slides = json.load(open(slides_json, encoding='utf-8'))
    out = ['''/* Sparky Stereo OS: the installer's slideshow, twenty-three stereo slides (full side by side, left eye first, PNG with the
 * sTER chunk). The branding sets slideshowWindow, so the QML runs in a window the picture can hand to the compositor.
 * The words are qsTr strings, translated through the branding's lang/calamares-sparky_<locale>.qm; English is the source.
 * Written by tools/make-slideshow.py from the approved texts (slides.json of the SparkyOS artwork): change the texts there.
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 20000
        repeat: true
        running: presentation.activatedInCalamares
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { }
    function onLeave() { }
''']
    for sl in slides:
        out.append(f'''
    StereoSlide {{
        pair: "slide{sl['slide']:02d}-{sl['id']}.pns"
        title: qsTr({q(sl['title'])})
        lines: [
''' + ',\n'.join(f'            qsTr({q(l)})' for l in sl['lines']) + '''
        ]
    }
''')
    out.append('}\n')
    qml = ''.join(out); open(os.path.join(branding, 'show.qml'), 'w', encoding='utf-8').write(qml)
    # the check: every qsTr string, in order, is the JSON's
    got = [json.loads(m) for m in re.findall(r'qsTr\((".*")\)', qml)]
    want = [t for sl in slides for t in [sl['title']] + sl['lines']]
    assert got == want, 'show.qml does not carry the approved texts'
    os.makedirs(trans, exist_ok=True)
    msgs = []
    for sl in slides:
        for t in [sl['title']] + sl['lines']:
            if t not in msgs: msgs.append(t)
    for lang in ['en'] + LANGS:
        body = ['<?xml version="1.0" encoding="utf-8"?>', '<!DOCTYPE TS>', f'<TS version="2.1" language="{lang}" sourcelanguage="en">', '<context>', '    <name>show</name>']
        for t in msgs:
            if lang == 'en': tr = f'<translation>{escape(t)}</translation>'
            else: tr = '<translation type="unfinished"></translation>'
            body += ['    <message>', f'        <source>{escape(t)}</source>', f'        {tr}', '    </message>']
        body += ['</context>', '</TS>']
        open(os.path.join(trans, f'calamares-sparky_{lang}.ts'), 'w', encoding='utf-8').write('\n'.join(body) + '\n')
    print(len(slides), 'slides,', len(msgs), 'strings,', 1 + len(LANGS), 'translation sources')

main(*sys.argv[1:4])
