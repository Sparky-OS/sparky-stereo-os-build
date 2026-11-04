#!/usr/bin/python3 -I
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
"""translations-shipped.py [--repo DIR] [--cohort LIST] [STAGE_DIR ...]

For every *.po.patch in sparky-os/translations, finds the newest built package of its source and fails on any
msgid the patch adds that the package's catalogues lack, naming the patch, the language and the string.

A patch that no series names never ships (dpkg-source(1), debian/patches/series: "lists all patches that have to be
applied"); this test reads what the built packages carry, so it catches a patch no build applied.

Where it looks, newest version wins and the debs of that exact version found in any of the places are joined:
  1. the stage folders given on the command line,
  2. the cohort list (default /K3D/partners/round-next/cohort.list), one .deb path per line,
  3. the live repository (default: readlink -f /var/tmp/sparky-repo-current), its pool/*/*/<source>/ folders.
A catalogue is read with msgunfmt from usr/share/locale/<lang>/LC_MESSAGES/<domain>.mo in the amd64 and all debs.
The msgctxt, the msgid and the msgstr must all be those the patch adds.

  translations-shipped.py --gettext PATCH...
instead asks glibc's gettext in the running system, one real locale per language (generate each with
localedef -i de_DE -f UTF-8 de_DE.UTF-8; the C and C.UTF-8 locales translate nothing, whatever LANGUAGE says),
and requires every translation to be there, to be the patch's, and to differ from the English unless the patch itself keeps
the English (a website's name, a bare "%1:"). Run it where the packages are installed.

Exit 0: every added msgid is shipped. Exit 1: some are not. Exit 2: a package or a patch could not be read."""
import argparse
import ctypes
import locale
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TRANSLATIONS = Path(__file__).resolve().parent.parent / 'translations'

# patch -> (source package, gettext domain for patches that name flat po/<lang>.po files[, folder of the catalogues
# when it is not usr/share/locale: VLC Stereo keeps its own under usr/share/vlc-stereo/locale])
SOURCES = {
    'command-not-found-messages.po.patch': ('command-not-found', 'command-not-found'),
    'discover-backend-split.po.patch': ('plasma-discover', None),
    'kalgebra-stereo3d.po.patch': ('kalgebra', None),
    'kalzium-stereo3d.po.patch': ('kalzium', None),
    'kf6-kfilemetadata-stereo3d.po.patch': ('kf6-kfilemetadata', None),
    'kf6-kio-gpu-launch.po.patch': ('kf6-kio', None),
    'kinfocenter-stereo3d.po.patch': ('kinfocenter', None),
    'kscreen-arrangement-view.po.patch': ('kscreen', None),
    'kscreen-dp-frame-sequential.po.patch': ('kscreen', None),
    'kscreenlocker-wallpaper-cost.po.patch': ('kscreenlocker', None),
    'kubrick-stereo3d.po.patch': ('kubrick', None),
    'kwin-wallpaper-cost.po.patch': ('kwin', None),
    'plasma-desktop-wallpaper-cost.po.patch': ('plasma-desktop', None),
    'plasma-nm-connectivity-check.po.patch': ('plasma-nm', None),
    'plasma-workspace-recovery.po.patch': ('plasma-workspace', None),
    'plasma-workspace-wallpaper-cost.po.patch': ('plasma-workspace', None),
    'powerdevil-graphics-link.po.patch': ('powerdevil', None),
    'vlc-spatial-video.po.patch': ('vlc', 'vlc', 'usr/share/vlc-stereo/locale'),
}

LOCALES = {'pl': 'pl_PL', 'pt_BR': 'pt_BR', 'fr': 'fr_FR', 'de': 'de_DE', 'ja': 'ja_JP', 'ko': 'ko_KR',
           'zh_CN': 'zh_CN', 'zh_TW': 'zh_TW'}

_UNESCAPE = re.compile(r'\\(["\\nt])')


def unquote(s):
    return _UNESCAPE.sub(lambda m: {'n': '\n', 't': '\t'}.get(m.group(1), m.group(1)), s)


