#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
"""Refuse zram and zswap in what the edition ships: packages and images.

Daniel, 2026-11-02: "do not compress or put anything to run from the RAM regarding swap". The swap is the
Cushion Swap File on disk; no package, image or boot menu of the edition may ship, enable, recommend or depend
on zram (zram-generator configurations, systemd-zram-generator, zram-tools, zramctl set-ups) or zswap
(zswap.enabled=1 on a kernel command line, CONFIG_ZSWAP_DEFAULT_ON=y). Every finding names the file and the
line (a byte offset in a compiled file), and any finding refuses.

  zram-check.py [ROOT] [--also FILE ...]       an image root (default /): its installed packages, the files that
                                               configure boot, swap, modules, units and devices, the maintainer
                                               scripts and the programs; --also adds files outside ROOT (an ISO's
                                               boot menus)
  zram-check.py --debs DEB ... | --debs-file F  packages: their control fields, maintainer scripts and every file
                                               they ship

Exit status: 0 nothing found; 1 refused (a finding, or a file that cannot be read: nothing passes unread);
2 usage. The rules and the clauses they follow are in RULES below.
"""
import argparse
import concurrent.futures
import os
import re
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

# Packages that set up zram swap. Debian: systemd-zram-generator (systemd/zram-generator; its own
# /usr/lib/systemd/zram-generator.conf makes zram0, zram-generator.conf(5)) and zram-tools (zramswap.service,
# /etc/default/zramswap); Ubuntu: zram-config; zram-generator is the upstream name other archives use.
FORBIDDEN = {
    'systemd-zram-generator': "Debian's zram-generator",
    'zram-tools': "Debian's zramswap service",
    'zram-config': "Ubuntu's zram set-up",
    'zram-generator': 'zram-generator',
}
# The fields that install, offer or stand in for a package (Debian Policy 7.2, 7.5). Conflicts, Breaks and
# Replaces are how a package keeps them out, and stay allowed.
PULLING = ('Pre-Depends', 'Depends', 'Recommends', 'Suggests', 'Enhances', 'Provides')

# Never executed and never read as configuration: documentation, manual pages, translations, shell completions,
# and dpkg-stereo's compressed authored copies (the package they belong to is checked itself).
SKIP_PREFIXES = ('usr/share/doc/', 'usr/share/man/', 'usr/share/info/', 'usr/share/locale/', 'usr/share/help/',
                 'usr/share/bash-completion/', 'usr/share/zsh/', 'usr/share/fish/', 'usr/share/dpkg-stereo/hr/')
TEXT_LIMIT = 4 << 20
BINARY_LIMIT = 256 << 20
MENTION = re.compile(r'zram|zswap', re.I)

# kstrtobool (lib/kstrtox.c, Linux 7.3): a value starting with e, y, t or 1, or "on", is true; param_set_bool
# (kernel/params.c) takes a parameter given without "=" as true. zram-generator.conf(5): systemd.zram[=0|1],
# "a true argument (or no argument)" makes zram0.
TRUE_VALUE = r'(?:[eEyYtT1]|[oO][nN])[^\s"\';]*'
END = r'(?=[\s"\';]|$)'
CMDLINE_ZSWAP = re.compile(r'(?<![\w.-])zswap\.enabled(?:=' + TRUE_VALUE + r')?' + END)
CMDLINE_ZRAM = re.compile(r'(?<![\w.-])systemd\.zram(?:=' + TRUE_VALUE + r')?' + END)
WRITE = re.compile(r'>|\btee\b|^\s*w\+?\s|\.write|write_text|writeValue')
FALSE_WRITE = re.compile(r'(?:echo|printf)\s+(?:-n\s+)?["\']?(?:0|[nNfF]\w*|off)["\']?\s*>|\s(?:0|[nN])\s*$')

