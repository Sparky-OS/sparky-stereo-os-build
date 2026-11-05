#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
"""lc-successor.py: the next +lc1 source of a published +lc1 source, with this tree's Lean Code toolkit and no other
change, made the way every recipe makes its next version (ORDER 311): the published source unpacked
(dpkg-source -x), plain-from-lc.py turns it back into its plain source, a plain entry at the recipe's next number
says why (no source change), lean.debian_prepare adds this toolkit at NEXT+lc1 with the source-consumer plan the
published source retained, and dpkg-source -b packs it next to the same orig tarball.
The kernel recipe also records its package version in debian/kernel-build.env (kernel/lean/prepare.py); that line
follows. Any other difference between the published and the new source stops the tool.
--in-place: for a published source whose shape plain-from-lc.py does not know (the six lc1 build dependencies inside a
folded Build-Depends, an edition entry that is also the Lean Code entry, the 19 October adapter's debian/sparky-lean):
the published debian/ directory stays as it is but for its toolkit, replaced by this tree's (the files debian_prepare
copies), and its changelog, which gains the plain entry for NEXT and the Lean Code entry for NEXT+lc1 on top (one entry,
NEXT, for a source whose versions carry no +lc1). Only the changelog and the toolkit may differ.
--overlay DIR (with --in-place): the files of DIR, by their place under debian/, replace or join the published ones
(a recipe that adds patches: debian/patches/NNNN-name.patch, the whole new debian/patches/series, and the symbols file
or control it changes); nothing else of debian/ but the toolkit and the changelog may differ, and the report lists them.
--depends OLD NEW (with --in-place): the one dependency text of debian/control the recipe changes, each exactly once, and nothing else of
debian/ but the toolkit and the changelog (ORDER 399: flightgear's Depends names the FlightGear data downloader).
--preserve PATTERN REASON: the next version keeps one more file as authored for a source consumer the recipe names
(lean.debian_prepare --preserve-source): the published plan stays as it is and gains this pattern, nothing else.
--recipe DIR: the next version carries a recipe change: DIR is the recipe's debian/ directory, whose changelog is the
published plain changelog with the new version's entry (or entries) on top; it replaces the plain debian/ directory, and
the new version is its top entry. Only debian/ may differ then; the tool lists what did.
Usage: lc-successor.py --next NEXT --item TEXT [--item TEXT...] OLD.dsc OUT
       lc-successor.py --recipe DIR OLD.dsc OUT
  NEXT: the plain version (7.3.1-14.1, 615.71.09-2+stereo3d7); the source becomes NEXT+lc1.
  OUT: receives the new .dsc and Debian tarball (the orig tarball is the published one, unchanged).
"""
import argparse
import email.utils
import filecmp
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lean import debian_prepare  # noqa: E402

NAME = 'Daniel Ramos (Capitain Jack)'
MAIL = 'Capitain_Jack@yahoo.com'


def parse(root, field):
    return subprocess.check_output(['dpkg-parsechangelog', '-S', field], cwd=root, text=True).strip()


def entry(name, version, items):
    # whole words only: a name such as dpkg-stereo or a long path is never split across lines
    body = '\n'.join(textwrap.fill(i, width=79, initial_indent='  * ', subsequent_indent='    ',
                                   break_on_hyphens=False, break_long_words=False) for i in items)
    return (f'{name} ({version}) unstable; urgency=medium\n\n{body}\n\n'
            f' -- {NAME} <{MAIL}>  {email.utils.formatdate(localtime=True)}\n\n')


def tree_diff(a, b, rel=Path('.')):
    """Paths that differ between two trees (content, kind or presence)."""
    out = []
    cmp = filecmp.dircmp(a / rel, b / rel)
    out += [str(rel / n) for n in cmp.left_only + cmp.right_only + cmp.funny_files]
    for n in cmp.common_files:
        pa, pb = a / rel / n, b / rel / n
        if pa.is_symlink() or pb.is_symlink():
            if not (pa.is_symlink() and pb.is_symlink() and os.readlink(pa) == os.readlink(pb)):
                out.append(str(rel / n))
        elif pa.read_bytes() != pb.read_bytes() or (pa.stat().st_mode & 0o111) != (pb.stat().st_mode & 0o111):
            out.append(str(rel / n))
    for n in cmp.common_dirs:
        out += tree_diff(a, b, rel / n)
    return out


