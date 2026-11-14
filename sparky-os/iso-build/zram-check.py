#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/14 (ORDER 558: a tear-down is told from a set-up by what the unit and its script do)
"""Refuse zram and zswap in what the edition ships or turns on, and anything of ours that keeps the person from it.

zram and zswap: never ours, never on by default; the person may opt in (HOUSE-RULES; Daniel, 2026-11-02: "do not
compress or put anything to run from the RAM regarding swap"; 2026-11-03: "now make it a opt in for the user that
really wants it", "we don't cape user choice", "what opt in means - off and disabled, the user opt in inside stereo
aptus"). The swap is the Cushion Swap File on disk. No package, image or boot menu of the edition may ship, enable
or pull in zram (zram-generator configurations, systemd-zram-generator, zram-tools, zramctl set-ups, the former
Auto rule) or zswap (zswap.enabled=1 on a kernel command line, CONFIG_ZSWAP_DEFAULT_ON=y), and none may Conflict
with or Break the zram packages, which would cap the person's choice. The person's opt-in passes: the Stereo APTus
entry that installs Debian's systemd-zram-generator when the person picks it is neither a dependency nor a
default. Every finding names the file and the line (a byte offset in a compiled file), and any finding refuses.

A tear-down is not a set-up (ORDER 558). A unit of systemd's that names zram, a drop-in or a link in the folder of
one, is judged by what it does, never by its name: its own Exec lines and the script they run are read to the end.
One that only stops, resets, removes or reports passes, and the gate says so with a note for each file and line it
let through. Any set-up line refuses as before; so does a unit or script that does both, and one the gate cannot
read to its end (a program the package does not ship, a compiled one, text made at run time, a zram device touched
in a way the gate does not know). WHAT A ZRAM UNIT DOES below has the rules.

Unrun Markdown in documentation or skills folders is noted as "documentation, not run". It must be text with
Markdown structure, not executable or shebang code, not in a configuration path, and not named by a consumer in
the package or supplied cohort. Referenced Markdown is scanned as input to a program, including through aliases.

  zram-check.py [ROOT] [--also FILE ...]       an image root (default /): its installed packages, the files that
                                               configure boot, swap, modules, units and devices, the maintainer
                                               scripts and the programs; --also adds files outside ROOT (an ISO's
                                               boot menus)
  zram-check.py --debs DEB ... | --debs-file F  packages: their control fields, maintainer scripts and every file
                                               they ship

Exit status: 0 nothing found (the tear-downs let through are listed); 1 refused (a finding, or a file that cannot
be read: nothing passes unread); 2 usage. The rules and the clauses they follow are in RULES below.
"""
import argparse
import concurrent.futures
import os
import re
import shlex
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
# The fields that install a package by default or stand in for it (Debian Policy 7.2, 7.5), and the ones that keep
# the person from installing it (Policy 7.3, 7.4): both refuse. Suggests and Enhances install nothing by default
# (apt leaves them to the person) and Replaces alone removes nothing; they pass, as the person's own opt-in does.
PULLING = ('Pre-Depends', 'Depends', 'Recommends', 'Provides')
CAPPING = ('Conflicts', 'Breaks')

# Never executed and never read as configuration: documentation, manual pages, translations, shell completions,
# and dpkg-stereo's compressed authored copies (the package they belong to is checked itself).
SKIP_PREFIXES = ('usr/share/doc/', 'usr/share/man/', 'usr/share/info/', 'usr/share/locale/', 'usr/share/help/',
                 'usr/share/bash-completion/', 'usr/share/zsh/', 'usr/share/fish/', 'usr/share/dpkg-stereo/hr/')
DOCUMENT_FOLDERS = {'doc', 'docs', 'documentation', 'skills', 'agent-skills'}
CONFIG_FOLDERS = {'systemd', 'udev', 'modprobe.d', 'sysctl.d', 'tmpfiles.d', 'modules-load.d',
                  'system-generators', 'user-generators', 'initramfs-tools'}
SCRIPT_SUFFIXES = {'.sh', '.bash', '.py', '.pl', '.rb', '.js', '.lua'}
MARKDOWN_PATH = re.compile(rb'''[^\s\0"'`<>|;=(){}\[\]]+\.(?:md|markdown)\b''', re.I)
QUOTED_MARKDOWN = re.compile(rb'''["']([^"'\r\n\0]+\.(?:md|markdown))["']''', re.I)
LITERAL_PATH = re.compile(rb'''/[^\s\0"'`<>|;=(){}\[\]]+''')
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

# Documentation/admin-guide/blockdev/zram.rst (Linux 7.3): a device is set up through disksize, comp_algorithm,
# max_comp_streams, mem_limit, backing_dev and algorithm_params, and "In order to add a new /dev/zramX device,
# perform a read operation on the hot_add attribute", so reading hot_add is a set-up as writing it is.
BLOCK = r'/sys/(?:block|devices/virtual/block)/zram\d*'
SETUP_ATTRIBUTES = 'disksize|comp_algorithm|max_comp_streams|mem_limit|backing_dev|algorithm_params'
SYSFS_SETUP = re.compile(BLOCK + r'/(?:' + SETUP_ATTRIBUTES + r')\b|/sys/class/zram-control/(hot_add)\b')
# A shell redirection and its target (not ">&2"), the files tee writes, and a write the gate cannot place
REDIRECT = re.compile(r'(?<![<>\d&])(?:&|\d*)>>?\|?(?!&)\s*["\']?([^\s"\';|&()<>]+)')
DUPLICATE = re.compile(r'\d*>&\d+|[-=]>|>=')
TEE = re.compile(r'\btee\b((?:[ \t]+[^\s|;&<>]+)*)')
OTHER_WRITE = re.compile(r'^\s*w\+?\s|\.write|write_text|writeValue')
FALSE_VALUE = re.compile(r'(?:echo|printf)\s+(?:-n\s+)?["\']?(?:0|[nNfF]\w*|off)["\']?\s*$')
FILE_TEST = re.compile(r'(?:\[\[?|\btest)\s+(?:!\s+)?-[a-zA-Z]\s+["\']?$')
# How a line reads a path without changing what it names: a test, a comparison, a command that only reads, an input
# redirection, Python's reading calls (the call must end as a reading: PYTHON_READ)
READ = re.compile(r'''(?:(?:\[\[?|\btest)\s+(?:!\s+)?-[a-zA-Z]\s+["']?
                        |(?:\[\[?|\btest)\s[^\];|&]*\s(?:=|==|!=)\s+["']?
                        |(?:==|!=|=~)\s*["']?
                        |\b(?:cat|head|tail|wc|stat|ls|readlink|lsblk|blkid|findmnt|grep|awk|zramctl)\b[^;|&<>]*?\s["']?
                        |(?<!<)<\s*["']?
                        |\b(?:startswith|endswith|exists|isfile|isdir|islink)\(\s*["']
                        |\b(Path|open)\(\s*["'])$''', re.X)