# (what it is, pattern, where: None for every text file, 'write' for a line that also writes, or the kind of
# configuration directory the file must be in)
RULES = [
    # Documentation/admin-guide/mm/zswap.rst (Linux 7.3): CONFIG_ZSWAP_DEFAULT_ON enables zswap at boot,
    # zswap.enabled= overrides it, and writing 1 to /sys/module/zswap/parameters/enabled enables it at run time
    ('a kernel configuration with zswap on by default', re.compile(r'^\s*CONFIG_ZSWAP_DEFAULT_ON=y\b'), None),
    ('a kernel command line that turns zswap on', CMDLINE_ZSWAP, None),
    ('zswap turned on at run time', re.compile(r'/sys/module/zswap/parameters/enabled'), 'write'),
    ('a kernel command line that makes zram0 (systemd.zram)', CMDLINE_ZRAM, None),
    # zramctl(8): --find, --size, --algorithm, --streams and --algorithm-params set a device up; listing it does not
    ('a zramctl set-up', re.compile(r'\bzramctl\b.*(?:\s-[A-Za-z]*[fsatp][A-Za-z]*\b|\s--(?:find|size|algorithm|'
                                    r'algorithm-params|streams)\b)'), None),
    # Documentation/admin-guide/blockdev/zram.rst (Linux 7.3): a device is added through zram-control/hot_add and
    # set up through disksize, comp_algorithm, max_comp_streams, mem_limit, backing_dev and algorithm_params
    ('a zram device set up through sysfs', re.compile(r'/sys/(?:block/zram\d*/(?:disksize|comp_algorithm|'
                                                      r'max_comp_streams|mem_limit|backing_dev|algorithm_params)|'
                                                      r'class/zram-control/hot_add)'), 'write'),
    ('a zram device set up by udev', re.compile(r'KERNEL=="zram[^"]*".*(?:ATTR\{[^}]+\}=(?!=)|RUN\+?=)'), None),
    ('swap on a zram device', re.compile(r'\b(?:mkswap|swapon)\b.*?/dev/zram|^\s*/dev/zram\d*\s+\S+\s+swap\b|'
                                         r'^\s*What=/dev/zram'), None),
    ('the zram module loaded', re.compile(r'\bmodprobe\b(?!.*\s(?:-r|--remove)\b).*\bzram\b'), None),
    ('the zram module loaded at boot', re.compile(r'^\s*zram\s*$'), 'modules-load'),
    ('zram or zswap module options', re.compile(r'^\s*options\s+(?:zram\b|zswap\b.*\benabled=' + TRUE_VALUE + ')'),
     'modprobe'),
]
# Strings a compiled program carries when it sets zram or zswap up: zram-generator's configuration, the
# edition's former zram switch (/etc/default/sparky-stereo-zram, /usr/libexec/sparky-stereo/zram-auto) and the
# zswap parameter. Qt keeps u"" literals in UTF-16, so both encodings are searched.
TOKENS = ('zram-generator.conf', 'sparky-stereo-zram', '/sparky-stereo/zram-auto', 'zswap.enabled=1')


def path_rule(path):
    """What the file is, from its path alone, when that is a zram set-up; else None."""
    p = PurePosixPath('/' + str(path).lstrip('/'))
    name, parents = p.name, {q.name for q in p.parents}
    if name == 'zram-generator.conf' or 'zram-generator.conf.d' in parents:
        return 'a zram-generator configuration'
    if 'system-generators' in parents and 'zram' in name:
        return 'a zram generator'
    if str(p).endswith('/etc/default/zramswap') or name in ('zramswap', 'zramswap.service'):
        return "zram-tools' zramswap"
    if 'systemd' in parents and 'zram' in name:
        return 'a zram unit'
    if name == 'zram-auto' or str(p).endswith('/etc/default/sparky-stereo-zram'):
        return "the edition's former zram switch"
    return None


def skipped(path):
    return str(path).lstrip('/').startswith(SKIP_PREFIXES)


def applies(where, path):
    if where in (None, 'write'):
        return True
    parts = PurePosixPath(str(path)).parts
    if where == 'modules-load':
        return 'modules-load.d' in parts or str(path).endswith('etc/modules')
    return 'modprobe.d' in parts


def scan_text(path, text):
    """(line number, line, what) of every line of TEXT that a content rule refuses."""
    found = []
    if not MENTION.search(text):
        return found
    for number, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith(('#', ';', '//')) or not MENTION.search(line):
            continue
        for what, pattern, where in RULES:
            if not applies(where, path) or not pattern.search(line):
                continue
            if where == 'write' and (not WRITE.search(line) or FALSE_WRITE.search(line)):
                continue
            found.append((number, line.strip(), what))
            break
    return found


def scan_compiled(data):
    """(byte offset, token) of the TOKENS in a compiled file."""
    found = []
    for token in TOKENS:
        for encoded in (token.encode(), token.encode('utf-16-le')):
            at = data.find(encoded)
            if at >= 0:
                found.append((at, token))
                break
    return found


def text_of(data):
    if data is None or b'\0' in data[:8192]:
        return None
    try:
        return data.decode('utf-8')
    except UnicodeDecodeError:
        return data.decode('latin-1')


