#!/usr/bin/env python3
# Sparky Stereo OS (ORDER 579): the sentence "This film has no sound." is the stereo layer's (po/LANG/stereo-layer_qt.po, context
# Stereo::NoSound|); sView (string 2115 of StMoviePlayer/lang/*/StMoviePlayer.lng) and VLC (msgid of po/LANG.po, as a patch or a tree)
# keep a copy. This check fails when a copy differs from the layer's in a language it ships, or when a required language is missing.
# Usage: check.py --layer-po DIR --sview-lang DIR [--vlc-patch FILE | --vlc-po DIR]   (--self-test: the check must fail on a drifted copy)
import argparse, re, shutil, sys, tempfile
from pathlib import Path

LANGS = ['de', 'es', 'fr', 'ja', 'ko', 'pl', 'pt_BR', 'zh_CN', 'zh_TW']
SVIEW = {'de': 'german', 'es': 'spanish', 'fr': 'french', 'ja': 'japanese', 'ko': 'korean', 'pl': 'polish', 'pt_BR': 'portuguesebr',
         'zh_CN': 'chinese', 'zh_TW': 'chineset'}
ENGLISH = 'This film has no sound.'


def po_value(text, msgid=ENGLISH):
    m = re.search(r'msgid "' + re.escape(msgid) + r'"\nmsgstr "((?:[^"\\]|\\.)*)"', text)
    return m.group(1) if m else None


def run(layer, sview, vlc_po=None, vlc_patch=None):
    bad = []
    ref = {}
    for l in LANGS:
        f = Path(layer) / l / 'stereo-layer_qt.po'
        v = po_value(f.read_text(encoding='utf8')) if f.is_file() else None
        if not v:
            bad.append(f'layer {l}: sentence missing')
        ref[l] = v
    for l in LANGS:
        f = Path(sview) / SVIEW[l] / 'StMoviePlayer.lng'
        m = re.search(r'^2115=(.*?)\r?$', f.read_text(encoding='utf8'), re.M) if f.is_file() else None
        if not m or m.group(1) != ref[l]:
            bad.append(f'sview {l}: {m.group(1) if m else None!r} != layer {ref[l]!r}')
    en = Path(sview) / 'english' / 'StMoviePlayer.lng'
    if not re.search(r'^2115=' + re.escape(ENGLISH) + r'\r?$', en.read_text(encoding='utf8'), re.M):
        bad.append('sview en: differs from the layer sentence')
    vlc = {}
    if vlc_po:
        for l in LANGS:
            f = Path(vlc_po) / f'{l}.po'
            vlc[l] = po_value(f.read_text(encoding='utf8')) if f.is_file() else None
    elif vlc_patch:
        cur = None
        for line in Path(vlc_patch).read_text(encoding='utf8').splitlines():
            m = re.match(r'\+\+\+ b/po/(\w+)\.po', line)
            if m:
                cur = m.group(1)
            if cur and line.startswith('+msgid "' + ENGLISH + '"'):
                vlc[cur] = 'next'
            elif cur and vlc.get(cur) == 'next' and line.startswith('+msgstr "'):
                vlc[cur] = line[len('+msgstr "'):-1]
    for l in LANGS:
        if vlc_po or vlc_patch:
            if vlc.get(l) != ref[l]:
                bad.append(f'vlc {l}: {vlc.get(l)!r} != layer {ref[l]!r}')
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--layer-po', required=True)
    ap.add_argument('--sview-lang', required=True)
    ap.add_argument('--vlc-patch')
    ap.add_argument('--vlc-po')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    bad = run(a.layer_po, a.sview_lang, a.vlc_po, a.vlc_patch)
    if a.self_test:
        # the check must fail when a copy drifts
        with tempfile.TemporaryDirectory() as t:
            lang = Path(t) / 'lang'
            shutil.copytree(a.sview_lang, lang)
            f = lang / 'german' / 'StMoviePlayer.lng'
            f.write_text(f.read_text(encoding='utf8').replace('2115=Dieser Film hat keinen Ton.', '2115=Dieser Film hat keinen Ton!'), encoding='utf8')
            if not run(a.layer_po, lang, a.vlc_po, a.vlc_patch):
                print('self-test FAILED: a drifted sView wording passed')
                return 1
        print('self-test ok: a drifted wording fails')
    for b in bad:
        print('DRIFT', b)
    print('wording check:', 'FAILED' if bad else 'ok (%d languages, layer = sView = VLC)' % len(LANGS))
    return 1 if bad else 0


sys.exit(main())