COMPARED = re.compile(r'''^["']?\s*(?:==|!=|\s(?:not\s+)?in\s)''')
PYTHON_READ = re.compile(r'''^["']\s*(?:,\s*["']r[bt]?["']\s*)?\)\s*(?:\.(?:read\w*|exists|is_\w+|stat|resolve)\(|\s+as\b|[:)\s,]|$)''')


def write_targets(line):
    """(target, the command text before it) of every shell redirection and tee of LINE."""
    found = []
    for m in REDIRECT.finditer(line):
        start = max(line.rfind(c, 0, m.start()) for c in ';|&') + 1
        found.append((m.group(1), line[start:m.start()]))
    for m in TEE.finditer(line):
        start = max(line.rfind(c, 0, m.start()) for c in ';&') + 1
        found += [(word.strip('"\''), line[start:m.start()].rsplit('|', 1)[0]) for word in m.group(1).split()
                  if not word.startswith('-')]
    return found


def writes_are_placed(line):
    """True when every write of LINE is a redirection or a tee whose target was read."""
    rest = DUPLICATE.sub('', REDIRECT.sub('', line))
    return '>' not in rest and not OTHER_WRITE.search(line)


def is_read(line, m):
    """True when the path matched by M is only read by LINE."""
    how = READ.search(line[:m.start()])
    if how:
        return not how.group(1) or bool(PYTHON_READ.match(line[m.end():]))
    return bool(COMPARED.match(line[m.end():])) and line[:m.start()].rstrip()[-1:] in ('"', "'", ' ', '(', '')


def sets_up_through_sysfs(line):
    """True when LINE sets a zram device up through sysfs, or may and the gate cannot show it does not. A line
    that only reads disksize and writes somewhere else (the reset attribute, a log) does not."""
    attributes = []
    for m in SYSFS_SETUP.finditer(line):
        if not m.group(1):
            attributes.append(m)
        elif not FILE_TEST.search(line[:m.start()]):
            return True
    if not attributes or not WRITE.search(line):
        return False
    written = [(target, before) for target, before in write_targets(line) if SYSFS_SETUP.match(target)]
    if written:
        return not all(FALSE_VALUE.search(before) for _, before in written)
    if FALSE_WRITE.search(line):
        return False
    return not (writes_are_placed(line) and all(is_read(line, m) for m in attributes))


# (what it is, pattern, where: None for every text file, 'write' for a line that also writes, 'sysfs' for
# sets_up_through_sysfs, or the kind of configuration directory the file must be in)
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
    ('a zram device set up through sysfs', SYSFS_SETUP, 'sysfs'),
    ('a zram device set up by udev', re.compile(r'KERNEL=="zram[^"]*".*(?:ATTR\{[^}]+\}=(?!=)|RUN\+?=)'), None),
    ('swap on a zram device', re.compile(r'\b(?:mkswap|swapon)\b.*?/dev/zram|^\s*/dev/zram\d*\s+\S+\s+swap\b|'
                                         r'^\s*What=/dev/zram'), None),
    ('the zram module loaded', re.compile(r'\bmodprobe\b(?!.*\s(?:-r|--remove)\b).*\bzram\b'), None),
    ('the zram module loaded at boot', re.compile(r'^\s*zram\s*$'), 'modules-load'),
    ('zram or zswap module options', re.compile(r'^\s*options\s+(?:zram\b|zswap\b.*\benabled=' + TRUE_VALUE + ')'),
     'modprobe'),
    # systemd.preset(5): "enable" turns a unit on when presets are applied (first boot, systemctl preset)
    ('a zram unit enabled by a preset', re.compile(r'^\s*enable\s+\S*zram', re.I), 'preset'),
]
# Strings a compiled program carries when it sets zram or zswap up: zram-generator's configuration, the
# edition's former zram switch (/etc/default/sparky-stereo-zram, /usr/libexec/sparky-stereo/zram-auto) and the
# zswap parameter. Qt keeps u"" literals in UTF-16, so both encodings are searched.
TOKENS = ('zram-generator.conf', 'sparky-stereo-zram', '/sparky-stereo/zram-auto', 'zswap.enabled=1')

# ---- WHAT A ZRAM UNIT DOES (ORDER 558) -------------------------------------------------------------------------
#
# What retires zram, each form with its source. A line that matches one, in any file, passes with a note.
#   zram.rst, "Reset": "Write any positive value to 'reset' sysfs node: echo 1 > /sys/block/zram0/reset"; it
#     "frees all the memory allocated for this device and resets the disksize to zero".
#   zram.rst, "Add/remove zram devices": "echo X > /sys/class/zram-control/hot_remove".
#   swapoff(8), systemctl(1) stop, disable and kill, modprobe(8) -r and rmmod(8), zramctl(8) --reset,
#   zram-generator(8) --reset-device, apt-get(8) purge, remove and autoremove of a zram package, and zswap.rst's
#   run-time switch written off.
NAMES = '|'.join(sorted(FORBIDDEN, key=len, reverse=True))
TEAR_DOWNS = [
    ('a zram device reset, its memory freed', re.compile(
        r'(?:\becho|\bprintf)\s+(?:-n\s+)?(["\']?)[1-9]\d*(?:\\{1,2}n)?\1\s*>\s*["\']?' + BLOCK + r'/reset\b')),
    ('a zram device removed', re.compile(r'>\s*["\']?/sys/class/zram-control/hot_remove\b')),
    ('swap on a zram device switched off', re.compile(r'\bswapoff\b[^;|&]*?/dev/zram\d*')),
    ('a zram unit stopped or disabled', re.compile(r'\bsystemctl\b[^;|&]*?\b(?:stop|disable|kill)\b[^;|&]*?'
                                                   r'[\w@.\\:-]*zram[\w@.\\:-]*')),
    ('the zram module unloaded', re.compile(r'\bmodprobe\b[^;|&]*\s(?:-r|--remove)\b[^;|&]*\bzram\b|'
                                            r'\brmmod\b[^;|&]*\bzram\b')),
    ('a zram device reset by zramctl', re.compile(r'\bzramctl\b[^;|&]*(?:\s-[A-Za-z]*r[A-Za-z]*\b|\s--reset\b)'
                                                  r'(?:[^;|&]*?/dev/zram\d*)?')),
    ('a zram device reset by its generator', re.compile(r'(?<![\w-])zram-generator\s[^;|&]*--reset-device\b')),
    ('zramswap stopped', re.compile(r'\bzramswap\s+stop\b')),
    ('a zram package removed', re.compile(r'\b(?:apt-get|apt|aptitude)\b[^;|&]*?\b(?:purge|remove|autoremove|autopurge)\b'
                                          r'[^;|&]*?(?<![\w-])(?:' + NAMES + r')(?![\w-])')),
    ('zswap turned off at run time', re.compile(r'(?:echo|printf)\s+(?:-n\s+)?["\']?(?:0|[nNfF]\w*|off)["\']?\s*>\s*'
                                                r'["\']?/sys/module/zswap/parameters/enabled\b')),
]
# What sets zram up in a unit or the script it runs, beside RULES: starting or enabling a zram unit the package does
# not ship (systemctl(1)), installing a zram package, zram-generator(8) --setup-device (what Debian's
# systemd-zram-setup@.service runs), zramswap start (zram-tools), and a set-up attribute written through a path the
# line does not spell. The person's Stereo APTus action does the first two when the person picks it; nothing of
# ours does them from a unit.
SYSTEMCTL = re.compile(r'\bsystemctl\b([^;|&]*)')
STARTS = ('start', 'restart', 'try-restart', 'reload-or-restart', 'try-reload-or-restart', 'enable', 'reenable', 'preset',
          'unmask', 'isolate')