def parse_po_flagged(lines):
    """lines: [(text, added)]. Entries as {(msgctxt or None, msgid): (msgstr, touched)}; plural entries keep msgstr[0..] joined
    by NUL; the header is left out. touched: some line of the entry is one the patch adds."""
    entries = {}
    cur = {}
    field = None
    touched = False

    def flush():
        nonlocal cur, touched
        if 'msgid' in cur and cur['msgid'] != '' and 'msgstr' in cur:
            entries[(cur.get('msgctxt'), cur['msgid'])] = (cur['msgstr'], touched)
        cur = {}
        touched = False

    for line, added in lines:
        if line.startswith('#~'):
            continue
        if line.startswith('#') or not line.strip():
            if not line.strip() or (cur.get('msgstr') is not None):
                flush()
            continue
        m = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[\d+\])?)\s+"(.*)"\s*$', line)
        if m:
            key, val = m.group(1), unquote(m.group(2))
            if key == 'msgctxt' and 'msgid' in cur:
                flush()
            if key == 'msgid' and 'msgstr' in cur:
                flush()
            touched = touched or added
            if key.startswith('msgstr['):
                cur['msgstr'] = cur.get('msgstr', '') + ('\0' if cur.get('msgstr') is not None else '') + val
                field = 'msgstr'
            else:
                cur[key] = val
                field = key
            continue
        m = re.match(r'^"(.*)"\s*$', line)
        if m and field:
            touched = touched or added
            cur[field] = cur[field] + unquote(m.group(1))
    flush()
    return entries


def parse_po(text):
    """{(msgctxt or None, msgid): msgstr} of a whole catalogue."""
    return {k: v[0] for k, v in parse_po_flagged([(l, False) for l in text.split('\n')]).items()}


def added_entries(patch):
    """{(lang, domain): {(msgctxt, msgid): msgstr}} for the entries the patch adds or fills in: the post-image of each hunk
    (context and added lines), keeping the entries with at least one added line."""
    flat_domain = (SOURCES.get(patch.name) or (None, None))[1]
    lines = {}
    cur = None
    in_hunk = False
    for line in patch.read_text(encoding='utf-8').split('\n'):
        m = re.match(r'^\+\+\+ b/po/([^/]+)/([^/]+)\.po$', line)
        if m:
            cur = (m.group(1), m.group(2))
            lines.setdefault(cur, [])
            in_hunk = False
            continue
        m = re.match(r'^\+\+\+ b/po/([^/]+)\.po$', line)
        if m:
            if flat_domain is None:
                raise SystemExit(f'{patch.name}: flat file {line}, and SOURCES names no domain for it')
            cur = (m.group(1), flat_domain)
            lines.setdefault(cur, [])
            in_hunk = False
            continue
        if line.startswith('diff '):
            cur = None
            in_hunk = False
            continue
        if cur is None:
            continue
        if line.startswith('@@'):
            in_hunk = True
            lines[cur].append(('', False))
            continue
        if not in_hunk:
            continue
        if line.startswith('+'):
            lines[cur].append((line[1:], True))
        elif line.startswith(' '):
            lines[cur].append((line[1:], False))
        elif line == '':
            lines[cur].append(('', False))
    added = {}
    for key, ls in lines.items():
        entries = parse_po_flagged(ls)
        added[key] = {k: v[0] for k, v in entries.items() if v[1] and v[0].replace('\0', '') != ''}
    return added


def _split_version(v):
    epoch = 0
    if ':' in v:
        e, v = v.split(':', 1)
        epoch = int(e)
    rev = ''
    if '-' in v:
        v, rev = v.rsplit('-', 1)
    return epoch, v, rev


def _cmp_part(a, b):
    def order(c):
        if c == '~':
            return -1
        if c.isdigit():
            return 0
        if c.isalpha():
            return ord(c)
        return ord(c) + 256

    while a or b:
        da = re.match(r'\D*', a).group(0)
        db = re.match(r'\D*', b).group(0)
        i = 0
        while i < max(len(da), len(db)):
            ca = order(da[i]) if i < len(da) else 0
            cb = order(db[i]) if i < len(db) else 0
            if ca != cb:
                return -1 if ca < cb else 1
            i += 1
        a, b = a[len(da):], b[len(db):]
        na = re.match(r'\d*', a).group(0)
        nb = re.match(r'\d*', b).group(0)
        a, b = a[len(na):], b[len(nb):]
        if int(na or 0) != int(nb or 0):
            return -1 if int(na or 0) < int(nb or 0) else 1
    return 0


