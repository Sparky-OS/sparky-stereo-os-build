#!/usr/bin/env python3
# Sparky Stereo OS (ORDER 579): the sentence "This film has no sound." is the stereo layer's (po/LANG/stereo-layer_qt.po, context
# Stereo::NoSound|). sView (string 2115 of StMoviePlayer/lang/*/StMoviePlayer.lng) and VLC (the msgid in po/LANG.po) keep a copy. This
# check fails when a copy differs from the layer's in a language it ships, or when a required language is missing.
#   python3 tests/no-sound-wording/check.py            runs from a clone with no arguments: the layer's sentences are kept in
#                                                      layer-sentences.json beside this file, the copies are read from the recipe's own
#                                                      patches (sparky-os/upstream/no-sound/patches); when a stereo-layer clone sits beside
#                                                      the build tree (../stereo-layer/po) or STEREO_LAYER_PO names its po folder, the
#                                                      layer's own catalogue is compared with the kept sentences too
#   --update LAYER_PO                                  rewrite layer-sentences.json from the layer's catalogue
#   --sview-lang DIR / --vlc-patch FILE / --vlc-po DIR read the copies from a tree instead (a fork checkout, VLC's po folder)
#   --self-test                                        also require that a drifted copy fails
import argparse, json, os, re, shutil, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TREE = HERE.parent.parent
PATCHES = TREE / 'sparky-os' / 'upstream' / 'no-sound' / 'patches'
REFERENCE = HERE / 'layer-sentences.json'
LANGS = ['de', 'es', 'fr', 'ja', 'ko', 'pl', 'pt_BR', 'zh_CN', 'zh_TW']
SVIEW = {'de': 'german', 'es': 'spanish', 'fr': 'french', 'ja': 'japanese', 'ko': 'korean', 'pl': 'polish', 'pt_BR': 'portuguesebr',
         'zh_CN': 'chinese', 'zh_TW': 'chineset'}
ENGLISH = 'This film has no sound.'


def po_value(text):
    m = re.search(r'msgid "' + re.escape(ENGLISH) + r'"\nmsgstr "((?:[^"\\]|\\.)*)"', text)
    return m.group(1) if m else None


def layer_sentences(layer_po):
    out = {}
    for l in LANGS:
        f = Path(layer_po) / l / 'stereo-layer_qt.po'
        out[l] = po_value(f.read_text(encoding='utf8')) if f.is_file() else None
    return out


def sview_from_patch(patch):
    out, cur = {}, None
    for line in Path(patch).read_text(encoding='utf8').splitlines():
        m = re.match(r'\+\+\+ b/StMoviePlayer/lang/(\w+)/StMoviePlayer\.lng', line)
        if m:
            cur = m.group(1)
        elif cur and line.startswith('+2115='):
            out[cur] = line[len('+2115='):].rstrip('\r')
    return out


def sview_from_tree(lang):
    out = {}
    for d in list(SVIEW.values()) + ['english']:
        f = Path(lang) / d / 'StMoviePlayer.lng'
        m = re.search(r'^2115=(.*?)\r?$', f.read_text(encoding='utf8'), re.M) if f.is_file() else None
        out[d] = m.group(1) if m else None
    return out


def vlc_from_patch(patch):
    out, cur = {}, None
    for line in Path(patch).read_text(encoding='utf8').splitlines():
        m = re.match(r'\+\+\+ b/po/(\w+)\.po', line)
        if m:
            cur = m.group(1)
        if cur and line.startswith('+msgid "' + ENGLISH + '"'):
            out[cur] = 'next'
        elif cur and out.get(cur) == 'next' and line.startswith('+msgstr "'):
            out[cur] = line[len('+msgstr "'):-1]
    return out


def vlc_from_po(folder):
    out = {}
    for l in LANGS:
        f = Path(folder) / f'{l}.po'
        out[l] = po_value(f.read_text(encoding='utf8')) if f.is_file() else None
    return out


def run(ref, sview, vlc):
    bad = []
    for l in LANGS:
        if not ref.get(l):
            bad.append(f'reference {l}: sentence missing')
        sv = sview.get(SVIEW[l])
        if sv != ref.get(l):
            bad.append(f'sview {l}: {sv!r} != layer {ref.get(l)!r}')
        v = vlc.get(l)
        if v != ref.get(l):
            bad.append(f'vlc {l}: {v!r} != layer {ref.get(l)!r}')
    if sview.get('english') != ENGLISH:
        bad.append(f"sview en: {sview.get('english')!r} != {ENGLISH!r}")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--update')
    ap.add_argument('--layer-po')
    ap.add_argument('--sview-lang')
    ap.add_argument('--vlc-patch')
    ap.add_argument('--vlc-po')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args()
    if a.update:
        ref = layer_sentences(a.update)
        if None in ref.values():
            print('layer catalogue lacks the sentence for', [l for l, v in ref.items() if v is None]); return 1
        REFERENCE.write_text(json.dumps(ref, ensure_ascii=False, indent=1, sort_keys=True) + '\n', encoding='utf8')
        print('wrote', REFERENCE); return 0
    ref = json.loads(REFERENCE.read_text(encoding='utf8'))
    layer_po = a.layer_po or os.environ.get('STEREO_LAYER_PO') or (str(TREE.parent / 'stereo-layer' / 'po') if (TREE.parent / 'stereo-layer' / 'po').is_dir() else None)
    bad = []
    note = 'layer catalogue not found: the kept sentences stand for it'
    if layer_po:
        live = layer_sentences(layer_po)
        for l in LANGS:
            if live[l] != ref.get(l):
                bad.append(f'layer {l}: {live[l]!r} != kept {ref.get(l)!r} (run --update)')
        note = 'layer catalogue ' + layer_po
    sview = sview_from_tree(a.sview_lang) if a.sview_lang else sview_from_patch(next(PATCHES.glob('sview-*.patch')))
    if a.vlc_po:
        vlc = vlc_from_po(a.vlc_po)
    else:
        vlc = vlc_from_patch(a.vlc_patch or next(PATCHES.glob('vlc-*.patch')))
    bad += run(ref, sview, vlc)
    if a.self_test:
        drifted = dict(sview); drifted['german'] = (drifted.get('german') or '') + '!'
        if not run(ref, drifted, vlc):
            print('self-test FAILED: a drifted sView wording passed'); return 1
        drifted = dict(vlc); drifted['ja'] = (drifted.get('ja') or '') + '!'
        if not run(ref, sview, drifted):
            print('self-test FAILED: a drifted VLC wording passed'); return 1
        print('self-test ok: a drifted wording fails')
    for b in bad:
        print('DRIFT', b)
    print('wording check:', 'FAILED' if bad else 'ok (%d languages, layer = sView = VLC; %s)' % (len(LANGS), note))
    return 1 if bad else 0


sys.exit(main())