STOPS = ('stop', 'disable', 'kill')
LOOKS = ('is-active', 'is-enabled', 'is-failed', 'status', 'show', 'cat', 'list-units', 'list-unit-files',
         'list-dependencies', 'reset-failed')
UNIT_NAME = re.compile(r'[\w@.\\:%-]*zram[\w@.\\:%-]*', re.I)
UNIT_SETUPS = [
    ('a zram package installed', re.compile(r'\b(?:apt-get|apt|aptitude)\b[^;|&]*?\b(?:install|reinstall)\b[^;|&]*?'
                                            r'(?<![\w-])(?:' + NAMES + r')(?![\w-])|'
                                            r'\bdpkg\b[^;|&]*\s(?:-i|--install|--unpack)\b[^;|&]*zram')),
    ('the zram generator run to set a device up', re.compile(r'(?<![\w-])zram-generator\s[^;|&]*--setup-device\b')),
    ('zramswap started', re.compile(r'\bzramswap\s+(?:start|restart)\b')),
    ('a zram set-up attribute written through a path the gate cannot read',
     re.compile(r'>\s*["\']?[^\s"\';|&]*[/}"](?:' + SETUP_ATTRIBUTES + r'|hot_add)\b')),
    ('a package installed that the line does not name, in a zram unit or its script',
     re.compile(r'\b(?:apt-get|apt|aptitude)\b[^;|&]*?\binstall\b(?:[^;|&]*\$|["\']?\s*,\s*[A-Za-z_]\w*\s*[\],)])')),
]
# A zram device or its sysfs folder, and zswap's parameters: in a unit or the script it runs, each one named must be
# read, torn down or set up in a way the rules above know; anything else is refused, it does not pass unread.
DEVICE = re.compile(r'/dev/zram\d*|' + BLOCK + r'(?:/[\w.-]+)*|/sys/class/zram-control(?:/\w+)?|'
                    r'/sys/module/zswap(?:/[\w.-]+)*')
# Text a script makes at run time and then runs cannot be read here
MADE_AT_RUN_TIME = re.compile(r'(?<![\w.-])eval\b|\b(?:curl|wget)\b.*\|\s*(?:ba|da)?sh\b|\bbase64\b.*\s(?:-d|--decode)\b|'
                              r'\bb64decode\b|\b__import__\b|\bimportlib\b|(?<![\w.])exec\(|(?<![\w.])compile\(')
# systemd.unit(5), systemd.service(5), systemd.swap(5): the settings that run a command, the ones that start
# another unit with this one, and what a drop-in may add to a zram unit of another package: a condition, a limit,
# an order, a description, or a handler for its failure. Anything else in such a drop-in is refused.
UNIT_SUFFIXES = ('.service', '.socket', '.device', '.mount', '.automount', '.swap', '.target', '.path', '.timer',
                 '.slice', '.scope')
COMMANDS = ('ExecStart', 'ExecStartPre', 'ExecStartPost', 'ExecCondition', 'ExecReload', 'ExecStop', 'ExecStopPost')
PULLS = ('Wants', 'Requires', 'Requisite', 'BindsTo', 'Upholds', 'OnSuccess', 'OnFailure', 'Also', 'Sockets', 'Unit',
         'Alias')
READS_ONLY = ('Description', 'Documentation', 'After', 'Before', 'PartOf', 'Conflicts', 'WantedBy', 'RequiredBy',
              'UpheldBy', 'RequiresMountsFor', 'WantsMountsFor')
LIMITS = re.compile(r'^(?:Condition\w+|Assert\w+|StartLimit\w+|RequiresMountsFor|WantsMountsFor|After|Before|'
                    r'Description|Documentation|Timeout\w*Sec|JobTimeoutSec|RefuseManualStart)$')
HANDLERS = ('OnFailure', 'OnSuccess')
# Programs outside the package whose command line says all they do to zram; the line itself is judged
KNOWN_PROGRAMS = ('systemctl', 'swapoff', 'zramctl', 'modprobe', 'rmmod', 'apt-get', 'apt', 'dpkg', 'rm', 'true', 'echo',
                  'logger', 'sleep', 'touch', 'mkdir', 'udevadm', 'systemd-cat', 'sparky-stereo-problems', 'zramswap',
                  'zram-generator')
SHELLS = ('sh', 'bash', 'dash')
INTERPRETERS = ('python3', 'perl', 'env')
PROGRAM_PATH = re.compile(r'(?<![\w.-])/(?:usr/|opt/)?[\w+.-]+(?:/[\w@%+.-]+)+')
MERGED = {'bin': 'usr/bin', 'sbin': 'usr/sbin', 'lib': 'usr/lib', 'lib64': 'usr/lib64'}


def logical_lines(text):
    """(number of its first line, line) with every line that ends in a backslash joined to the next."""
    number, parts = 0, []
    for at, line in enumerate(text.splitlines(), 1):
        if not parts:
            number = at
        if line.endswith('\\') and not line.endswith('\\\\'):
            parts.append(line[:-1])
            continue
        yield number, ''.join(parts) + line
        parts = []
    if parts:
        yield number, ''.join(parts)


def tear_downs(line):
    """(what, span) of every tear-down LINE carries."""
    return [(what, m.span()) for what, pattern in TEAR_DOWNS for m in pattern.finditer(line)]