def compare_versions(x, y):
    ex, vx, rx = _split_version(x)
    ey, vy, ry = _split_version(y)
    if ex != ey:
        return -1 if ex < ey else 1
    return _cmp_part(vx, vy) or _cmp_part(rx, ry)


class Version(str):
    def __lt__(self, other):
        return compare_versions(self, other) < 0

    def __gt__(self, other):
        return compare_versions(self, other) > 0


_FIELDS = {}


def deb_fields(deb):
    if deb in _FIELDS:
        return _FIELDS[deb]
    _FIELDS[deb] = _deb_fields(deb)
    return _FIELDS[deb]


def _deb_fields(deb):
    out = subprocess.run(['dpkg-deb', '-f', str(deb), 'Package', 'Source', 'Version', 'Architecture'],
                         capture_output=True, text=True)
    if out.returncode:
        raise SystemExit(f'{deb}: dpkg-deb -f failed: {out.stderr.strip()}')
    f = dict(l.split(': ', 1) for l in out.stdout.strip().split('\n') if ': ' in l)
    source = f.get('Source', f['Package']).split(' ')[0]
    return source, f['Version'], f['Architecture'], f['Package']


def candidates(source, stages, cohort_debs, repo):
    """{version: [deb paths]} of the amd64 and all debs of the source, across the three places."""
    found = {}
    paths = []
    for s in stages:
        paths += sorted(Path(s).glob('*.deb'))
    paths += [p for p in cohort_debs if p.is_file()]
    if repo:
        for d in Path(repo).glob(f'pool/*/*/{source}'):
            paths += sorted(d.glob('*.deb'))
    seen = set()
    for p in paths:
        if p.name in seen or '-dbgsym_' in p.name or '-lc-hr_' in p.name:
            continue
        # the file name is binary_version_arch.deb; read the control only for plausible files
        seen.add(p.name)
        src, ver, arch, pkg = deb_fields(p)
        if src != source or arch not in ('amd64', 'all'):
            continue
        found.setdefault(Version(ver), []).append(p)
    return found


def newest(found):
    return max(found, key=lambda v: _Key(v))


class _Key:
    def __init__(self, v):
        self.v = v

    def __lt__(self, o):
        return compare_versions(self.v, o.v) < 0


def catalogue(debs, wanted_domains, root_dir='usr/share/locale'):
    """{(lang, domain): {(msgctxt, msgid): msgstr}} read with msgunfmt from the debs' .mo files."""
    got = {}
    with tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')) as t:
        for i, deb in enumerate(debs):
            root = Path(t) / str(i)
            root.mkdir()
            tar = subprocess.Popen(['dpkg-deb', '--fsys-tarfile', str(deb)], stdout=subprocess.PIPE)
            subprocess.run(['tar', '-x', '-C', str(root), '--wildcards', '*/LC_MESSAGES/*.mo'],
                           stdin=tar.stdout, stderr=subprocess.DEVNULL)
            tar.stdout.close()
            tar.wait()
            for mo in root.glob(root_dir + '/*/LC_MESSAGES/*.mo'):
                lang, dom = mo.parts[-3], mo.stem
                if dom not in wanted_domains:
                    continue
                po = subprocess.run(['msgunfmt', '--no-wrap', str(mo)], capture_output=True, text=True)
                if po.returncode:
                    raise SystemExit(f'{deb.name}: msgunfmt {lang}/{dom}.mo failed: {po.stderr.strip()}')
                got[(lang, dom)] = parse_po(po.stdout)
    return got


def locale_root(patch):
    spec = SOURCES.get(patch.name, ())
    return spec[2] if len(spec) > 2 else 'usr/share/locale'


def short(ctxt, msgid):
    s = msgid.replace('\n', '\\n')
    s = s if len(s) <= 70 else s[:67] + '...'
    return (f'[{ctxt}] ' if ctxt else '') + s


