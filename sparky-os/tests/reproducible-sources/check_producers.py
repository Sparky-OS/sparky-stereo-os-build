#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""ORDER 421b: no script that writes a source package is dated by the clock, or packs debian/ as the checkout left it.

For every tracked script under sparky-os, kernel and tools that writes a changelog entry or packs a source:
- the clock is not read for a date (formatdate, datetime.now, `date -R`, a dch without --date);
- a file that packs a source (dpkg-source -b, dpkg-buildpackage without -b/-B) normalizes its tree first (repo/reproducible.py).
ORDER 435: every script that runs repo/plain-from-lc.py says what becomes of the source's Lean Code preserve plan: --drop-plan (the
caller carries it itself, as repo/lc-successor.py does) or --save-plan FILE, and a script that saves a plan hands it back to
lean.debian_prepare (--preserve-plan FILE, or carried_plan=).
Files that the 421 inventory listed by pattern but that write no source are named below with the reason.
Usage: check_producers.py [BUILD_REPO_ROOT]     Exit 0 clean, 1 with every finding named.
"""
import re
import subprocess
import sys
from pathlib import Path

NOT_SOURCE = {
    'sparky-os/release/check-repository-dependencies.py': 'dates the Release file of a throw-away repository, not a source',
    'sparky-os/release/make-provenance.py': 'writes an attestation about builds, not a source',
    'sparky-os/repo/plain-from-lc.py': 'edits a tree and writes no entry or date; its caller packs it',
    'sparky-os/packages/stereo-declare/build-in-container.sh': 'builds the extracted .dsc of prepare-source.sh, which dates and packs the source',
    'sparky-os/repo/reproducible.py': 'the engine itself',
    'sparky-os/repo/build-provenance.sh': 'the engine itself',
}
CLOCK = [
    (re.compile(r'formatdate\('), 'email.utils.formatdate reads the clock'),
    (re.compile(r'datetime\.(utc)?now\('), 'datetime.now reads the clock'),
    (re.compile(r'(?<![\w-])date\s+(-R|-u\s+-R|--rfc-2822|-Iseconds)(?![\w-])'), '`date -R` reads the clock'),
]
PACK = re.compile(r"""dpkg-source -b\b|dpkg-source['"],\s*['"]-b['"]|dpkg-buildpackage\b(?![^\n]*\s-[a-zA-Z]*[bBAF]\b)""")
MAKES_TREE = re.compile(r'\bdch\b|debian_prepare|lean\.standalone|\s-S\b')   # a build of a tree somebody else prepared packs no source of its own
DCH_SHELL = re.compile(r'(?:^|[;&|(]\s*|&&\s*)dch\s')
NORMALIZE = re.compile(r'normalize-tree|normalize_tree|\bnormalize\b|reproducible\.normalize|reproducible\.pack')


def tracked(root):
    out = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z'], text=True).split('\0')
    for rel in out:
        if rel.endswith(('.sh', '.py')) and rel.startswith(('sparky-os/', 'kernel/', 'tools/')) and '/tests/' not in rel \
                and '/translations/' not in rel and '/node_modules/' not in rel:
            yield rel


def findings(rel, text):
    found = []
    writes = bool(re.search(r'\bdch\b|changelog|dpkg-buildpackage', text) or PACK.search(text))
    if not writes:
        return found
    lines = text.splitlines()
    for number, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if stripped.startswith('#'):
            continue
        for pattern, why in CLOCK:
            if pattern.search(line) and ('changelog' in text or 'dch' in text):
                found.append(f'{rel}:{number}: {why}')
        if DCH_SHELL.search(line) and 'print(' not in line and '--date' not in line and not re.search(r'^\s*dch\s+--?(help|version)\b', line):
            found.append(f'{rel}:{number}: dch without --date')
        if re.search(r"\['dch',", line) and "'--date'" not in line:
            found.append(f'{rel}:{number}: dch without --date')
    packs, in_doc = [], False
    for n, l in enumerate(lines, 1):
        was = in_doc
        in_doc ^= l.count('"""') % 2 == 1
        if was or in_doc or l.lstrip().startswith('#') or 'parsechangelog' in l:
            continue
        m = PACK.search(l)
        if m and (m.group(0).startswith('dpkg-source') or MAKES_TREE.search(text)):
            packs.append(n)
    if packs and not NORMALIZE.search(text):
        found.append(f'{rel}:{packs[0]}: packs a source without normalizing its tree (repo/reproducible.py normalize-tree)')
    return found


PLAIN_CALL = re.compile(r'plain-from-lc\.py')


def plan_findings(rel, text):
    """ORDER 435: a plain-from-lc.py call names --save-plan or --drop-plan; a saved plan reaches lean.debian_prepare."""
    found, calls, in_doc = [], [], False
    for n, l in enumerate(text.splitlines(), 1):
        was = in_doc
        in_doc ^= l.count('"""') % 2 == 1
        if was or in_doc or l.lstrip().startswith('#') or not PLAIN_CALL.search(l):
            continue
        calls.append(n)
        if '--save-plan' not in l and '--drop-plan' not in l:
            found.append(f'{rel}:{n}: plain-from-lc.py without --save-plan or --drop-plan: the Lean Code preserve plan would be dropped')
    if calls and '--save-plan' in text and not re.search(r'--preserve-plan|carried_plan', text):
        found.append(f'{rel}:{calls[0]}: --save-plan without --preserve-plan (or carried_plan=): the saved plan never reaches lean.debian_prepare')
    return found


def main(root):
    root = Path(root)
    problems, checked = [], 0
    for rel in tracked(root):
        text = (root / rel).read_text(errors='replace')
        if rel != 'sparky-os/repo/plain-from-lc.py':
            problems += plan_findings(rel, text)
        if rel in NOT_SOURCE:
            continue
        found = findings(rel, text)
        if re.search(r'\bdch\b|changelog|dpkg-buildpackage', text) or PACK.search(text):
            checked += 1
        problems += found
    print(f'{checked} source-writing scripts checked, {len(problems)} findings')
    for p in problems:
        print('  ' + p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[3]))