def judge(line, ships):
    """What one line of a zram unit, or of a script it runs, does to zram: (set-ups, tear-downs, unknowns), each a
    list of what it is. SHIPS(unit name) is true for a unit of the package itself."""
    setups = [what for what, pattern, where in RULES if where in (None, 'write', 'sysfs') and pattern.search(line)
              and not (where == 'write' and (not WRITE.search(line) or FALSE_WRITE.search(line)))
              and not (where == 'sysfs' and not sets_up_through_sysfs(line))]
    unknown = []
    for m in SYSTEMCTL.finditer(line):
        units = [u.group(0) for u in UNIT_NAME.finditer(m.group(1)) if not ships(u.group(0))]
        verb = next((w for w in re.findall(r'[\w@.:%-]+', m.group(1)) if not w.startswith('-')), '')
        if units and verb in STARTS:
            setups += [f'a zram unit this package does not ship is started or enabled ({unit})' for unit in units]
        elif units and verb not in STOPS + LOOKS:
            unknown.append(f'systemctl {verb} on {units[0]} is not a tear-down the gate knows (a mask keeps the '
                           'person\'s zram from starting)')
    setups += [what for what, pattern in UNIT_SETUPS if pattern.search(line) and what not in setups
               and not ('attribute written' in what and (setups or SYSFS_SETUP.search(line)))]
    down = tear_downs(line)
    if setups:
        unknown = []
    else:
        for m in DEVICE.finditer(line):
            if any(start <= m.start() and m.end() <= end for _, (start, end) in down) or is_read(line, m):
                continue
            unknown.append(f'{m.group(0)} is used in a way the gate does not know as a tear-down or a reading')
        if MADE_AT_RUN_TIME.search(line):
            unknown.append('text made at run time and then run, which the gate cannot read')
    return setups, [what for what, _ in down], unknown


class Tree:
    """The files a unit can reach: a package's own (FILES: path -> bytes, None when too big, or ('link', target))
    or an image's (ROOT)."""

    def __init__(self, files=None, root=None):
        self.files, self.root = files, root

    @staticmethod
    def norm(path):
        parts = [p for p in PurePosixPath('/' + str(path).lstrip('/')).parts[1:] if p != '.']
        return '/'.join(parts)

    def entry(self, path):
        """('file', bytes or None), ('link', target) or None."""
        if self.files is not None:
            value = self.files.get(path, self)
            if value is self:
                return None
            return value if isinstance(value, tuple) else ('file', value)
        real = self.root / path
        if real.is_symlink():
            return 'link', os.readlink(real)
        if real.is_file():
            try:
                return 'file', real.read_bytes() if real.stat().st_size <= TEXT_LIMIT else None
            except OSError:
                return 'file', None
        return None

    def find(self, path):
        """The path of the file PATH names here, through links and a merged /usr; None when it is not here."""
        path = self.norm(path)
        for _ in range(8):
            entry = self.entry(path)
            if entry is None:
                first, _, rest = path.partition('/')
                if first in MERGED and rest:
                    path = MERGED[first] + '/' + rest
                    if self.entry(path) is not None:
                        continue
                return None
            if entry[0] == 'file':
                return path
            target = entry[1]
            path = self.norm(target if target.startswith('/') else os.path.normpath(
                str(PurePosixPath(path).parent / target)))
        return None

    def text(self, path):
        entry = self.entry(path)
        return text_of(entry[1]) if entry and entry[0] == 'file' and entry[1] is not None else None

    def units(self, name):
        """The unit files of this tree that NAME means: itself, or the template of an instance."""
        names = {name, re.sub(r'@[^.]*\.', '@.', name)}
        if self.files is not None:
            return sorted(p for p in self.files if PurePosixPath(p).name in names and unit_folder(p) is not None
                          and not isinstance(self.files[p], tuple))
        found = []
        for folder in ('usr/lib/systemd/system', 'etc/systemd/system', 'lib/systemd/system', 'usr/lib/systemd/user',
                       'etc/systemd/user'):
            found += [f'{folder}/{n}' for n in sorted(names) if (self.root / folder / n).is_file()
                      and not (self.root / folder / n).is_symlink()]
        return found


def unit_folder(path):
    """Where PATH sits below systemd's system or user folder, as its parts; None when it is not a unit's place."""
    parts = PurePosixPath('/' + str(path).lstrip('/')).parts
    for at in range(len(parts) - 2):
        if parts[at] == 'systemd' and parts[at + 1] in ('system', 'user'):
            return parts[at + 2:]
    return None


def of_zram(path, text, target):
    """True when a unit's file, a drop-in or a link is about zram or zswap: by a name on its way, by where it
    points, or by what it says."""
    below = unit_folder(path)
    return below is not None and bool(MENTION.search('/'.join(below)) or MENTION.search(target or '') or any(
        MENTION.search(line) for _, _, _, _, line in parse_unit(text or '')))


def parse_unit(text):
    """(section, key, value, line number, line) of every setting of a unit file (systemd.syntax(7))."""
    section = ''
    for number, line in logical_lines(text):
        stripped = line.strip()
        if not stripped or stripped.startswith(('#', ';')):
            continue
        if stripped.startswith('[') and stripped.endswith(']'):
            section = stripped[1:-1]
        elif '=' in stripped:
            key, value = stripped.split('=', 1)
            yield section, key.strip(), value.strip(), number, stripped
        else:
            yield section, '', stripped, number, stripped