def scan_file(shown, path, data):
    """Every finding of one file, by its path, its text lines or, when compiled, its tokens. DATA is None for a
    link or a file too big to read."""
    findings = []
    what = path_rule(path)
    text = text_of(data) if data is not None and len(data) <= TEXT_LIMIT else None
    if what:
        section = next(((n, l.strip()) for n, l in enumerate((text or '').splitlines(), 1)
                        if l.strip().startswith('[zram')), None)
        findings.append(f'{shown}:{section[0]}: {section[1]} ({what})' if section else f'{shown}: {what}')
    if data is None or skipped(path):
        return findings
    if text is not None:
        findings += [f'{shown}:{n}: {line} ({w})' for n, line, w in scan_text(path, text)]
    elif data[:4] == b'\x7fELF':
        findings += [f'{shown}: byte {at}: "{token}" (a compiled zram or zswap set-up)'
                     for at, token in scan_compiled(data)]
    return findings


def relations(control, origin):
    """Findings for the fields of a control stanza that pull a forbidden package."""
    entries = []
    for number, line in enumerate(control.splitlines(), 1):
        m = re.match(r'^([A-Za-z][A-Za-z0-9-]*):(.*)$', line)
        if m:
            entries.append([m.group(1), number, m.group(2)])
        elif line[:1] in (' ', '\t') and entries:
            entries[-1][2] += ' ' + line.strip()
    findings = []
    for field, number, value in entries:
        if field not in PULLING:
            continue
        for alternative in re.split(r'[,|]', value):
            m = re.match(r'\s*([a-z0-9][a-z0-9+.-]*)', alternative)
            if m and m.group(1) in FORBIDDEN:
                findings.append(f'{origin}:{number}: {field}: {m.group(1)} ({FORBIDDEN[m.group(1)]})')
    return findings


# ---- packages ---------------------------------------------------------------------------------------------------

def members(deb, part):
    """(path, bytes or None) of every file and link of DEB's control or data archive, as dpkg-deb reads them."""
    flag = '--ctrl-tarfile' if part == 'control' else '--fsys-tarfile'
    proc = subprocess.Popen(['dpkg-deb', flag, str(deb)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=proc.stdout, mode='r|') as archive:
            for member in archive:
                path = member.name.removeprefix('./')
                if member.isfile():
                    yield path, archive.extractfile(member).read() if member.size <= BINARY_LIMIT else None
                elif member.issym() or member.islnk():
                    yield path, None
    finally:
        proc.stdout.read()
        error = proc.stderr.read().decode(errors='replace').strip()
        proc.stdout.close()
        proc.stderr.close()
        if proc.wait() != 0:
            raise OSError(f'dpkg-deb {flag} failed: {error or proc.returncode}')


def check_deb(deb):
    """(findings, error) of one package."""
    name = Path(deb).name
    findings = []
    try:
        for path, data in members(deb, 'control'):
            if path == 'control':
                findings += relations(text_of(data) or '', f'{name}: DEBIAN/control')
            elif path != 'md5sums' and (text := text_of(data)) is not None:
                findings += [f'{name}: DEBIAN/{path}:{n}: {line} ({w})' for n, line, w in scan_text(path, text)]
        for path, data in members(deb, 'data'):
            findings += [f'{name}: {f}' for f in scan_file('/' + path, path, data)]
    except (OSError, tarfile.TarError) as error:
        return findings, f'{name}: cannot be read: {error}'
    return findings, None


def check_debs(debs, jobs):
    """Findings and errors of every package; -dbgsym and -lc-hr companions are checked through their package."""
    companions = [d for d in debs if re.search(r'-(?:dbgsym|lc-hr)_', Path(d).name)]
    checked = [d for d in debs if d not in companions]
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(check_deb, checked))
    findings = [f for fs, _ in results for f in fs]
    errors = [e for _, e in results if e]
    refused = sum(1 for fs, e in results if fs or e)
    return findings, errors, (f'{len(checked)} package(s), {refused} refused ({len(companions)} -dbgsym and -lc-hr '
                              'companions are checked through their packages)')


# ---- an image root ---------------------------------------------------------------------------------------------

# Where an image configures boot, swap, modules, units and devices, and where its programs, plugins and
# maintainer scripts are. lib, bin and sbin count where they are not merged into /usr.
IMAGE_TREES = ('etc', 'boot', 'usr/lib/systemd', 'usr/lib/udev', 'usr/lib/modprobe.d', 'usr/lib/modules-load.d',
               'usr/lib/tmpfiles.d', 'usr/lib/sysctl.d', 'usr/lib/kernel', 'usr/lib/kf6', 'usr/libexec', 'usr/local',
               'usr/sbin', 'usr/bin', 'usr/share/initramfs-tools', 'var/lib/dpkg/info', 'lib/systemd', 'lib/udev',
               'lib/modprobe.d', 'lib/modules-load.d', 'sbin', 'bin')
