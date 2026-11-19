#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Installer-owned, pinned model profiles. The package's debconf question owns consent."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

class HttpsRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        if urllib.parse.urlsplit(new_url).scheme != 'https':
            raise ValueError('HTTPS')
        return super().redirect_request(request, fp, code, message, headers, new_url)


opener = urllib.request.build_opener(HttpsRedirect())
DATA = Path('/usr/share/sparky-install-models')
STATE = Path('/var/lib/sparky-install-models')
sys.path.insert(0, '/usr/lib/sparky-stereo-apt')
import sparky_install_downloads as notice


def words(key, **values):
    texts = json.loads((DATA / 'messages.json').read_text())
    return texts.get(notice.language(), texts['en'])[key].format(**values)


def profile(identifier):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', identifier):
        raise ValueError(identifier)
    p = json.loads((DATA / 'profiles' / (identifier + '.json')).read_text())
    if p['package'] != identifier or not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', p['package']):
        raise ValueError(identifier)
    root = Path(p['root'])
    if not root.is_absolute() or not str(root).startswith('/var/lib/') or '..' in root.parts:
        raise ValueError(p['root'])
    for f in p['files']:
        rel = Path(f['file'])
        if rel.is_absolute() or '..' in rel.parts or not re.fullmatch(r'[a-f0-9]{64}', f['sha256']):
            raise ValueError(f['file'])
        if urllib.parse.urlsplit(f['url']).scheme != 'https' or not isinstance(f['bytes'], int) or f['bytes'] <= 0:
            raise ValueError(f['file'])
    if p['download_bytes'] != sum(f['bytes'] for f in p['files']):
        raise ValueError(identifier)
    return p


def owned_directory(path):
    """Refuse a symbolic-link parent before any create or deletion."""
    path = Path(path)
    current = Path('/')
    for part in path.parts[1:]:
        current /= part
        if current.is_symlink():
            raise ValueError(str(current))
        current.mkdir(exist_ok=True, mode=0o755)
        st = current.stat()
        if st.st_uid != 0 or st.st_mode & 0o022:
            raise PermissionError(str(current))
    return path


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verified(path, artifact):
    return not path.is_symlink() and path.is_file() and path.stat().st_size == artifact['bytes'] and digest(path) == artifact['sha256']


def describe(p):
    print(words('plan', profile=p['title'], size=notice.human(p['download_bytes'])), flush=True)
    print(words('purge', package=p['package']), flush=True)
    for f in p['files']:
        print(f"{f['file']}: {f['bytes']} | {f['sha256']} | {f['url']}", flush=True)
    row = dict(package=p['package'], version=p['version'], size=p['download_bytes'], source=p['files'][0]['url'])
    for line in notice.assess([row], question='not-asked')['text']:
        print(line, flush=True)


def terms(p):
    notes = p.get('licence_notes', {})
    if notes:
        print(notes.get(notice.language(), notes['en']), flush=True)
    for licence in p['licences']:
        print(licence['name'] + '\n' + licence['url'], flush=True)
        body = (DATA / 'licences' / licence['file']).read_bytes()
        if licence.get('sha256') and hashlib.sha256(body).hexdigest() != licence['sha256']:
            raise ValueError(licence['file'] + ': SHA256')
        print(body.decode('utf-8'), flush=True)