def check_packages(args):
    cohort_debs = []
    if args.cohort and Path(args.cohort).is_file():
        cohort_debs = [Path(l.strip()) for l in Path(args.cohort).read_text().split('\n')
                       if l.strip() and not l.startswith('#')]
    repo = args.repo or os.path.realpath('/var/tmp/sparky-repo-current')
    failed = 0
    unreadable = 0
    for patch in sorted(TRANSLATIONS.glob('*.po.patch')):
        if patch.name not in SOURCES:
            print(f'ERROR {patch.name}: not in SOURCES, so no package to look in')
            unreadable += 1
            continue
        source = SOURCES[patch.name][0]
        added = added_entries(patch)
        found = candidates(source, args.stages, cohort_debs, repo)
        if not found:
            print(f'ERROR {patch.name}: no built package of source {source}')
            unreadable += 1
            continue
        version = newest(found)
        debs = found[version]
        have = catalogue(debs, {d for (_, d) in added}, locale_root(patch))
        total = sum(len(v) for v in added.values())
        bad = 0
        for (lang, dom), entries in sorted(added.items()):
            cat = have.get((lang, dom))
            for (ctxt, msgid), msgstr in entries.items():
                if cat is None:
                    reason = f'{lang}/{dom}.mo is in no deb of {source} {version}'
                elif (ctxt, msgid) not in cat:
                    reason = f'msgid missing from {lang}/{dom}.mo of {source} {version}'
                elif cat[(ctxt, msgid)] != msgstr:
                    reason = f'msgstr differs in {lang}/{dom}.mo of {source} {version}'
                else:
                    continue
                print(f'FAIL {patch.name} {lang} {dom}: {short(ctxt, msgid)}: {reason}')
                bad += 1
        failed += bad
        print(f'{"FAIL" if bad else "ok  "} {patch.name}: {total - bad}/{total} added strings in {source} {version}')
    if unreadable:
        return 2
    return 1 if failed else 0


def check_gettext(args):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.dgettext.restype = ctypes.c_char_p
    libc.dgettext.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    libc.bindtextdomain.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    libc.bind_textdomain_codeset.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    failed = 0
    for name in args.patches:
        patch = Path(name)
        added = added_entries(patch)
        total = bad = 0
        for (lang, dom), entries in sorted(added.items()):
            loc = LOCALES.get(lang, lang) + '.UTF-8'
            try:
                locale.setlocale(locale.LC_ALL, loc)
            except locale.Error:
                print(f'ERROR locale {loc} is not generated (localedef -i {LOCALES.get(lang, lang)} -f UTF-8 {loc})')
                return 2
            libc.bindtextdomain(dom.encode(), ('/' + locale_root(patch)).encode())
            libc.bind_textdomain_codeset(dom.encode(), b'UTF-8')
            for (ctxt, msgid), msgstr in entries.items():
                total += 1
                key = (ctxt + '\x04' + msgid) if ctxt else msgid
                got = libc.dgettext(dom.encode(), key.encode()).decode()
                if got == key:
                    print(f'FAIL {patch.name} {lang} {dom} under {loc}: {short(ctxt, msgid)}: not translated')
                    bad += 1
                elif got != msgstr.split('\0')[0]:
                    print(f'FAIL {patch.name} {lang} {dom} under {loc}: {short(ctxt, msgid)}: the translation is not the patch\'s')
                    bad += 1
                elif got == msgid and msgstr.split('\0')[0] != msgid:
                    print(f'FAIL {patch.name} {lang} {dom} under {loc}: {short(ctxt, msgid)}: translation equals the English')
                    bad += 1
        failed += bad
        print(f'{"FAIL" if bad else "ok  "} {patch.name}: {total - bad}/{total} found through gettext')
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('stages', nargs='*', help='stage folders holding built .deb files')
    ap.add_argument('--cohort', default='/K3D/partners/round-next/cohort.list')
    ap.add_argument('--repo', help='the live repository (default: /var/tmp/sparky-repo-current)')
    ap.add_argument('--gettext', action='store_true', help='the arguments are patch files; ask glibc gettext')
    args = ap.parse_args()
    if args.gettext:
        args.patches = args.stages
        return check_gettext(args)
    return check_packages(args)


if __name__ == '__main__':
    sys.exit(main())