class Reading:
    """What the zram units of one tree do. FINDINGS refuse; NOTES are what was let through and why; READ is every
    file read as a unit or as a script one runs."""

    def __init__(self, tree, shown):
        self.tree, self.shown = tree, shown
        self.findings, self.notes, self.read = [], [], set()
        self.scripts, self.pending = {}, {}

    def ships(self, name):
        return bool(self.tree.units(name.replace('%n', 'x').replace('%i', 'x').replace('%N', 'x').replace('%I', 'x')))

    def refuse(self, path, number, line, why):
        where = f'{self.shown(path)}:{number}' if number else self.shown(path)
        self.findings.append(f'{where}: {line} ({why})' if line else f'{where}: {why}')

    def note(self, path, number, line, why):
        where = f'{self.shown(path)}:{number}' if number else self.shown(path)
        self.notes.append(f'{where}: {line} ({why})' if line else f'{where}: {why}')

    def line(self, path, number, line):
        """Judges one line; returns (refused, the tear-downs it carries)."""
        setups, down, unknown = judge(line, self.ships)
        for what in setups:
            self.refuse(path, number, line, what)
        for what in unknown:
            self.refuse(path, number, line, f'{what}: refused, nothing passes unread')
        self.pending.setdefault(path, []).extend((number, line, what) for what in down)
        return bool(setups or unknown), down

    def let_through(self, path, refused):
        """The tear-down lines of a file are noted only when nothing in it, or in what it runs, is refused."""
        for number, line, what in self.pending.pop(path, []) if not refused else ():
            self.note(path, number, line, f'{what}: a tear-down')

    def script(self, path):
        """Reads a script of the tree to its end, and every script of the tree it names; returns (refused, tear-downs)
        of all of them. A tear-down line is noted only when nothing in the script is refused."""
        if path in self.scripts:
            return self.scripts[path]
        self.scripts[path] = (False, 0)
        self.read.add(path)
        text = self.tree.text(path)
        refused, count = False, 0
        for number, line in logical_lines(text):
            if line.lstrip().startswith('#'):
                continue
            bad, down = self.line(path, number, line.strip())
            refused, count = refused or bad, count + len(down)
        for name in sorted(set(PROGRAM_PATH.findall(text))):
            other = self.tree.find(name)
            if other and other != path and (self.tree.text(other) or '').startswith('#!') and not skipped(other):
                bad, more = self.script(other)
                refused, count = refused or bad, count + more
        self.let_through(path, refused)
        self.scripts[path] = (refused, count)
        return refused, count

    def command(self, path, number, line, value, key):
        """Judges the command of one Exec setting and follows the program it runs; returns (refused, tear-downs,
        what it runs)."""
        refused, down = self.line(path, number, line)
        count, runs = len(down), []
        try:
            words = shlex.split(value.lstrip('@-:+!|'), posix=True)
        except ValueError as error:
            self.refuse(path, number, line, f'a command the gate cannot split into words ({error}): refused')
            return True, count, runs
        commands, current = [], []
        for word in words:
            if word == ';':
                commands.append(current)
                current = []
            else:
                current.append(word)
        commands.append(current)
        for argv in [c for c in commands if c]:
            program, base = argv[0], PurePosixPath(argv[0]).name
            mine = self.tree.find(program) if program.startswith('/') else None
            if mine is not None and self.tree.text(mine) is None and base in SHELLS + INTERPRETERS + KNOWN_PROGRAMS:
                mine = None    # an image has the system's own programs; their command line is what is judged
            follow = None
            if mine is None and (self.tree.entry(Tree.norm(program)) or ('', ''))[0] == 'link':
                self.refuse(path, number, line, f'runs {program}, a link that leaves this package: the gate cannot '
                                                'follow it')
                refused = True
            elif mine is not None:
                follow = mine
            elif base in SHELLS + INTERPRETERS:
                rest = [a for a in argv[1:] if not a.startswith('-') and '=' not in a]
                if base in SHELLS and '-c' in argv[1:]:
                    pass
                elif base in INTERPRETERS and any(a in ('-c', '-e') for a in argv[1:]):
                    pass
                elif rest and rest[0].startswith('/') and self.tree.find(rest[0]):
                    follow = self.tree.find(rest[0])
                elif base == 'env' and rest and PurePosixPath(rest[0]).name in KNOWN_PROGRAMS:
                    pass
                else:
                    self.refuse(path, number, line, f'runs {" ".join(argv[:2])}, a script this package does not '
                                                    'ship: the gate cannot follow it')
                    refused = True
            elif base == 'false' and key == 'ExecCondition':
                self.refuse(path, number, line, 'a condition that never holds keeps the zram unit from starting, '
                                                'which caps the person\'s choice')
                refused = True
            elif base not in KNOWN_PROGRAMS:
                self.refuse(path, number, line, f'runs {program}, which this package does not ship and the gate does '
                                                'not know: it cannot follow it')
                refused = True
            elif (base == 'zram-generator' and '--reset-device' not in argv) or (
                    base == 'zramswap' and argv[1:2] not in (['stop'], ['status'])):
                self.refuse(path, number, line, f'runs {program} in a way that is not a tear-down the gate knows')
                refused = True
            if follow is not None:
                if self.tree.text(follow) is None:
                    self.refuse(path, number, line, f'runs /{follow}, which the gate cannot read (compiled, or too big)')
                    refused = True
                else:
                    bad, more = self.script(follow)
                    refused, count = refused or bad, count + more
                    runs.append('/' + follow)
        return refused, count, runs

    def handler(self, path, number, line, key, value, own):
        """A setting that starts other units with this one: a zram unit of another package refuses; a unit of this
        package is read."""
        refused, count = False, 0
        for name in value.split():
            mine = self.tree.units(name.replace('%n', 'x').replace('%i', 'x'))
            if mine:
                for unit in mine:
                    bad, more = self.unit(unit)
                    refused, count = refused or bad, count + more
            elif MENTION.search(name):
                self.refuse(path, number, line, f'a zram unit this package does not ship is pulled in ({name})')
                refused = True
            elif not own and key not in HANDLERS:
                self.refuse(path, number, line, 'a drop-in that pulls another unit in with a zram unit')
                refused = True
        return refused, count

    def unit(self, path):
        """Reads a unit file of the tree; returns (refused, tear-downs)."""
        return self.settings(path, own=True)

    def settings(self, path, own):
        """Reads a unit file, or a drop-in (OWN: of a unit of this package; else of another package's zram unit)."""
        if path in self.scripts:
            return self.scripts[path]
        self.scripts[path] = (False, 0)
        self.read.add(path)
        name = PurePosixPath(path).name
        text = self.tree.text(path)
        if text is None:
            self.refuse(path, 0, '', 'a zram unit the gate cannot read: refused, nothing passes unread')
            self.scripts[path] = (True, 0)
            return True, 0
        refused, count, runs, limits, commands = False, 0, [], [], 0
        for section, key, value, number, line in parse_unit(text):
            if key in COMMANDS and (own or key == 'ExecCondition'):
                if not value:
                    continue
                commands += 1
                bad, more, ran = self.command(path, number, line, value, key)
                refused, count, runs = refused or bad, count + more, runs + ran
                limits.append(key)
            elif key in PULLS and (own or key in HANDLERS):
                bad, more = self.handler(path, number, line, key, value, own)
                refused, count = refused or bad, count + more
                limits.append(key)
            elif own or LIMITS.match(key):
                if key not in READS_ONLY and not key.startswith(('Condition', 'Assert')):
                    bad, down = self.line(path, number, line)
                    refused, count = refused or bad, count + len(down)
                limits.append(key)
            else:
                self.refuse(path, number, line, 'a drop-in may only limit or condition a zram unit of another package, '
                                                'or hand its failure on; this setting does more, or the gate does not '
                                                'know it')
                refused = True
        if own and name.endswith('.swap') and re.match(r'dev-zram\d*\.swap$', name):
            # systemd.swap(5): "Swap units must be named after the devices or files they control"
            self.refuse(path, 0, '', 'a zram unit: swap on a zram device, by the name systemd.swap(5) gives it')
            refused = True
        elif own and not commands and not name.endswith('.conf'):
            if name.endswith(('.timer', '.path', '.socket')):
                target = next((v for _, k, v, _, _ in parse_unit(text) if k == 'Unit'), name.rsplit('.', 1)[0] + '.service')
                mine = self.tree.units(target)
                if not mine:
                    self.refuse(path, 0, '', f'a zram unit that starts {target}, which this package does not ship: the '
                                             'gate cannot follow it')
                    refused = True
                for unit in mine:
                    bad, more = self.unit(unit)
                    refused, count = refused or bad, count + more
            elif not name.endswith('.service'):
                self.refuse(path, 0, '', 'a zram unit of a kind the gate does not judge (it runs no command the gate '
                                         'can read): refused, nothing passes unread')
                refused = True
        if refused and count:
            self.refuse(path, 0, '', f'does both: {count} tear-down line(s) beside what is refused above; a unit that '
                                     'tears zram down and also sets it up, or cannot be read to its end, is refused')
        elif not refused:
            ran = f'runs {", ".join(dict.fromkeys(runs))}, read to the end' if runs else 'runs no program of its own'
            if own:
                self.note(path, 0, '', f'a zram unit that only stops, resets, removes or reports: {ran}; '
                                       f'{count} tear-down line(s) in what it runs, no set-up')
            else:
                unit = PurePosixPath(path).parent.name[:-2]
                self.note(path, 0, '', f'a drop-in that only limits or conditions {unit} '
                                       f'({", ".join(dict.fromkeys(limits)) or "no setting"}): {ran}; no set-up')
        self.let_through(path, refused)
        self.scripts[path] = (refused, count)
        return refused, count

    def file(self, path, target):
        """One unit file, drop-in or link that is about zram."""
        if path in self.read:
            return
        self.read.add(path)
        p = PurePosixPath(path)
        folder = p.parent.name
        if target is not None:
            if target == '/dev/null' and folder.endswith('.d'):
                self.note(path, 0, '', f'masks the drop-in {p.name} of {folder[:-2]}: it takes a setting away from that '
                                       'unit and adds none')
            elif target == '/dev/null':
                self.refuse(path, 0, '', f'a zram unit masked ({p.name}): it keeps the person\'s zram from starting, '
                                         'which caps their choice')
            elif self.tree.units(p.name) or self.tree.units(PurePosixPath(target).name):
                for unit in self.tree.units(p.name) or self.tree.units(PurePosixPath(target).name):
                    refused, _ = self.unit(unit)
                    if not refused:
                        self.note(path, 0, '', f'starts /{unit} of this package with {folder or "its other name"}; '
                                               'that unit only tears zram down, as its own note says')
                    else:
                        self.refuse(path, 0, '', f'starts /{unit}, which is refused')
            else:
                self.refuse(path, 0, '', f'a zram unit this package does not ship is enabled or named again ({p.name} '
                                         f'-> {target}): that sets zram up')
            return
        self.read.discard(path)
        if folder.endswith('.d') and p.name.endswith('.conf'):
            self.settings(path, own=bool(self.tree.units(folder[:-2])))
        elif p.name.endswith(UNIT_SUFFIXES):
            self.unit(path)
        else:
            self.read.add(path)
            self.refuse(path, 0, '', 'a file about zram among systemd\'s units that the gate cannot judge: refused, '
                                     'nothing passes unread')


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
    if 'systemd' in parents and 'zram' in name and unit_folder(path) is None and not name.endswith('.preset'):
        return 'a file of systemd\'s named after zram that the gate cannot judge'
    if name == 'zram-auto' or str(p).endswith('/etc/default/sparky-stereo-zram'):
        return "the edition's former zram switch"
    return None