LEAN_ITEM = ('  * Apply verified native Lean Code before compilation and qualified lc1\n'
             '    payload assembly; retain exact authored source and HR companions.')


def toolkit_files(sparky_os):
    """The files lean.debian_prepare copies into debian/sparky-lean-toolkit, by their place in the source."""
    files = {f'lean/{p.name}': p for p in (sparky_os / 'lean').glob('*.py')}
    files.update({'lean/JvmLexer.java': sparky_os / 'lean/JvmLexer.java', 'lean/ZigTokens.zig': sparky_os / 'lean/ZigTokens.zig',
                  'lean/smoke.tsv': sparky_os / 'lean/smoke.tsv',
                  'provenance.sh': sparky_os / 'repo/provenance.sh', 'LICENSE': sparky_os / 'packages/dpkg-stereo/LICENSE'})
    return files


def in_place(old, new, name, version, nxt, items, depends=(), overlay=None):
    """--in-place: the published debian/ with this tree's toolkit and two new changelog entries; nothing else but the
    dependency texts --depends names (each exactly once in debian/control)."""
    shutil.copytree(old, new, symlinks=True, copy_function=os.link, ignore=lambda d, names: ['debian'] if Path(d) == old else [])
    shutil.copytree(old / 'debian', new / 'debian', symlinks=True)
    rules = (new / 'debian/rules').read_text()
    dirs = set(re.findall(r'PYTHONPATH=\$\(CURDIR\)/debian/([A-Za-z0-9_.-]+) python3 -m lean\.', rules))
    if len(dirs) != 1 or not (new / 'debian' / next(iter(dirs)) / 'lean/__init__.py').is_file():
        raise ValueError(f'debian/rules names no single bundled toolkit: {sorted(dirs)}')
    kit = new / 'debian' / dirs.pop()
    shutil.rmtree(kit)
    for rel, src in toolkit_files(HERE.parent).items():
        (kit / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, kit / rel)
    overlaid = set()
    if overlay:
        for src in sorted(p for p in overlay.rglob('*') if p.is_file()):
            rel = src.relative_to(overlay)
            (new / 'debian' / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, new / 'debian' / rel)
            overlaid.add(str(Path('debian') / rel))
    for before, after in depends:
        control = (new / 'debian/control').read_text()
        if control.count(before) != 1:
            raise ValueError(f'--depends: {before!r} is not exactly once in debian/control')
        (new / 'debian/control').write_text(control.replace(before, after))
    lc = version.endswith('+lc1')
    plain = version[:-len('+lc1')] if lc else version
    if subprocess.run(['dpkg', '--compare-versions', nxt, 'gt', plain]).returncode:
        raise ValueError(f'{nxt} does not advance {plain}')
    changelog = new / 'debian/changelog'
    text = entry(name, nxt, items) + changelog.read_text()
    if lc:
        text = (f'{name} ({nxt}+lc1) UNRELEASED; urgency=medium\n\n{LEAN_ITEM}\n\n'
                f' -- {NAME} <{MAIL}>  {email.utils.formatdate(localtime=True)}\n\n') + text
    changelog.write_text(text)
    changed = sorted(tree_diff(old, new))
    kit_rel = str(kit.relative_to(new)) + '/'
    toolkit = [p for p in changed if p.startswith(kit_rel)]
    allowed = {'debian/changelog'} | ({'debian/control'} if depends else set()) | overlaid
    other = [p for p in changed if p not in allowed and p not in toolkit]
    if other:
        raise ValueError(f'the new source differs beyond its changelog and toolkit: {other}')
    return {'source': name, 'old': version, 'new': nxt + '+lc1' if lc else nxt, 'mode': 'in-place', 'toolkit_dir': kit_rel,
            'changed': [p for p in changed if p not in toolkit], 'toolkit_files_changed': len(toolkit)}


