#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""The repository watcher of sparky-pjeoffice: does CNJ publish a version other than the reviewed one, and is its file the same twice?

It runs in the repository (by hand or from a job that someone with the right to schedules it), never on a person's machine, and it
approves nothing. It reads TRF3's user guide for the Linux x64 link, CNJ's update address for the version CNJ names, fetches the file
twice into new folders, and compares: the two fetches with each other, with the server's Content-Length, and (as a fact, never as
trust) with the SHA-256 the server keeps in the object's metadata. When the version differs from the catalogue it writes a PROPOSAL
(a catalogue with the new entry, and the facts a reviewer reads: the bundled Java, the launcher and updater files compared with the
reviewed version's) and exits 3. A person reviews it; only a person changes catalogue/catalogue.json.

Exit status: 0 the published version is the reviewed one and its file is unchanged; 3 a new version, fetched twice alike: a proposal
was written; 2 the two fetches (or the size) disagree: nothing is proposed; 1 anything else that went wrong (the reason is said).
Usage: watch.py --catalogue FILE --workdir DIR [--guide-url URL] [--update-url URL] [--proposal FILE] [--report FILE] [--user-agent TEXT]
"""
import argparse
import hashlib
import json
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

GUIDE = 'https://pjeoffice.trf3.jus.br/pjeoffice-pro/docs/userguide.html'
LINK = re.compile(r'''href=["']([^"']*pjeoffice-pro-v([0-9][0-9A-Za-z.]*)-linux_x64\.zip)["']''')


class Disagreement(Exception):
    pass


def https_only(url):
    if urllib.parse.urlsplit(url).scheme != 'https':
        raise ValueError('%s is not an https address' % url)
    return url


def get(url, user_agent, limit=None):
    request = urllib.request.Request(https_only(url), headers={'User-Agent': user_agent})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read(limit), dict(response.headers)


def fetch_file(url, folder, user_agent):
    """Fetch the file into a new, empty folder; the size read is compared with Content-Length. Returns the path, size, SHA-256, headers."""
    folder.mkdir()
    target = folder / url.rsplit('/', 1)[-1]
    request = urllib.request.Request(https_only(url), headers={'User-Agent': user_agent})
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(request, timeout=300) as response, target.open('wb') as stream:
        headers = dict(response.headers)
        for block in iter(lambda: response.read(1 << 20), b''):
            stream.write(block)
            digest.update(block)
            size += len(block)
    declared = headers.get('Content-Length')
    if declared is not None and int(declared) != size:
        raise Disagreement('%s: Content-Length %s, received %d' % (url, declared, size))
    return target, size, digest.hexdigest(), headers


def facts(archive, top):
    """What a reviewer reads about a new file, compared with the reviewed expectations in the catalogue."""
    found = {}
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        found['entries'] = len(names)
        found['top_folders'] = sorted({name.split('/')[0] for name in names})
        found['top_matches_catalogue'] = found['top_folders'] == [top]
        found['has'] = {part: any(name == top + '/' + part for name in names)
                        for part in ('pjeoffice-pro.jar', 'cutplayer4jfx.jar', 'jre/bin/java', 'pjeoffice-update.properties', 'pjeoffice-pro.sh', 'ffmpeg.exe')}
        try:
            release = bundle.read(top + '/jre/release').decode('utf-8', 'replace')
            found['jre_release'] = dict(re.findall(r'^(JAVA_VERSION|IMPLEMENTOR_VERSION)="?([^"\n]*)"?', release, re.M))
        except KeyError:
            found['jre_release'] = None
        try:
            properties = bundle.read(top + '/pjeoffice-update.properties').decode('utf-8', 'replace')
            found['update_properties'] = {key: value.strip() for key, value in re.findall(r'(?m)^\s*(update\.[a-z.]+)\s*=\s*(.*)$', properties)}
        except KeyError:
            found['update_properties'] = None
        try:
            launcher = bundle.read(top + '/pjeoffice-pro.sh').decode('utf-8', 'replace')
            found['launcher_sha256'] = hashlib.sha256(launcher.encode()).hexdigest()
            found['launcher_java_flags'] = sorted(set(re.findall(r'^\s*(-[A-Za-z][^\s\\]*)', launcher, re.M)))
        except KeyError:
            found['launcher_sha256'] = None
    return found


def run(args):
    catalogue = json.loads(Path(args.catalogue).read_text(encoding='utf-8'))
    reviewed = catalogue['current']
    entry = catalogue['versions'][reviewed]
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    report = {'reviewed': reviewed}
    page, _ = get(args.guide_url, args.user_agent, 4 << 20)
    links = LINK.findall(page.decode('utf-8', 'replace'))
    if not links:
        raise ValueError('%s names no Linux x64 file (pjeoffice-pro-vVERSION-linux_x64.zip)' % args.guide_url)
    urls = sorted({url for url, _ in links})
    if len(urls) != 1:
        raise ValueError('%s names %d different Linux x64 files: %s' % (args.guide_url, len(urls), ', '.join(urls)))
    url, version = urls[0], links[0][1]
    url = urllib.parse.urljoin(args.guide_url, url)
    report.update({'published': version, 'url': url})
    if args.update_url:
        text, _ = get(args.update_url, args.user_agent, 1 << 16)
        named = re.search(r'(?m)^\s*app\.version\s*=\s*(\S+)', text.decode('utf-8', 'replace'))
        report['update_properties_version'] = named.group(1) if named else None
    first = fetch_file(url, Path(tempfile.mkdtemp(dir=workdir)) / 'first', args.user_agent)
    second = fetch_file(url, Path(tempfile.mkdtemp(dir=workdir)) / 'second', args.user_agent)
    report['first'] = {'size': first[1], 'sha256': first[2]}
    report['second'] = {'size': second[1], 'sha256': second[2]}
    if first[1] != second[1] or first[2] != second[2]:
        raise Disagreement('the two fetches differ: %d bytes %s against %d bytes %s' % (first[1], first[2], second[1], second[2]))
    stated = first[3].get('x-amz-meta-sha256')
    if stated:
        report['server_metadata_sha256'] = stated
        report['server_metadata_agrees'] = stated == first[2]
    report['facts'] = facts(first[0], entry['top'])
    same = version == reviewed and first[1] == entry['size'] and first[2] == entry['sha256']
    report['same_as_reviewed'] = same
    if version == reviewed and not same:
        raise Disagreement('CNJ names %s, the reviewed version, but its file is not the reviewed one: %d bytes %s, reviewed %d bytes %s'
                           % (version, first[1], first[2], entry['size'], entry['sha256']))
    if not same:
        proposed = json.loads(json.dumps(catalogue))
        proposed['current'] = version
        proposed['versions'][version] = {'url': url, 'size': first[1], 'sha256': first[2], 'top': entry['top'], 'java': entry.get('java', '1.8.0'),
                                         'reviewed': 'NOT REVIEWED: ' + 'the reviewer sets this to the date of the review'}
        if args.proposal:
            Path(args.proposal).write_text(json.dumps(proposed, indent=1) + '\n', encoding='utf-8')
        report['proposal'] = args.proposal
    return report, (0 if same else 3)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--catalogue', required=True)
    parser.add_argument('--workdir', required=True)
    parser.add_argument('--guide-url', default=GUIDE)
    parser.add_argument('--update-url', default='https://pje-office.pje.jus.br/pro/update.properties')
    parser.add_argument('--proposal')
    parser.add_argument('--report')
    parser.add_argument('--user-agent', default='sparky-pjeoffice-watcher')
    args = parser.parse_args(argv)
    try:
        report, code = run(args)
    except Disagreement as error:
        print('DISAGREEMENT: %s' % error, file=sys.stderr)
        return 2
    except (OSError, ValueError, urllib.error.URLError, KeyError, zipfile.BadZipFile) as error:
        print('ERROR: %s: %s' % (type(error).__name__, error), file=sys.stderr)
        return 1
    text = json.dumps(report, indent=1, sort_keys=True)
    print(text)
    if args.report:
        Path(args.report).write_text(text + '\n', encoding='utf-8')
    return code


if __name__ == '__main__':
    sys.exit(main())
