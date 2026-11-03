#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Writes renamed-commands, the table of commands Debian installs under another name, from Debian's own data (ORDER 252b,
# study row J15). Debian Policy 10.1: "Two different packages must not install programs with different functionality
# but with the same filenames ... If this case happens, one of the programs must be renamed." So `fd` is fd-find's
# `fdfind` (fdclone has /usr/bin/fd) and `bat` is bat's `batcat` (bacula-console-qt has /usr/sbin/bat).
# A row is written when both hold:
#   1. Contents: the package ships the installed name R (in bin, sbin, usr/bin, usr/sbin or usr/games) but not the
#      command C, and a package of another source ships C (the clash). Either C is the package's or its source's name
#      (without the rust-, golang-, python-, node-, ruby- or haskell- prefix), one of its leading dash parts or the
#      initials of its dash parts, and R is C with at most four letters added before or after it; or R is C with one
#      of those names of three letters or more, without a dash, joined before or after it (num-utils' prefix "num").
#   2. Debian's own words: a paragraph of the source's debian/README.Debian, debian/NEWS or debian/changelog (from
#      sources.debian.org, at the version in Packages) says why (renamed, clash, conflict, collides, already used), and
#      one of its sentences names C and then R, with "to", "into", "as", "is" or "it's" between them ("renamed from
#      'bat' to 'batcat'", "install fd into ... a symlink from this file to /usr/bin/fdfind").
# Each row's fourth field orders the offer by Debian's popularity contest: "first" when the package has more
# installations than every package that ships C (fd-find against fdclone), so it is named before them; "after" when
# the program under the name is the more installed one (moreutils' ts against task-spooler's tsp), so it is named
# after them. Every rename Debian's own words document is kept: none is left out.
# Usage: make-renamed.py --data DIR --evidence DIR [--fetch] --out renamed-commands --report report.tsv
#   DIR holds Debian's indexes, decompressed: Contents-*.txt (lines under bin and sbin), Packages-*, popcon-by_inst.gz.
#   --evidence keeps the Debian texts read (one folder per source and version); --fetch downloads the missing ones.
# Last update 2026/11/02
import argparse, collections, glob, gzip, os, re, sys, time, urllib.parse, urllib.request

PREFIXES = ('rust-', 'golang-', 'python-', 'node-', 'ruby-', 'haskell-')
DIRS = ('bin/', 'sbin/', 'usr/bin/', 'usr/sbin/', 'usr/games/')
WHY = re.compile(r'renam|clash|conflict|collid|collision|already (used|taken|in use|exists)', re.I)
TEXTS = ('debian/README.Debian', 'debian/NEWS', 'debian/changelog')


def read_packages(data):
    info = {}
    for path in sorted(glob.glob(os.path.join(data, 'Packages-*'))):
        component = os.path.basename(path).split('-')[1]
        component = 'non-free' if component == 'non' else component
        stanza = {}
        for line in open(path, encoding='utf-8', errors='replace'):
            if line.strip() == '':
                if 'Package' in stanza:
                    name = stanza['Package']
                    src, _, ver = stanza.get('Source', name).partition(' ')
                    ver = ver.strip('()') or stanza.get('Version', '')
                    info.setdefault(name, (src, ver, component))
                stanza = {}
            elif not line.startswith(' ') and ':' in line:
                key, _, value = line.partition(':')
                stanza[key] = value.strip()
    return info


def read_contents(data):
    commands, shipped = collections.defaultdict(set), collections.defaultdict(set)
    for path in sorted(glob.glob(os.path.join(data, 'Contents-*.txt'))):
        for line in open(path, encoding='utf-8', errors='replace'):
            try:
                name, packages = line.rstrip('\n').rsplit(None, 1)
            except ValueError:
                continue
            if not name.startswith(DIRS):
                continue
            command = os.path.basename(name)
            for package in packages.split(','):
                package = package.rsplit('/', 1)[-1]
                commands[command].add(package)
                shipped[package].add(command)
    return commands, shipped


def read_popcon(data):
    installs = {}
    with gzip.open(os.path.join(data, 'popcon-by_inst.gz'), 'rt', encoding='utf-8', errors='replace') as fp:
        for line in fp:
            fields = line.split()
            if len(fields) > 2 and fields[0].isdigit():
                installs[fields[1]] = int(fields[2])
    return installs


def names_of(package, src):
    names = set()
    for name in {package, src}:
        for prefix in PREFIXES:
            if name.startswith(prefix):
                name = name[len(prefix):]
        parts = name.split('-')
        names.update('-'.join(parts[:i]) for i in range(1, len(parts) + 1))
        if len(parts) > 1:
            names.add(''.join(part[0] for part in parts if part))
    return names