def finish(work, dsc, name, version, new_version, old, out, report):
    """dpkg-source -b next to the published orig tarball; the new .dsc, Debian tarball, both changelogs and the report."""
    for f in dsc.parent.glob(f'{name}_*.orig*'):
        os.symlink(f, work / f.name)
    subprocess.run(['dpkg-source', '-b', 'new'], cwd=work, check=True, stdout=subprocess.DEVNULL)
    stem = f'{name}_{new_version.split(":", 1)[-1]}'
    made = sorted(p.name for p in work.glob(stem + '.*'))
    for n in made:
        if (out / n).exists():
            raise ValueError(f'{out / n} exists')
        shutil.copyfile(work / n, out / n)
    shutil.copyfile(work / 'new/debian/changelog', out / f'{stem}.changelog')
    shutil.copyfile(old / 'debian/changelog', out / f'{name}_{version.split(":", 1)[-1]}.changelog')
    report['files'] = made
    (out / f'{stem}.successor.json').write_text(json.dumps(report, indent=1) + '\n')
    print(json.dumps(report))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--next')
    ap.add_argument('--item', action='append')
    ap.add_argument('--recipe', type=Path, help="the recipe's debian/ directory for the next version")
    ap.add_argument('--depends', nargs=2, action='append', default=[], metavar=('OLD', 'NEW'),
                    help='with --in-place: one text of debian/control replaced by another (a dependency the recipe changes)')
    ap.add_argument('--overlay', type=Path, help='with --in-place: a folder of files for debian/ (patches, series, symbols, control)')
    ap.add_argument('--in-place', action='store_true', help='keep the published debian/ but for its toolkit and changelog')
    ap.add_argument('--preserve', nargs=2, action='append', default=[], metavar=('PATTERN', 'REASON'),
                    help='one more source-consumer pattern for the next version, its reason beside it')
    ap.add_argument('--work', type=Path)
    ap.add_argument('dsc', type=Path)
    ap.add_argument('out', type=Path)
    args = ap.parse_args()
    if not ((args.recipe and not args.next and not args.item and not args.in_place) or (not args.recipe and args.next and args.item)):
        ap.error('either --next and --item (no source change), or --recipe DIR')
    if (args.depends or args.overlay) and not args.in_place:
        ap.error('--depends and --overlay go with --in-place')
    if args.recipe and args.recipe.resolve().name != 'debian':
        ap.error("--recipe names a recipe's debian/ directory")
    dsc = args.dsc.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    os.environ.update(DEBFULLNAME=NAME, DEBEMAIL=MAIL)
    with tempfile.TemporaryDirectory(prefix='lc-successor-', dir=args.work or out.parent) as work:
        work = Path(work)
        subprocess.run(['dpkg-source', '--no-copy', '-x', str(dsc), str(work / 'old')], check=True,
                       stdout=subprocess.DEVNULL)
        old, new = work / 'old', work / 'new'
        name, version = parse(old, 'Source'), parse(old, 'Version')
        if args.in_place:
            if args.recipe:
                raise ValueError('--in-place and --recipe exclude each other')
            report = in_place(old, work / 'new', name, version, args.next, args.item, args.depends,
                              args.overlay.resolve() if args.overlay else None)
            finish(work, dsc, name, version, report['new'], old, out, report)
            return
        if not version.endswith('+lc1'):
            raise ValueError(f'{version}: not a +lc1 source')
        # the upstream files are only read from here on: linked, not copied (a kernel tree is 1.5 GB); debian/ is written
        shutil.copytree(old, new, symlinks=True, copy_function=os.link, ignore=lambda d, names: ['debian'] if Path(d) == old else [])
        shutil.copytree(old / 'debian', new / 'debian', symlinks=True)
        plan = new / 'debian/sparky-lean-preserve.json'
        preserve = list(json.loads(plan.read_text()).items()) if plan.exists() else []
        published_plan = dict(preserve)
        for pattern, reason in args.preserve:
            if pattern in published_plan:
                raise ValueError(f'{pattern}: already in the published source-consumer plan')
            preserve.append((pattern, reason))
        control = (new / 'debian/control').read_text()
        six = 'gcc, node-acorn, nodejs, perl, python3, python3-yaml'
        mode = []
        if f'Build-Depends: {six},' not in control:
            # the 20 October wheel DKMS sources: the six at the end; the next source has them where debian_prepare puts them
            if not re.search(r'^Build-Depends: .*, ' + re.escape(six) + r'\n', control, re.M):
                raise ValueError('the lc1 build dependencies are in no place plain-from-lc.py knows')
            mode = ['--build-depends-at-end']
            moved = re.sub(r'^Build-Depends: (.*), ' + re.escape(six) + r'\n', lambda m: f'Build-Depends: {six}, {m.group(1)}\n',
                           control, flags=re.M)
        subprocess.run([sys.executable, str(HERE / 'plain-from-lc.py'), *mode, str(new)], check=True)
        plain = parse(new, 'Version')
        if plain != version[:-len('+lc1')]:
            raise ValueError(f'plain-from-lc gave {plain}, not {version[:-4]}')
        changelog = new / 'debian/changelog'
        if args.recipe:
            recipe = args.recipe.resolve()
            published = changelog.read_text()
            mine = (recipe / 'changelog').read_text()
            if not mine.endswith('\n\n' + published) or parse(recipe.parent, 'Source') != name:
                raise ValueError("the recipe's changelog does not extend the published plain changelog of this source")
            if (recipe / 'sparky-lean-toolkit').exists() or (recipe / 'sparky-lean-preserve.json').exists():
                raise ValueError('a recipe holds the plain debian/ directory; Lean Code adds the toolkit and the plan')
            args.next = subprocess.check_output(['dpkg-parsechangelog', '-l', str(recipe / 'changelog'), '-S', 'Version'],
                                                text=True).strip()
            shutil.rmtree(new / 'debian')
            shutil.copytree(recipe, new / 'debian', symlinks=True)
        if subprocess.run(['dpkg', '--compare-versions', args.next, 'gt', plain]).returncode:
            raise ValueError(f'{args.next} does not advance {plain}')
        if not args.recipe:
            changelog.write_text(entry(name, args.next, args.item) + changelog.read_text())
        env = new / 'debian/kernel-build.env'
        if env.exists() and not args.recipe:
            text = env.read_text()
            line = f'PACKAGE_VERSION={version}\n'
            if text.count(line) != 1:
                raise ValueError('debian/kernel-build.env does not record the published version')
            env.write_text(text.replace(line, f'PACKAGE_VERSION={args.next}+lc1\n'))
        debian_prepare.prepare(new, args.next + '+lc1', HERE.parent, preserve_sources=preserve)
        if plan.exists() or (old / 'debian/sparky-lean-preserve.json').exists():
            if json.loads(plan.read_text()) != {**published_plan, **dict(args.preserve)}:
                raise ValueError('the source-consumer plan changed beyond the --preserve patterns')
            if not args.preserve and plan.read_bytes() != (old / 'debian/sparky-lean-preserve.json').read_bytes():
                raise ValueError('the source-consumer plan changed')
        changed = sorted(tree_diff(old, new))
        allowed = {'debian/changelog', 'debian/kernel-build.env'} | ({'debian/sparky-lean-preserve.json'} if args.preserve else set())
        if mode:
            if (new / 'debian/control').read_text() != moved:
                raise ValueError('debian/control differs beyond the place of the six build dependencies')
            allowed.add('debian/control')
        toolkit = [p for p in changed if p.startswith('debian/sparky-lean-toolkit/')]
        other = [p for p in changed if p not in allowed and p not in toolkit]
        if args.recipe:
            other = [p for p in other if not p.startswith('debian/')]
        if other:
            raise ValueError(f'the new source differs beyond its changelog and toolkit: {other}')
        report = {'source': name, 'old': version, 'new': args.next + '+lc1', 'recipe': str(args.recipe or ''),
                  'changed': [p for p in changed if p not in toolkit], 'toolkit_files_changed': len(toolkit),
                  'preserve_patterns': len(preserve), 'preserve_added': [p for p, _ in args.preserve], 'plain_from_lc': mode}
        finish(work, dsc, name, version, args.next + '+lc1', old, out, report)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        sys.exit(f'lc-successor: {exc}')
