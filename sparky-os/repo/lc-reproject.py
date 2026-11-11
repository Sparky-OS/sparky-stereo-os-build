#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
"""lc-reproject.py: a published lc1 package, Lean Code projected again by this tree's toolkit at a new version,
from the exact authored payload its HR companion holds, without recompiling (ORDER 311).

A package built with toolkit 0.1.15 or older carries the `#line` directives that renderer wrote into C and C++
(ORDER 303). Its payload is the build's staging tree with the projected files in their lean form; the HR companion
holds every projected file's authored bytes. Putting those back gives the staging tree the build handed to Lean Code,
and this toolkit's `lean.release build-tree` then does what a fresh build's last step does. Steps:
  1. the runtime archive and its companion pass `check-tree` (marker, manifest, payload, md5sums);
  2. every projected file gets its authored bytes back (sha256 checked against the manifest's sha_hr), keeping its
     mode and mtime; the manifest goes, and with it what `package.prepare` added to the control file (the marker,
     `dpkg-stereo (<< 0.1.6)` in Breaks, Installed-Size; md5sums are written again);
  3. the new version: Version, every relation to a sibling (--sibling: a binary of the same source re-versioned with it)
     at the old version (${binary:Version}, ${source:Version}), and the Debian changelog,
     which must be the old source's debian/changelog (gzip -9n, byte for byte) and becomes the new source's;
  4. provenance.sh --tree, then `lean.release build-tree` (projection, its checks, the HR companion, check-debs);
  5. the comparison with the old archive: the same paths, kinds, modes and links; every unprojected file byte for byte
     the same (the changelog excepted); every authored text the same; the `#line` lines the old renderer added to C
     and C++, before and after (after: none beyond the authored text's own).
A payload file that was retained because it was hard-linked cannot be told apart once unpacked: the tool stops.
Usage: lc-reproject.py --version NEW --old-changelog FILE --new-changelog FILE --report OUT.json [--sibling NAME...]
         RUNTIME.deb [HR.deb] OUT
"""
import argparse
import email.utils
import hashlib
import json
import lzma
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lean import package, release  # noqa: E402

TOOL_LINE = re.compile(rb'^#line [0-9]+$', re.M)          # the form lang_c.line_directives wrote (0.1.15 and older)
RELATIONS = ('depends', 'pre-depends', 'recommends', 'suggests', 'enhances', 'breaks', 'conflicts', 'replaces',
             'provides', 'built-using', 'static-built-using')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def gzip9n(data):
    # what dh_compress gives (gzip -9n: no name, no time stamp in the header)
    return subprocess.run(['gzip', '-9n'], input=data, stdout=subprocess.PIPE, check=True).stdout


def unpack(deb, where):
    subprocess.run(['dpkg-deb', '-R', str(deb), str(where)], check=True)
    return package.check_tree(where)


def relink(value, old, new, siblings, changes, key):
    """A relation to a binary package of the same source at the old version (${binary:Version}, ${source:Version})
    names the new one; a relation to another package that happens to name the old version stops the tool."""
    def one(m):
        name, op, ver = m.group(1), m.group(3), m.group(4)
        if ver != old:
            return m.group(0)
        if name not in siblings:
            raise package.Invalid(f'{key}: {name} ({op} {old}) is not a package of this source')
        changes.append(f'{key}: {name} ({op} {old}) -> ({op} {new})')
        return m.group(0).replace(f'({op} {old})', f'({op} {new})').replace(f'({op}{old})', f'({op}{new})')
    return re.sub(r'([a-z0-9][a-z0-9+.-]+)(:[a-z0-9-]+)?\s*\((<<|<=|=|>=|>>)\s*([^)\s]+)\s*\)', one, value)


def edit_control(path, old, new, siblings):
    """Version, the marker's fields and sibling relations; field order and every other line kept."""
    out, changes, key = [], [], None
    for line in path.read_text().splitlines():
        if line and not line[0].isspace():
            key, _, value = line.partition(':')
            low = key.lower()
            value = value.strip()
            if low in (package.FIELD.lower(), 'installed-size'):
                key = None
                continue
            if low == 'version':
                if value != old:
                    raise package.Invalid(f'control version {value} is not {old}')
                line = f'{key}: {new}'
            elif low == 'breaks':
                items = [i.strip() for i in value.split(',') if i.strip()]
                if 'dpkg-stereo (<< 0.1.6)' not in items:
                    raise package.Invalid('Breaks lacks the lc1 entry package.prepare adds')
                items.remove('dpkg-stereo (<< 0.1.6)')
                if not items:
                    key = None
                    continue
                value = ', '.join(items)
                line = f'{key}: {value}'
            elif low == 'source' and '(' in value:
                raise package.Invalid('a binary version apart from its source version needs its own rule')
            if low in RELATIONS:
                line = f'{key}: ' + relink(value, old, new, siblings, changes, key)
            out.append(line)
        elif key is not None:
            if key.lower() in RELATIONS and old in line:
                raise package.Invalid(f'{key}: a folded relation field naming {old} needs its own rule')
            out.append(line)
    path.write_text('\n'.join(out) + '\n')
    return changes