def install(p, consent):
    describe(p)
    terms(p)
    if p['consent_required'] and not consent:
        print(words('declined'), file=sys.stderr)
        return 1
    root = owned_directory(p['root'])
    owned_directory(STATE / 'receipts')
    with (STATE / 'install.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        work = Path(tempfile.mkdtemp(prefix='.model-install-', dir=root))
        os.chmod(work, 0o700)
        files = []
        try:
            owned = set()
            for receipt in (STATE / 'receipts').glob('*.json'):
                record = json.loads(receipt.read_text())
                if record['root'] == str(root):
                    owned.update(record['files'])
            unowned = set()
            for f in p['files']:
                path = root / f['file']
                owned_directory(path.parent)
                if path.is_symlink():
                    raise ValueError(str(path))
                if path.exists() and f['file'] not in owned:
                    if not verified(path,f):
                        raise PermissionError(str(path))
                    unowned.add(f['file'])
            generated = p.get('generated_files', [])
            for name in generated:
                path = root / name
                owned_directory(path.parent)
                if path.is_symlink() or (path.exists() and name not in owned):
                    raise PermissionError(str(path))
            missing = [f for f in p['files'] if not verified(root / f['file'], f)]
            need = sum(f['bytes'] for f in missing)
            if shutil.disk_usage(root).free < need + p.get('postprocess_disk_bytes', 0) + 128 * 1024 * 1024:
                raise OSError('ENOSPC')
            for i, f in enumerate(missing):
                # A replaced upstream object is refused before transferring its body.
                request = urllib.request.Request(f['url'], method='HEAD')
                with opener.open(request, timeout=60) as response:
                    size = response.headers.get('x-linked-size') or response.headers.get('Content-Length')
                    if size is not None and int(size) != f['bytes']:
                        raise ValueError(f['file'] + ': size')
                print(words('download', file=f['file']), flush=True)
                target = work / str(i)
                with opener.open(f['url'], timeout=60) as response, target.open('xb') as output:
                    if urllib.parse.urlsplit(response.geturl()).scheme != 'https':
                        raise ValueError(f['file'] + ': HTTPS')
                    h = hashlib.sha256()
                    length = 0
                    for block in iter(lambda: response.read(1024 * 1024), b''):
                        length += len(block)
                        if length > f['bytes']:
                            raise ValueError(f['file'] + ': size')
                        h.update(block)
                        output.write(block)
                    output.flush()
                    os.fsync(output.fileno())
                if length != f['bytes'] or h.hexdigest() != f['sha256']:
                    raise ValueError(f['file'] + ': SHA256/size')
                files.append((f, target))
            for f, target in files:
                destination = root / f['file']
                owned_directory(destination.parent)
                if destination.is_symlink():
                    raise ValueError(str(destination))
                target.chmod(0o644)
                target.replace(destination)
            receipt = dict(profile=p['package'], package=p['package'], group=p['group'], root=str(root),
                           files=[f['file'] for f in p['files'] if f['file'] not in unowned] + generated,
                           profile_sha256=hashlib.sha256(json.dumps(p, sort_keys=True).encode()).hexdigest())
            temp = STATE / 'receipts' / (p['package'] + '.json.new')
            temp.write_text(json.dumps(receipt, indent=2) + '\n')
            temp.chmod(0o644)
            temp.replace(temp.with_suffix(''))
            if p.get('postprocess'):
                env = dict(os.environ, XDG_CONFIG_HOME=str(work / 'config'), XDG_CACHE_HOME=str(work / 'cache'))
                subprocess.run(p['postprocess'], env=env, check=True)
                for name in p.get('generated_verified', []):
                    path = root / name
                    if path.is_symlink() or not path.is_file():
                        raise ValueError(name)
                    sidecar = path.with_name(path.name + '.sha256')
                    if sidecar.is_symlink():
                        raise ValueError(str(sidecar))
                    sidecar.write_text(digest(path) + '\n')
                    sidecar.chmod(0o644)
        finally:
            shutil.rmtree(work)
    print(words('done', profile=p['title']), flush=True)
    return 0


def purge_unlocked(identifier):
    receipt = STATE / 'receipts' / (identifier + '.json')
    if not receipt.is_file():
        return
    data = json.loads(receipt.read_text())
    root = owned_directory(data['root'])
    print(words('purge', package=data['package']), flush=True)
    shared = set()
    for other in receipt.parent.glob('*.json'):
        if other != receipt:
            record = json.loads(other.read_text())
            if record['root'] == str(root):
                shared.update(record['files'])
    for name in data['files']:
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(name)
        if name not in shared:
            path = root / relative
            owned_directory(path.parent)
            if path.is_symlink():
                raise ValueError(str(path))
            path.unlink(missing_ok=True)
    receipt.unlink()


def purge(identifier):
    owned_directory(STATE / 'receipts')
    with (STATE / 'install.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        purge_unlocked(identifier)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=['plan', 'terms', 'install', 'purge', 'purge-group'])
    parser.add_argument('profile')
    parser.add_argument('--consented', action='store_true')
    args = parser.parse_args()
    if args.operation in ('install', 'purge', 'purge-group') and os.geteuid() != 0:
        print(words('root'), file=sys.stderr)
        return 1
    if args.operation == 'purge':
        purge(args.profile)
    elif args.operation == 'purge-group':
        for path in (STATE / 'receipts').glob('*.json'):
            if json.loads(path.read_text())['group'] == args.profile:
                purge(path.stem)
    else:
        p = profile(args.profile)
        if args.operation == 'terms':
            print(words('consent', profile=p['title']))
            terms(p)
        elif args.operation == 'plan':
            describe(p)
        else:
            return install(p, args.consented)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        print(words('failed', reason=str(error)), file=sys.stderr)
        sys.exit(1)