def candidates(info, commands, shipped):
    rows = []
    for package, own in sorted(shipped.items()):
        src = info.get(package, (package, '', 'main'))[0]
        for command in sorted(names_of(package, src)):
            if len(command) < 2 or command in own:
                continue
            clash = sorted(q for q in commands.get(command, ()) if info.get(q, (q,))[0] != src)
            if not clash:
                continue
            for real in sorted(own):
                extra = real[len(command):] if real.startswith(command) else real[:-len(command)] if real.endswith(command) else None
                if extra and re.fullmatch(r'[a-z]{1,4}', extra):
                    rows.append((command, package, real, src, clash))
    # R is C with a dash-free name of the package joined to it (num-utils: average to numaverage)
    for package, own in sorted(shipped.items()):
        src = info.get(package, (package, '', 'main'))[0]
        for part in sorted(n for n in names_of(package, src) if len(n) > 2 and '-' not in n):
            for real in sorted(own):
                for command in (real[len(part):] if real.startswith(part) else '', real[:-len(part)] if real.endswith(part) else ''):
                    if len(command) < 2 or command in own or not re.fullmatch(r'[a-z][a-z0-9]*', command):
                        continue
                    clash = sorted(q for q in commands.get(command, ()) if info.get(q, (q,))[0] != src)
                    if clash and (command, package, real, src, clash) not in rows:
                        rows.append((command, package, real, src, clash))
    return sorted(rows)


def evidence_path(evidence, src, ver, text):
    return os.path.join(evidence, src, ver, text.replace('/', '_'))


def fetch(evidence, src, ver, component):
    for text in TEXTS:
        path = evidence_path(evidence, src, ver, text)
        if os.path.exists(path) or os.path.exists(path + '.none'):
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        initial = src[:4] if src.startswith('lib') else src[0]
        url = 'https://sources.debian.org/data/%s/%s/%s/%s/%s' % (
            component, initial, src, urllib.parse.quote(ver), text)
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=60) as reply:
                    body = reply.read()
                with open(path, 'wb') as fp:
                    fp.write(body)
                break
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
                open(path + '.none', 'w').close()
                break
            except (urllib.error.URLError, OSError):
                # a dropped connection is tried again, then stops the run
                if attempt == 3:
                    raise
                time.sleep(5 * (attempt + 1))
        time.sleep(0.5)


def debian_words(evidence, src, ver, command, real):
    word = lambda w: r'(?<![\w.-])' + re.escape(w) + r'(?![\w-])'
    # C, then within the sentence "to", "into", "as", "is" or "it's", then R
    renamed = re.compile(word(command) + r'(?:(?!\.\s).){0,120}?\b(?:to|into|as|is|it\'s)\b(?:(?!\.\s).){0,60}?' + word(real), re.S)
    for text in TEXTS:
        path = evidence_path(evidence, src, ver, text)
        if not os.path.exists(path):
            continue
        body = open(path, encoding='utf-8', errors='replace').read()
        # README and NEWS paragraphs are separated by empty lines, changelog items start with an asterisk
        parts = re.split(r'\n\s*\n|\n(?=\s+[*-] )', body)
        for part in parts:
            if WHY.search(part) and renamed.search(' '.join(part.split())):
                return text, ' '.join(part.split())
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--out', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    info = read_packages(args.data)
    commands, shipped = read_contents(args.data)
    installs = read_popcon(args.data)
    table, report = [], []
    for command, package, real, src, clash in candidates(info, commands, shipped):
        ver, component = info.get(package, (src, '', 'main'))[1:]
        if args.fetch:
            fetch(args.evidence, src, ver, component)
        words = debian_words(args.evidence, src, ver, command, real)
        mine, theirs = installs.get(package, 0), max(installs.get(q, 0) for q in clash)
        order = 'first' if mine > theirs else 'after'
        if not words:
            verdict = 'no Debian text'
        else:
            verdict = 'written, ' + order
            table.append((command, package, real, order, src, ver, words[0]))
        report.append((verdict, command, package, real, ','.join(clash), '%d/%d' % (mine, theirs),
                       '%s %s %s' % (src, ver, words[0]) if words else '', words[1][:300] if words else ''))
    with open(args.report, 'w') as fp:
        fp.write('verdict\tcommand\tpackage\tinstalled as\tpackages with the command\tpopcon installs (package/most of the others)\tDebian text\tits words\n')
        for row in sorted(report):
            fp.write('\t'.join(row) + '\n')
    seen = collections.Counter(row[0] for row in table)
    duplicates = [command for command, n in seen.items() if n > 1]
    if duplicates:
        sys.exit('make-renamed: more than one renamed package for %s; see %s' % (', '.join(duplicates), args.report))
    with open(args.out, 'w') as fp:
        fp.write('# Commands that Debian installs under another name, because another package has the name (Debian Policy 10.1).\n')
        fp.write('# command-not-found names the package of each row, with the name to run, before the packages that have the\n')
        fp.write('# command under its own name ("first") or after them ("after"), as Debian\'s popularity contest ranks them.\n')
        fp.write('# Made by make-renamed.py from Debian forky\'s Contents, Packages and popularity contest and each source\'s own\n')
        fp.write('# README.Debian, NEWS or changelog (the file named per row).\n')
        fp.write('# Each row: the command, the package, the name it is installed as, first or after; the line above it names the\n')
        fp.write('# Debian text.\n')
        for command, package, real, order, src, ver, text in sorted(table):
            fp.write('# %s %s, %s\n%s\t%s\t%s\t%s\n' % (src, ver, text, command, package, real, order))
    print('make-renamed: %d candidates, %d rows' % (len(report), len(table)))


main()