def skipped(path):
    return str(path).lstrip('/').startswith(SKIP_PREFIXES)


def markdown(path):
    return PurePosixPath(path).suffix.lower() in ('.md', '.markdown')


def configuration(path):
    path = str(path).lstrip('/')
    parts = set(PurePosixPath(path).parts)
    return bool(parts & CONFIG_FOLDERS or path.startswith(('etc/', 'boot/', 'var/lib/dpkg/info/', 'DEBIAN/')))


def references(path, data, mode):
    """Markdown paths named by code or configuration, including literal paths in compiled programs."""
    if data is None:
        return set()
    if not (mode & 0o111 or data.startswith((b'#!', b'\x7fELF')) or configuration(path)
            or PurePosixPath(path).suffix in SCRIPT_SUFFIXES):
        return set()
    paths = MARKDOWN_PATH.findall(data) + QUOTED_MARKDOWN.findall(data) + LITERAL_PATH.findall(data)
    found = {PurePosixPath(p.decode('utf-8', errors='replace')).name.casefold() for p in paths}
    text = text_of(data) if len(data) <= TEXT_LIMIT else None
    if text is not None:
        found.update(word.casefold() for word in re.findall(r'[\w.+%-]+', text))
    return found


def follow_aliases(aliases, referenced):
    """A link is a consumer reference only when code or configuration names that link."""
    referenced = set(referenced)
    for _ in aliases:
        before = len(referenced)
        for path, target in aliases:
            if PurePosixPath(path).name.casefold() in referenced:
                referenced.add(PurePosixPath(target).name.casefold())
        if len(referenced) == before:
            break
    return referenced


def documentation(path, data, mode, referenced):
    """Unrun Markdown in a documentation folder; an extension alone never establishes this."""
    if data is None or len(data) > TEXT_LIMIT:
        return False
    parts = set(PurePosixPath(path).parts)
    try:
        text = data.decode('utf-8') if data is not None else ''
    except UnicodeDecodeError:
        return False
    return bool(markdown(path) and parts & DOCUMENT_FOLDERS and not configuration(path)
                and not parts & {'bin', 'sbin', 'libexec'} and not mode & 0o111
                and all(c.isprintable() or c in '\t\r\n' for c in text)
                and not text.lstrip('\ufeff \t\r\n').startswith('#!')
                and PurePosixPath(path).name.casefold() not in referenced
                and re.search(r'(?m)^ {0,3}(?:#{1,6}\s+\S|```|~~~|\|.+\|\s*$)', text))


def applies(where, path):
    if where in (None, 'write', 'sysfs'):
        return True
    parts = PurePosixPath(str(path)).parts
    if where == 'modules-load':
        return 'modules-load.d' in parts or str(path).endswith('etc/modules')
    if where == 'preset':
        return 'system-preset' in parts or 'user-preset' in parts
    return 'modprobe.d' in parts


def scan_text(path, text, notes=None):
    """(line number, line, what) of every line of TEXT that a content rule refuses; the tear-downs of the other
    lines are added to NOTES in the same form."""
    found = []
    if not MENTION.search(text):
        return found
    for number, line in logical_lines(text):
        if line.lstrip().startswith(('#', ';', '//')) or not MENTION.search(line):
            continue
        for what, pattern, where in RULES:
            if not applies(where, path) or not pattern.search(line):
                continue
            if where == 'write' and (not WRITE.search(line) or FALSE_WRITE.search(line)):
                continue
            if where == 'sysfs' and not sets_up_through_sysfs(line):
                continue
            found.append((number, line.strip(), what))
            break
        else:
            if notes is not None:
                notes += [(number, line.strip(), f'{what}: a tear-down') for what, _ in tear_downs(line)]
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