IMAGE_GLOBS = ('usr/lib/sparky*', 'usr/share/sparky*', 'usr/lib/*/qt6/plugins', 'usr/src/*/.config')


def installed(root):
    """{package: status stanza} of what dpkg calls installed in ROOT."""
    packages = {}
    for stanza in (root / 'var/lib/dpkg/status').read_text(errors='replace').split('\n\n'):
        m = re.search(r'^Package: (\S+)', stanza, re.M)
        if m and re.search(r'^Status: install ok installed$', stanza, re.M):
            packages[m.group(1)] = stanza
    return packages


def image_files(root):
    """Every file and link of the image's trees, once."""
    seen = set()
    for top in [root / t for t in IMAGE_TREES] + sorted(p for g in IMAGE_GLOBS for p in root.glob(g)):
        if top.is_symlink() or not top.exists():
            continue
        walk = [(top.parent, [], [top.name])] if top.is_file() else os.walk(top)
        for directory, _, names in walk:
            for name in names:
                path = Path(directory) / name
                if path not in seen and (path.is_symlink() or path.is_file()):
                    seen.add(path)
                    yield path


def check_image(root, also):
    findings, errors = [], []
    try:
        packages = installed(root)
    except OSError as error:
        return findings, [f'/var/lib/dpkg/status: cannot be read: {error}'], 'the image'
    for name, stanza in sorted(packages.items()):
        if name in FORBIDDEN:
            findings.append(f'/var/lib/dpkg/status: {name} is installed ({FORBIDDEN[name]})')
        findings += relations(stanza, f'/var/lib/dpkg/status: {name}')
    count = 0
    for path in image_files(root):
        shown = '/' + path.relative_to(root).as_posix()
        if skipped(shown):
            continue
        data = None
        if not path.is_symlink():
            try:
                data = path.read_bytes() if path.stat().st_size <= BINARY_LIMIT else None
            except OSError as error:
                errors.append(f'{shown}: cannot be read: {error}')
                continue
        count += 1
        findings += scan_file(shown, shown, data)
    for extra in also:
        try:
            data = Path(extra).read_bytes()
        except OSError as error:
            errors.append(f'{extra}: cannot be read: {error}')
            continue
        count += 1
        findings += scan_file(extra, extra, data)
    return findings, errors, f'the image {root} ({count} files read, {len(also)} of them outside it)'


WHY = ('Daniel, 2026-11-02: "do not compress or put anything to run from the RAM regarding swap". zram and zswap '
       'are forbidden in everything the edition ships; the swap is the Cushion Swap File on disk.')


def report(findings, errors, what):
    if not findings and not errors:
        print(f'zram/zswap gate: passed, nothing of zram or zswap in {what}.')
        return 0
    print(f'zram/zswap gate: refused, {len(findings)} finding(s) and {len(errors)} unreadable in {what}:',
          file=sys.stderr)
    for line in findings + errors:
        print(f'  {line}', file=sys.stderr)
    print(WHY, file=sys.stderr)
    print('Remove each set-up named above, or the dependency that pulls it, rebuild the package or the image and run '
          'this gate again; nothing is published or packed until it passes.', file=sys.stderr)
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('root', nargs='?', default='/')
    parser.add_argument('--also', action='append', default=[], metavar='FILE')
    parser.add_argument('--debs', nargs='+', metavar='DEB')
    parser.add_argument('--debs-file', metavar='FILE', help='a file with one .deb path per line')
    parser.add_argument('--jobs', type=int, default=int(os.environ.get('SPARKY_ZRAM_GATE_JOBS', '4')))
    args = parser.parse_args()
    if not (args.debs or args.debs_file):
        return report(*check_image(Path(args.root), args.also))
    debs = list(args.debs or [])
    if args.debs_file:
        try:
            debs += [line.strip() for line in Path(args.debs_file).read_text().splitlines() if line.strip()]
        except OSError as error:
            return report([], [f'{args.debs_file}: cannot be read: {error}'], 'the package list')
    if not debs:
        print('zram/zswap gate: no packages given', file=sys.stderr)
        return 2
    return report(*check_debs(debs, max(1, args.jobs)))


if __name__ == '__main__':
    sys.exit(main())