def changelog_date(text):
    m = re.search(r'^ -- .*?>  (.+)$', text, re.M)
    return int(email.utils.parsedate_to_datetime(m.group(1)).timestamp())


def count_tool_lines(data):
    return len(TOOL_LINE.findall(data))


def payload_rows(obj, manifest):
    return {r['path']: r for r in obj['files'] if r['path'] != manifest}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--version', required=True)
    ap.add_argument('--old-changelog', required=True, type=Path)
    ap.add_argument('--new-changelog', required=True, type=Path)
    ap.add_argument('--report', required=True, type=Path)
    ap.add_argument('--sibling', action='append', default=[], help='a binary package of the same source, re-versioned too')
    ap.add_argument('--work', type=Path, help='scratch folder (default: beside OUT)')
    ap.add_argument('archives', nargs='+')
    args = ap.parse_args()
    *debs, out = args.archives
    out = Path(out)
    if len(debs) not in (1, 2):
        ap.error('RUNTIME.deb [HR.deb] OUT')
    out.mkdir(parents=True, exist_ok=True)
    new = args.version
    old_cl, new_cl = args.old_changelog.read_bytes(), args.new_changelog.read_bytes()
    report = {'runtime': os.path.basename(debs[0]), 'hr': os.path.basename(debs[1]) if len(debs) > 1 else None,
              'toolkit': package.renderer()}
    with tempfile.TemporaryDirectory(prefix='lc-reproject-', dir=args.work or out.parent) as work:
        work = Path(work)
        stage, hrtree = work / 'stage', work / 'hr'
        obj = unpack(debs[0], stage)
        p, v, a = obj['package'], obj['version'], obj['architecture']
        mp = package.manifest_path(p, a)
        report.update(package=p, old_version=v, new_version=new, architecture=a,
                      old_renderer=obj['renderer']['identity'])
        if subprocess.run(['dpkg', '--compare-versions', new, 'gt', v]).returncode:
            raise package.Invalid(f'{new} does not advance {v}')
        rows = payload_rows(obj, mp)
        if any(r['reason'] == 'hardlinked payload: retained' for r in rows.values()):
            raise package.Invalid('hard-linked payload: the unpacked archive cannot reproduce the staging tree; rebuild')
        projected = {path: r for path, r in rows.items() if r['status'] == 'projected'}
        if not projected and len(debs) > 1:
            raise package.Invalid(f'{p} has no projected file and no HR companion; none is expected')
        old_lean = {}
        if projected:
            if len(debs) < 2:
                raise package.Invalid(f'{p} has {len(projected)} projected files and no HR companion was given')
            hobj = unpack(debs[1], hrtree)
            if (hobj['package'], hobj['version'], hobj['architecture']) != (obj['hr_package'], v, a):
                raise package.Invalid('the HR companion is not this package version\'s')
            for path, r in projected.items():
                target = stage / path[1:]
                old_lean[path] = target.read_bytes()
                data = lzma.decompress((hrtree / package.hr_path(p, a, r['sha_hr'])[1:]).read_bytes())
                if sha256(data) != r['sha_hr'] or len(data) != r['bytes_hr']:
                    raise package.Invalid(f'{path}: the HR text is not the authored text the manifest names')
                st = target.lstat()
                target.write_bytes(data)
                os.utime(target, ns=(st.st_atime_ns, st.st_mtime_ns))
        (stage / mp[1:]).unlink()
        d = (stage / mp[1:]).parent
        while d != stage / 'usr/share' and not any(d.iterdir()):
            d.rmdir()
            d = d.parent
        report['relations'] = edit_control(stage / 'DEBIAN/control', v, new, set(args.sibling))
        (stage / 'DEBIAN/md5sums').unlink()
        cl = stage / f'usr/share/doc/{p}/changelog.Debian.gz'
        cl_path = f'/usr/share/doc/{p}/changelog.Debian.gz'
        if cl.is_symlink() or not cl.exists():
            report['changelog'] = 'link or none: ' + (os.readlink(cl) if cl.is_symlink() else 'none')
        else:
            if cl.read_bytes() != gzip9n(old_cl):
                raise package.Invalid(f'{cl}: not the old source changelog compressed as dh_compress does')
            mode = cl.stat().st_mode
            cl.write_bytes(gzip9n(new_cl))
            os.chmod(cl, mode & 0o7777)
            t = changelog_date(new_cl.decode())
            os.utime(cl, (t, t))
            report['changelog'] = 'replaced by the new source changelog'
        # where else the old version is written: kept as built (maintainer scripts name the version their source names)
        report['old_version_elsewhere'] = sorted(
            str(f.relative_to(stage)) for f in stage.rglob('*')
            if f.is_file() and not f.is_symlink() and f != cl and f.name != 'control'
            and v.encode() in f.read_bytes())
        subprocess.run(['bash', str(HERE / 'provenance.sh'), '--tree', str(stage)], check=True)
        built = work / 'built'
        release.build_tree(stage, built)
        names = sorted(n.name for n in built.glob('*.deb'))
        report['built'] = names
        nobj_dir = work / 'new'
        nobj = unpack(built / f'{p}_{new.split(":", 1)[-1]}_{a}.deb', nobj_dir)
        nrows = payload_rows(nobj, mp)
        if set(nrows) != set(rows):
            raise package.Invalid(f'payload paths differ: {sorted(set(nrows) ^ set(rows))[:10]}')
        stats = dict(files=len(rows), projected_old=len(projected),
                     projected_new=sum(1 for r in nrows.values() if r['status'] == 'projected'),
                     c_projected_old=sum(1 for r in projected.values() if r['handler'] == 'c'),
                     c_projected_new=sum(1 for r in nrows.values() if r['status'] == 'projected' and r['handler'] == 'c'),
                     tool_line_old=0, tool_line_new=0, author_line=0, c_files_with_tool_line_old=0,
                     same_lean_other_formats=0, changed_lean_other_formats=[], newly_projected=[], no_longer_projected=[])
        for path, r in rows.items():
            n = nrows[path]
            if (r['kind'], r['mode'], r.get('target')) != (n['kind'], n['mode'], n.get('target')):
                raise package.Invalid(f'{path}: kind, mode or link target changed')
            if r['kind'] != 'file':
                continue
            authored = r.get('sha_hr', r['sha256'])
            if n.get('sha_hr', n['sha256']) != authored and path != cl_path:
                raise package.Invalid(f'{path}: authored text changed')
            if r['status'] == 'projected' and n['status'] != 'projected':
                stats['no_longer_projected'].append((path, n['reason']))
            if r['status'] != 'projected' and n['status'] == 'projected':
                stats['newly_projected'].append((path, n['handler']))
            new_bytes = (nobj_dir / path[1:]).read_bytes()
            if r['status'] == 'projected' and r['handler'] == 'c':
                hr = (stage / path[1:]).read_bytes()
                base = count_tool_lines(hr)
                stats['author_line'] += base
                old_added = count_tool_lines(old_lean[path]) - base
                stats['tool_line_old'] += old_added
                stats['c_files_with_tool_line_old'] += old_added > 0
                stats['tool_line_new'] += count_tool_lines(new_bytes) - base
            elif r['status'] == 'projected' and n['status'] == 'projected':
                if sha256(old_lean[path]) == n['sha256']:
                    stats['same_lean_other_formats'] += 1
                else:
                    stats['changed_lean_other_formats'].append(path)
            elif r['status'] != 'projected' and n['status'] != 'projected' and r['sha256'] != n['sha256'] \
                    and path != cl_path:
                raise package.Invalid(f'{path}: an unprojected file changed')
        checks = {}
        for r in nrows.values():
            if r['status'] == 'projected' and r['handler'] == 'c':
                checks[r['check']] = checks.get(r['check'], 0) + 1
        stats['c_checks'] = checks
        report['stats'] = stats
        if stats['tool_line_new']:
            raise package.Invalid(f'{stats["tool_line_new"]} #line lines beyond the authored text after projection')
        for name in names:
            dest = out / name
            if dest.exists():
                raise package.Invalid(f'{dest} exists')
            shutil.copyfile(built / name, dest)
            os.chmod(dest, 0o644)
            report.setdefault('sha256', {})[name] = package.file_hash(dest)
    args.report.write_text(json.dumps(report, indent=1, sort_keys=True) + '\n')
    print(json.dumps({k: report[k] for k in ('package', 'new_version', 'built')}), json.dumps(report['stats']['c_checks']))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        sys.exit(f'lc-reproject: {exc}')