def scan_file(shown, path, data, notes=None, document=None):
    """Every finding of one file, by its path, its text lines or, when compiled, its tokens. DATA is None for a
    link or a file too big to read. The tear-down lines it carries go to NOTES as (line number, line, what)."""
    findings = []
    what = path_rule(path)
    text = text_of(data) if data is not None and len(data) <= TEXT_LIMIT else None
    if what:
        section = next(((n, l.strip()) for n, l in enumerate((text or '').splitlines(), 1)
                        if l.strip().startswith('[zram')), None)
        findings.append(f'{shown}:{section[0]}: {section[1]} ({what})' if section else f'{shown}: {what}')
    if document:
        if notes is not None and MENTION.search(text or ''):
            notes.append((0, '', 'documentation, not run'))
        return findings
    if document is False and markdown(path) and (data is None or len(data) > TEXT_LIMIT):
        findings.append(f'{shown}: Markdown cannot be read within the text limit; not classified as unrun documentation')
        return findings
    if data is None or (skipped(path) and document is None):
        return findings
    if text is not None:
        findings += [f'{shown}:{n}: {line} ({w})' for n, line, w in scan_text(path, text, notes)]
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
        if field not in PULLING + CAPPING:
            continue
        for alternative in re.split(r'[,|]', value):
            m = re.match(r'\s*([a-z0-9][a-z0-9+.-]*)', alternative)
            if m and m.group(1) in FORBIDDEN:
                why = (FORBIDDEN[m.group(1)] if field in PULLING else
                       f"{FORBIDDEN[m.group(1)]}: keeps the person from opting in, which caps their choice")
                findings.append(f'{origin}:{number}: {field}: {m.group(1)} ({why})')
    return findings


def merge(findings, notes, reading, line_notes, shown):
    """The findings and notes of a tree: the units' reading first decides what a file it read says; the tear-down
    lines of the other files are notes of their own."""
    findings = list(dict.fromkeys(findings + reading.findings))
    notes = notes + reading.notes
    for path, lines in line_notes.items():
        if path not in reading.read:
            notes += [f'{shown(path)}:{n}: {line} ({what})' for n, line, what in lines]
    return findings, list(dict.fromkeys(notes))


# ---- packages ---------------------------------------------------------------------------------------------------

def members(deb, part, modes=False):
    """(path, bytes or None, link target or None) of every file and link of DEB's control or data archive, as
    dpkg-deb reads them."""
    flag = '--ctrl-tarfile' if part == 'control' else '--fsys-tarfile'
    proc = subprocess.Popen(['dpkg-deb', flag, str(deb)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        with tarfile.open(fileobj=proc.stdout, mode='r|') as archive:
            for member in archive:
                path = member.name.removeprefix('./')
                if member.isfile():
                    row = (path, archive.extractfile(member).read() if member.size <= BINARY_LIMIT else None, None)
                    yield (*row, member.mode) if modes else row
                elif member.issym() or member.islnk():
                    row = (path, None, member.linkname)
                    yield (*row, member.mode) if modes else row
    finally:
        proc.stdout.read()
        error = proc.stderr.read().decode(errors='replace').strip()
        proc.stdout.close()
        proc.stderr.close()
        if proc.wait() != 0:
            raise OSError(f'dpkg-deb {flag} failed: {error or proc.returncode}')


def check_deb(deb, referenced=()):
    """(findings, notes, error) of one package."""
    name = Path(deb).name
    findings, notes, units, line_notes = [], [], [], {}
    referenced, documents, aliases = set(referenced), [], []
    try:
        for path, data, _ in members(deb, 'control'):
            if path == 'control':
                findings += relations(text_of(data) or '', f'{name}: DEBIAN/control')
            elif path != 'md5sums' and (text := text_of(data)) is not None:
                referenced |= references('DEBIAN/' + path, data, 0o755)
                down = []
                findings += [f'{name}: DEBIAN/{path}:{n}: {line} ({w})' for n, line, w in scan_text(path, text, down)]
                notes += [f'{name}: DEBIAN/{path}:{n}: {line} ({w})' for n, line, w in down]
        for path, data, target, mode in members(deb, 'data', modes=True):
            referenced |= references(path, data, mode)
            if target is not None:
                aliases.append((path, target))
            if markdown(path) and target is None:
                documents.append((path, data, mode))
                continue
            down = []
            findings += [f'{name}: {f}' for f in scan_file('/' + path, path, data, down)]
            if down:
                line_notes[path] = down
            small = data if data is not None and len(data) <= TEXT_LIMIT and unit_folder(path) is not None else None
            if of_zram(path, text_of(small), target):
                units.append((path, target))
        referenced = follow_aliases(aliases, referenced)
        for path, data, mode in documents:
            down = []
            document = documentation(path, data, mode, referenced)
            findings += [f'{name}: {f}' for f in scan_file('/' + path, path, data, down, document=document)]
            for n, line, what in down:
                if what == 'documentation, not run':
                    notes.append(f'{name}: /{path}: {what}')
                else:
                    line_notes.setdefault(path, []).append((n, line, what))
        reading = Reading(Tree(files={}), lambda path: f'{name}: /{path}')
        if units:
            # the unit's Exec lines name other files of the package: read them all, once more, to follow them
            files = {}
            for path, data, target in members(deb, 'data'):
                files[path] = ('link', target) if target is not None else (
                    data if data is not None and len(data) <= TEXT_LIMIT else None)
            reading.tree = Tree(files=files)
            for path, target in units:
                reading.file(path, target)
    except (OSError, tarfile.TarError) as error:
        return findings, notes, f'{name}: cannot be read: {error}'
    return (*merge(findings, notes, reading, line_notes, lambda path: f'{name}: /{path}'), None)


def check_debs(debs, jobs):
    """Findings, errors and notes of every package; -dbgsym and -lc-hr companions are checked through their
    package."""
    companions = [d for d in debs if re.search(r'-(?:dbgsym|lc-hr)_', Path(d).name)]
    checked = [d for d in debs if d not in companions]
    # A consumer may belong to another package in the supplied cohort.
    referenced, aliases = set(), []
    for deb in checked:
        try:
            for part in ('control', 'data'):
                for path, data, target, mode in members(deb, part, modes=True):
                    if part == 'control' and path in ('control', 'md5sums'):
                        continue
                    referenced |= references('DEBIAN/' + path if part == 'control' else path, data, mode)
                    if target is not None:
                        aliases.append((path, target))
        except (OSError, tarfile.TarError):
            pass  # check_deb below retains the unreadable-package refusal.
    referenced = follow_aliases(aliases, referenced)
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda deb: check_deb(deb, referenced), checked))
    findings = [f for fs, _, _ in results for f in fs]
    notes = [n for _, ns, _ in results for n in ns]
    errors = [e for _, _, e in results if e]
    refused = sum(1 for fs, _, e in results if fs or e)
    return findings, errors, (f'{len(checked)} package(s), {refused} refused ({len(companions)} -dbgsym and -lc-hr '
                              'companions are checked through their packages)'), notes


