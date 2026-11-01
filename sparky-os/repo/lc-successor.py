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
Usage: lc-successor.py --next NEXT --item TEXT [--item TEXT...] OLD.dsc OUT
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
    body = '\n'.join(textwrap.fill(i, width=79, initial_indent='  * ', subsequent_indent='    ') for i in items)
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--next', required=True)
    ap.add_argument('--item', action='append', required=True)
    ap.add_argument('--work', type=Path)
    ap.add_argument('dsc', type=Path)
    ap.add_argument('out', type=Path)
    args = ap.parse_args()
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
        if not version.endswith('+lc1'):
            raise ValueError(f'{version}: not a +lc1 source')
        # the upstream files are only read from here on: linked, not copied (a kernel tree is 1.5 GB); debian/ is written
        shutil.copytree(old, new, symlinks=True, copy_function=os.link, ignore=lambda d, names: ['debian'] if Path(d) == old else [])
        shutil.copytree(old / 'debian', new / 'debian', symlinks=True)
        plan = new / 'debian/sparky-lean-preserve.json'
        preserve = list(json.loads(plan.read_text()).items()) if plan.exists() else []
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
        if subprocess.run(['dpkg', '--compare-versions', args.next, 'gt', plain]).returncode:
            raise ValueError(f'{args.next} does not advance {plain}')
        changelog = new / 'debian/changelog'
        changelog.write_text(entry(name, args.next, args.item) + changelog.read_text())
        env = new / 'debian/kernel-build.env'
        if env.exists():
            text = env.read_text()
            line = f'PACKAGE_VERSION={version}\n'
            if text.count(line) != 1:
                raise ValueError('debian/kernel-build.env does not record the published version')
            env.write_text(text.replace(line, f'PACKAGE_VERSION={args.next}+lc1\n'))
        debian_prepare.prepare(new, args.next + '+lc1', HERE.parent, preserve_sources=preserve)
        if plan.exists() or (old / 'debian/sparky-lean-preserve.json').exists():
            if plan.read_bytes() != (old / 'debian/sparky-lean-preserve.json').read_bytes():
                raise ValueError('the source-consumer plan changed')
        changed = sorted(tree_diff(old, new))
        allowed = {'debian/changelog', 'debian/kernel-build.env'}
        if mode:
            if (new / 'debian/control').read_text() != moved:
                raise ValueError('debian/control differs beyond the place of the six build dependencies')
            allowed.add('debian/control')
        toolkit = [p for p in changed if p.startswith('debian/sparky-lean-toolkit/')]
        other = [p for p in changed if p not in allowed and p not in toolkit]
        if other:
            raise ValueError(f'the new source differs beyond its changelog and toolkit: {other}')
        # the orig tarball (and its signature) beside the new tree, as dpkg-source -b wants them
        for f in dsc.parent.glob(f'{name}_*.orig*'):
            os.symlink(f, work / f.name)
        subprocess.run(['dpkg-source', '-b', 'new'], cwd=work, check=True, stdout=subprocess.DEVNULL)
        new_version = args.next + '+lc1'
        stem = f'{name}_{new_version.split(":", 1)[-1]}'
        made = sorted(p.name for p in work.glob(stem + '.*'))
        for n in made:
            if (out / n).exists():
                raise ValueError(f'{out / n} exists')
            shutil.copyfile(work / n, out / n)
        shutil.copyfile(changelog, out / f'{stem}.changelog')
        shutil.copyfile(old / 'debian/changelog', out / f'{name}_{version.split(":", 1)[-1]}.changelog')
        report = {'source': name, 'old': version, 'new': new_version, 'files': made,
                  'changed': [p for p in changed if p not in toolkit], 'toolkit_files_changed': len(toolkit),
                  'preserve_patterns': len(preserve), 'plain_from_lc': mode}
        (out / f'{stem}.successor.json').write_text(json.dumps(report, indent=1) + '\n')
        print(json.dumps(report))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        sys.exit(f'lc-successor: {exc}')