# ---- an image root ---------------------------------------------------------------------------------------------

# Where an image configures boot, swap, modules, units and devices, and where its programs, plugins and
# maintainer scripts are. lib, bin and sbin count where they are not merged into /usr.
IMAGE_TREES = ('etc', 'boot', 'usr/lib/systemd', 'usr/lib/udev', 'usr/lib/modprobe.d', 'usr/lib/modules-load.d',
               'usr/lib/tmpfiles.d', 'usr/lib/sysctl.d', 'usr/lib/kernel', 'usr/lib/kf6', 'usr/libexec', 'usr/local',
               'usr/sbin', 'usr/bin', 'usr/share/initramfs-tools', 'var/lib/dpkg/info', 'lib/systemd', 'lib/udev',
               'lib/modprobe.d', 'lib/modules-load.d', 'sbin', 'bin', 'usr/share/agent-skills')
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
    """Every file and link of the image's trees, once: a tree reached through a link (lib, bin and sbin merged into
    /usr) is the tree it leads to, read under its own name."""
    seen = set()
    for top in [root / t for t in IMAGE_TREES] + sorted(p for g in IMAGE_GLOBS for p in root.glob(g)):
        if top.is_symlink() or not top.exists() or top.resolve() != top.absolute():
            continue
        walk = [(top.parent, [], [top.name])] if top.is_file() else os.walk(top)
        for directory, _, names in walk:
            for name in names:
                path = Path(directory) / name
                if path not in seen and (path.is_symlink() or path.is_file()):
                    seen.add(path)
                    yield path


def check_image(root, also):
    """(findings, errors, what was read, notes) of an image root."""
    findings, errors, units, line_notes = [], [], [], {}
    try:
        packages = installed(root)
    except OSError as error:
        return findings, [f'/var/lib/dpkg/status: cannot be read: {error}'], 'the image', []
    for name, stanza in sorted(packages.items()):
        if name in FORBIDDEN:
            findings.append(f'/var/lib/dpkg/status: {name} is installed ({FORBIDDEN[name]}: an image has it off '
                            'and not installed; the person opts in from Stereo APTus)')
        findings += relations(stanza, f'/var/lib/dpkg/status: {name}')
    count = 0
    referenced, documents, aliases = set(), [], []
    for path in image_files(root):
        shown = '/' + path.relative_to(root).as_posix()
        if skipped(shown) and not markdown(shown):
            continue
        data = target = None
        if path.is_symlink():
            target = os.readlink(path)
            aliases.append((shown, target))
        else:
            try:
                data = path.read_bytes() if path.stat().st_size <= BINARY_LIMIT else None
            except OSError as error:
                errors.append(f'{shown}: cannot be read: {error}')
                continue
        count += 1
        mode = path.stat().st_mode if not path.is_symlink() else 0
        referenced |= references(shown, data, mode)
        if markdown(shown) and target is None:
            documents.append((shown, data, mode))
            continue
        down = []
        findings += scan_file(shown, shown, data, down)
        if down:
            line_notes[shown.lstrip('/')] = down
        small = data if data is not None and len(data) <= TEXT_LIMIT and unit_folder(shown) is not None else None
        if of_zram(shown, text_of(small), target):
            units.append((shown.lstrip('/'), target))
    reading = Reading(Tree(root=root), lambda path: f'/{path}')
    for path, target in units:
        reading.file(path, target)
    referenced = follow_aliases(aliases, referenced)
    document_notes = []
    for shown, data, mode in documents:
        down = []
        findings += scan_file(shown, shown, data, down,
                              document=documentation(shown, data, mode, referenced))
        for n, line, what in down:
            if what == 'documentation, not run':
                document_notes.append(f'{shown}: {what}')
            else:
                line_notes.setdefault(shown.lstrip('/'), []).append((n, line, what))
    findings, notes = merge(findings, document_notes, reading, line_notes, lambda path: f'/{path}')
    for extra in also:
        try:
            data = Path(extra).read_bytes()
        except OSError as error:
            errors.append(f'{extra}: cannot be read: {error}')
            continue
        count += 1
        findings += scan_file(extra, extra, data)
    return findings, errors, f'the image {root} ({count} files read, {len(also)} of them outside it)', notes


WHY = ('zram and zswap: never ours, never on by default; the person may opt in (Daniel, 2026-11-02: "do not compress '
       'or put anything to run from the RAM regarding swap"; 2026-11-03: "we don\'t cape user choice"). The swap is the '
       'Cushion Swap File on disk. Nothing the edition ships sets zram or zswap up, pulls in a zram package or keeps the '
       'person from one; the Stereo APTus entry that installs Debian\'s systemd-zram-generator when the person picks it '
       'is the opt-in, neither a dependency nor a default, and passes. A unit or a line that only retires zram (stops, '
       'resets, removes, reports) passes with a note; one that also sets it up, or that cannot be read to its end, is '
       'refused.')
LET_THROUGH = ('zram/zswap gate: {count} tear-down(s) let through, each read to its end. A tear-down stops, resets or '
               'removes zram, or reports; it sets nothing up:')


def report(findings, errors, what, notes=()):
    documents = [n for n in notes if n.endswith(': documentation, not run')]
    notes = [n for n in notes if n not in documents]
    if not findings and not errors:
        print(f'zram/zswap gate: passed, nothing of zram or zswap of ours in {what} (the person\'s opt-in from Stereo '
              'APTus is allowed).')
        if notes:
            print(LET_THROUGH.format(count=len(notes)))
            for line in notes:
                print(f'  note: {line}')
        for line in documents:
            print(f'  note: {line}')
        return 0
    print(f'zram/zswap gate: refused, {len(findings)} finding(s) and {len(errors)} unreadable in {what}:',
          file=sys.stderr)
    for line in findings + errors:
        print(f'  {line}', file=sys.stderr)
    print(WHY, file=sys.stderr)
    print('Remove each set-up named above, or the relation that pulls the package in or keeps it out, rebuild the '
          'package or the image and run this gate again; nothing is published or packed until it passes.', file=sys.stderr)
    if notes:
        print(LET_THROUGH.format(count=len(notes)) + ' (these are not why it is refused)', file=sys.stderr)
        for line in notes:
            print(f'  note: {line}', file=sys.stderr)
    for line in documents:
        print(f'  note: {line}', file=sys.stderr)
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
