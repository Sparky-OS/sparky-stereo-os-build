# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""The installer and the commands of sparky-pjeoffice.

PJeOffice Pro is CNJ's program. Nothing of it is in this package: the official ZIP is fetched from CNJ's own address on the
person's machine, checked against the size and SHA-256 a reviewer wrote into the catalogue, and only then unpacked into a
folder of its own under /opt/pjeoffice-pro/versions. The launcher reads the symbolic link /opt/pjeoffice-pro/current, which is
switched after every check has passed, so a failure at any step leaves the version that was in use in use.

    install     fetch (or resume), verify, unpack, qualify, make the certificate list, switch
    remove      take the program away; the person's certificates, settings and files are never touched
    rollback    use the previous version again
    trust       make the program's certificate list again from its own and the system's
    status      what is installed, in words or as JSON
    check       ask CNJ's update address whether it names another version (informational; never changes anything)
    sign-pdf    sign a PDF through the program's own supported entry point (a CAdES file beside the PDF)
    launch      start the program (and the tray) for the person
"""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile


PACKAGE = 'sparky-pjeoffice'
PROGRAM = '/opt/pjeoffice-pro'
VERSIONS = PROGRAM + '/versions'
CURRENT = PROGRAM + '/current'
STATE_DIR = '/var/lib/sparky-pjeoffice'
STATE_FILE = STATE_DIR + '/state.json'
TRUST_DIR = STATE_DIR + '/trust'
FFMPEG_DIR = STATE_DIR + '/ffmpeg'
CACHE = '/var/cache/sparky-pjeoffice'
CATALOGUE = '/usr/share/sparky-pjeoffice/catalogue.json'
LANGDIR = '/usr/share/sparky-pjeoffice/lang'
SYSTEM_TLS = '/etc/ssl/certs/ca-certificates.crt'
SYSTEM_FFMPEG = '/usr/bin/ffmpeg'
CODEC = '/usr/lib/sparky-pjeoffice/codec'
ENGINE = '/usr/bin/sparky-stereo-problems'
KEYSTORE_PASSWORD = 'pjeoffice'
MERGE_SCRIPT = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'merge-trust.js')
KEYSTORE_RESOURCE = 'pjeoffice.jks'
SIGNER_URL = 'http://127.0.0.1:8800/pjeOffice/?u=18'
EXECUTABLES = ('ffmpeg.exe', 'pjeoffice-pro.sh', 'jre/lib/jexec', 'jre/lib/jspawnhelper')
EXIT_KEPT = 10   # the install failed and the version that was in use is still in use
VERSION_PATTERN = re.compile(r'[0-9]+(\.[0-9]+)*[A-Za-z]?')
MAX_UNPACKED = 2 << 30


class Failure(Exception):
    """A step that cannot do what it is for: key is the problem's key, message its LOCAL number, args its arguments."""

    def __init__(self, key, message, args, reason):
        super().__init__(reason)
        self.key, self.message, self.args_, self.reason = key, message, args, reason


# ---- words ---------------------------------------------------------------------------------------------------------

def _language_files():
    seen, order = set(), []
    for name in os.environ.get('LANGUAGE', '').split(':') + [os.environ.get('LC_ALL', ''), os.environ.get('LC_MESSAGES', ''),
                                                              os.environ.get('LANG', '')]:
        code = name.split('.')[0].split('@')[0]
        if not re.fullmatch(r'[A-Za-z]{2,3}(_[A-Za-z0-9]+)?', code or ''):
            continue
        for candidate in (code, code.split('_')[0]):
            if candidate not in seen:
                seen.add(candidate)
                order.append(candidate)
    return order + ['en']


def _read_lang(code):
    path = os.path.join(LANGDIR, code)
    table = {}
    if os.path.isfile(path):
        with open(path, encoding='utf-8') as stream:
            for line in stream:
                found = re.fullmatch(r'(LOCAL[0-9]+)="(.*)"\n?', line)
                if found:
                    table[found.group(1)] = found.group(2).replace('\\"', '"')
    return table


def say(message, *args):
    """A line for the person, in their language (the lookup order of the problems engine: the whole name, the bare language, English)."""
    for code in _language_files():
        text = _read_lang(code).get(message)
        if text:
            break
    else:
        text = message
    return text % args if args else text


def out(message, *args):
    print(say(message, *args), flush=True)


def human(count):
    if count >= 1 << 30:
        return '%.2f GiB' % (count / (1 << 30))
    if count >= 1 << 20:
        return '%.1f MiB' % (count / (1 << 20))
    return '%.1f KiB' % (count / 1024)


# ---- the catalogue ------------------------------------------------------------------------------------------------

def load_catalogue(path=None):
    """The reviewed catalogue: the one version this package installs, with its address, size and SHA-256."""
    path = path or CATALOGUE
    with open(path, encoding='utf-8') as stream:
        data = json.load(stream)
    current = data.get('current')
    entry = data.get('versions', {}).get(current)
    if not isinstance(current, str) or not VERSION_PATTERN.fullmatch(current) or not isinstance(entry, dict):
        raise ValueError('%s: "current" does not name a version of "versions"' % path)
    if not re.fullmatch(r'https://[^\s/]+/[^\s]+', entry.get('url', '')):
        raise ValueError('%s: the address of %s is not an https address' % (path, current))
    if not isinstance(entry.get('size'), int) or entry['size'] <= 0:
        raise ValueError('%s: the size of %s is not a number of bytes' % (path, current))
    if not re.fullmatch(r'[0-9a-f]{64}', entry.get('sha256', '')):
        raise ValueError('%s: the SHA-256 of %s is not 64 lowercase hexadecimal digits' % (path, current))
    if not re.fullmatch(r'[A-Za-z0-9._-]+', entry.get('top', '')):
        raise ValueError('%s: "top" of %s is not a folder name' % (path, current))
    return current, entry, data


# ---- state, locks, the engine --------------------------------------------------------------------------------------

def read_state():
    try:
        with open(STATE_FILE, encoding='utf-8') as stream:
            return json.load(stream)
    except FileNotFoundError:
        return {}


def write_state(state):
    os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=STATE_DIR, prefix='.state-')
    with os.fdopen(handle, 'w', encoding='utf-8') as stream:
        json.dump(state, stream, indent=1, sort_keys=True)
        stream.write('\n')
    os.chmod(temporary, 0o644)
    os.replace(temporary, STATE_FILE)


class Lock:
    def __init__(self):
        os.makedirs(STATE_DIR, mode=0o755, exist_ok=True)
        self.stream = open(STATE_DIR + '/lock', 'a+')

    def __enter__(self):
        try:
            fcntl.lockf(self.stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise Failure('install', 'LOCAL10', [], 'another installation of PJeOffice Pro is running')
        return self

    def __exit__(self, *unused):
        self.stream.close()


def engine(*arguments):
    """The one engine keeps a failure until it is repaired (Daniel, 2026-11-02); its own failure is said, never swallowed."""
    result = subprocess.run([ENGINE, *arguments], capture_output=True, text=True)
    if result.returncode:
        print('sparky-stereo-problems %s: %s' % (arguments[0], (result.stderr or result.stdout).strip()), file=sys.stderr)


def keep(failure):
    engine('keep', '--machine', '--repair', json.dumps(['/usr/bin/sparky-pjeoffice', 'install']), PACKAGE, failure.key,
           failure.message, *[str(each) for each in failure.args_])


def clear(key):
    engine('clear', '--machine', PACKAGE, key)


# ---- fetch and verify ----------------------------------------------------------------------------------------------

def sha256_of(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch(version, entry, destination):
    """Fetch the ZIP into destination + '.part' (a partial file is resumed, as the server allows) and return its path once the
    transfer ended. Nothing is trusted yet: verify() decides."""
    os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
    part = destination + '.part'
    if os.path.exists(part) and os.path.getsize(part) > entry['size']:
        os.unlink(part)
    if os.path.exists(part) and os.path.getsize(part):
        out('LOCAL40', human(os.path.getsize(part)), human(entry['size']))
    command = ['curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '30',
               '--max-time', '7200', '--continue-at', '-', '--output', part]
    if not sys.stderr.isatty():
        command.append('--silent')
        command.append('--show-error')
    else:
        command.append('--progress-bar')
    command.append(entry['url'])
    result = subprocess.run(command)
    if result.returncode:
        have = os.path.getsize(part) if os.path.exists(part) else 0
        raise Failure('install', 'LOCAL2', [version, 'curl %d, %s of %s received' % (result.returncode, human(have), human(entry['size']))],
                      'the download from %s ended with curl status %d' % (entry['url'], result.returncode))
    os.replace(part, destination)
    return destination


def verify(version, entry, path):
    """The reviewed size and SHA-256, or the file is deleted and the failure says what differed."""
    size = os.path.getsize(path)
    digest = sha256_of(path)
    if size != entry['size']:
        detail = 'size %d, reviewed %d' % (size, entry['size'])
    elif digest != entry['sha256']:
        detail = 'SHA-256 %s, reviewed %s' % (digest, entry['sha256'])
    else:
        return
    os.unlink(path)
    raise Failure('install', 'LOCAL3', [version, detail], 'the file fetched from CNJ is not the reviewed one: ' + detail)


# ---- unpack and qualify --------------------------------------------------------------------------------------------

def unpack(archive, top, target):
    """Unpack the ZIP's one top folder into target with safe names, and set the modes the ZIP does not carry (it has none)."""
    with zipfile.ZipFile(archive) as bundle:
        total = sum(each.file_size for each in bundle.infolist())
        if total > MAX_UNPACKED:
            raise ValueError('the archive unpacks to %s, more than the %s allowed' % (human(total), human(MAX_UNPACKED)))
        os.makedirs(target, mode=0o755)
        root = os.path.realpath(target)
        for info in bundle.infolist():
            name = info.filename
            if name.startswith('/') or '\\' in name or '..' in name.split('/'):
                raise ValueError('unsafe name in the archive: %r' % name)
            if (info.external_attr >> 28) in (0xA, 0x2, 0x6, 0x1):
                raise ValueError('the archive holds a link or a device: %r' % name)
            if not name.startswith(top + '/'):
                raise ValueError('%r is outside the folder %s of the archive' % (name, top))
            relative = name[len(top) + 1:]
            if not relative:
                continue
            path = os.path.realpath(os.path.join(target, relative))
            if not (path + os.sep).startswith(root + os.sep):
                raise ValueError('%r leaves the target folder' % name)
            if info.is_dir():
                os.makedirs(path, mode=0o755, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(path), mode=0o755, exist_ok=True)
            with bundle.open(info) as source, open(path, 'wb') as sink:
                shutil.copyfileobj(source, sink)
            executable = relative in EXECUTABLES or relative.startswith('jre/bin/')
            os.chmod(path, 0o755 if executable else 0o644)
    return target


def manifest(target):
    """SHA-256 of every file as CNJ shipped it, kept beside the program so a later check can tell what is the program's own."""
    lines = []
    for folder, directories, files in os.walk(target):
        directories.sort()
        for name in sorted(files):
            path = os.path.join(folder, name)
            lines.append('%s  %s' % (sha256_of(path), os.path.relpath(path, target)))
    return '\n'.join(lines) + '\n'


def prepare(target, entry):
    """Our one change inside the unpacked tree: CNJ's own updater is switched off (update.url=disabled), the package updates it.
    The original file stays beside it, and the manifest is made first."""
    with open(os.path.join(target, 'SHA256SUMS.cnj'), 'w', encoding='utf-8') as stream:
        stream.write(manifest(target))
    properties = os.path.join(target, 'pjeoffice-update.properties')
    shutil.copyfile(properties, properties + '.cnj')
    with open(properties, encoding='utf-8') as stream:
        text = stream.read()
    changed, count = re.subn(r'(?m)^update\.url\s*=.*$', 'update.url=disabled', text)
    if count != 1:
        raise ValueError('pjeoffice-update.properties has %d update.url lines, not one' % count)
    with open(properties, 'w', encoding='utf-8') as stream:
        stream.write(changed)
    with open(os.path.join(target, 'SPARKY-PJEOFFICE.txt'), 'w', encoding='utf-8') as stream:
        stream.write('Installed by sparky-pjeoffice from the official ZIP (SHA-256 %s).\n'
                     'Changed by the installer: pjeoffice-update.properties (update.url=disabled; the original is the .cnj file).\n'
                     'SHA256SUMS.cnj lists every file as CNJ shipped it.\n' % entry['sha256'])


def qualify(target, entry):
    """What can be checked before the program is switched in: the files are there, the jar is a whole ZIP and holds the
    certificate list, and the bundled Java runs and is the version the catalogue reviewed."""
    for needed in ('pjeoffice-pro.jar', 'cutplayer4jfx.jar', 'jre/bin/java', 'jre/bin/jjs', 'pjeoffice-update.properties'):
        if not os.path.isfile(os.path.join(target, needed)):
            raise ValueError('%s is missing from the program' % needed)
    jar = os.path.join(target, 'pjeoffice-pro.jar')
    with zipfile.ZipFile(jar) as bundle:
        broken = bundle.testzip()
        if broken:
            raise ValueError('%s is damaged inside pjeoffice-pro.jar' % broken)
        if KEYSTORE_RESOURCE not in bundle.namelist():
            raise ValueError('pjeoffice-pro.jar holds no %s' % KEYSTORE_RESOURCE)
    result = subprocess.run([os.path.join(target, 'jre/bin/java'), '-version'], capture_output=True, text=True, timeout=120)
    prefix = entry.get('java', '1.8.0')
    if result.returncode or ('"%s' % prefix) not in result.stderr:
        raise ValueError('the bundled Java does not run as the reviewed %s: %s' % (prefix, (result.stderr or result.stdout).strip()[:200]))


# ---- the certificate list ------------------------------------------------------------------------------------------

def make_trust(version, app, bundle_path=None):
    """The program's HTTPS codec reads its own certificate list from the jar and never the system's. The list made here keeps every
    original certificate exactly as it is and adds the system's TLS certificates, so the person's system trust (what Sparky CA or
    they added) reaches the program. The original certificates are never dropped: the program's own Java (jjs) writes the list and
    reads it back to check. A certificate Java cannot read is counted and said, never skipped silently."""
    bundle_path = bundle_path or SYSTEM_TLS
    jar = os.path.join(app, 'pjeoffice-pro.jar')
    jjs = os.path.join(app, 'jre/bin/jjs')
    try:
        sha256_of(bundle_path)
    except OSError as error:
        raise Failure('trust', 'LOCAL7', [str(error)], 'the system certificate list %s cannot be read: %s' % (bundle_path, error))
    folder = os.path.join(TRUST_DIR, version)
    os.makedirs(folder, mode=0o755, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=folder, prefix='.merge-') as work:
        original = os.path.join(work, 'original')
        with zipfile.ZipFile(jar) as bundle:
            data = bundle.read(KEYSTORE_RESOURCE)
        with open(original, 'wb') as stream:
            stream.write(data)
        kind = 'PKCS12' if data[:1] == b'\x30' else 'JKS' if data[:4] == bytes.fromhex('feedfeed') else None
        if kind is None:
            raise Failure('trust', 'LOCAL7', ['the program\'s certificate list is neither PKCS12 nor JKS'], 'unknown key store type')
        written = os.path.join(work, 'merged')
        result = subprocess.run([jjs, MERGE_SCRIPT, '--', kind, original, bundle_path, written, KEYSTORE_PASSWORD],
                                capture_output=True, text=True, timeout=300)
        if result.returncode or not os.path.isfile(written):
            reason = (result.stderr or result.stdout).strip().splitlines()
            raise Failure('trust', 'LOCAL7', [(reason[-1] if reason else 'jjs exited with %d' % result.returncode)[:240]],
                          'the certificate list could not be made: ' + ' '.join(reason[-3:]))
        counts = json.loads(result.stdout.strip().splitlines()[-1])
        os.chmod(written, 0o644)
        os.replace(written, os.path.join(folder, KEYSTORE_RESOURCE))
    if counts.get('skipped'):
        print('sparky-pjeoffice: %d certificate(s) of %s could not be read by the program\'s Java and were not added' % (counts['skipped'], bundle_path), file=sys.stderr)
    return {'bundle_sha256': sha256_of(bundle_path), 'original': counts['original'], 'added': counts['added'], 'skipped': counts['skipped'],
            'version': version, 'type': kind}


def ensure_ffmpeg_link():
    """ffmpeg_home is a folder holding a file named ffmpeg.exe; it is a link to the system's FFmpeg, never a copy of CNJ's static one."""
    if not os.path.exists(SYSTEM_FFMPEG):
        raise ValueError(SYSTEM_FFMPEG + ' is missing')
    os.makedirs(FFMPEG_DIR, mode=0o755, exist_ok=True)
    link = FFMPEG_DIR + '/ffmpeg.exe'
    if os.path.islink(link) and os.readlink(link) == SYSTEM_FFMPEG:
        return
    temporary = FFMPEG_DIR + '/.ffmpeg.exe.new'
    if os.path.lexists(temporary):
        os.unlink(temporary)
    os.symlink(SYSTEM_FFMPEG, temporary)
    os.replace(temporary, link)


# ---- switching -----------------------------------------------------------------------------------------------------

def in_use():
    try:
        return os.path.basename(os.readlink(CURRENT))
    except FileNotFoundError:
        return None
    except OSError:
        return None


def switch(version):
    """Point the stable link at the version. The link is made beside and renamed over the old one, so there is never a moment
    without a usable launcher target."""
    if os.path.lexists(CURRENT) and not os.path.islink(CURRENT):
        raise OSError('%s is not a link; it was not made by this installer and is left alone' % CURRENT)
    temporary = PROGRAM + '/.current.new'
    if os.path.lexists(temporary):
        os.unlink(temporary)
    os.symlink('versions/' + version, temporary)
    os.replace(temporary, CURRENT)


def prune(keep_versions):
    if os.path.isdir(VERSIONS):
        for name in sorted(os.listdir(VERSIONS)):
            if name not in keep_versions:
                shutil.rmtree(os.path.join(VERSIONS, name), ignore_errors=True)
    if os.path.isdir(TRUST_DIR):
        for name in sorted(os.listdir(TRUST_DIR)):
            if name not in keep_versions:
                shutil.rmtree(os.path.join(TRUST_DIR, name), ignore_errors=True)


def disk_check(version, entry, archive_free_path, program_free_path):
    need_archive = entry['size'] + (64 << 20)
    need_program = 1 << 30
    for path, need in ((archive_free_path, need_archive), (program_free_path, need_program)):
        os.makedirs(path, exist_ok=True)
        free = shutil.disk_usage(path).free
        if free < need:
            raise Failure('install', 'LOCAL6', [version, path, human(need), human(free)],
                          'not enough space in %s: %s free, %s needed' % (path, human(free), human(need)))


def install(catalogue_path=None):
    version, entry, _ = load_catalogue(catalogue_path)
    state = read_state()
    previous = in_use()
    with Lock():
        if previous == version and os.path.isdir(os.path.join(VERSIONS, version)) and os.path.isfile(os.path.join(TRUST_DIR, version, KEYSTORE_RESOURCE)):
            ensure_ffmpeg_link()
            if state.get('zip_sha256') == entry['sha256']:
                out('LOCAL36', version)
                clear('install')
                return 0
        archive = os.path.join(CACHE, 'pjeoffice-pro-%s.zip' % version)
        target = os.path.join(VERSIONS, version)
        staging = os.path.join(VERSIONS, '.%s.new' % version)
        try:
            disk_check(version, entry, CACHE, PROGRAM if os.path.isdir(PROGRAM) else os.path.dirname(PROGRAM))
            os.makedirs(VERSIONS, mode=0o755, exist_ok=True)
            if os.path.lexists(staging):
                shutil.rmtree(staging)
            if not (os.path.isfile(archive) and os.path.getsize(archive) == entry['size']):
                out('LOCAL30', version, human(entry['size']), entry['url'])
                fetch(version, entry, archive)
            out('LOCAL31')
            verify(version, entry, archive)
            try:
                out('LOCAL32')
                unpack(archive, entry['top'], staging)
                prepare(staging, entry)
                out('LOCAL33')
                qualify(staging, entry)
                if os.path.lexists(target):
                    aside = target + '.old'
                    shutil.rmtree(aside, ignore_errors=True)
                    os.rename(target, aside)
                os.replace(staging, target)
                out('LOCAL34')
                trust = make_trust(version, target)
                ensure_ffmpeg_link()
                switch(version)
            except Failure:
                raise
            except Exception as error:
                shutil.rmtree(staging, ignore_errors=True)
                aside = target + '.old'
                if os.path.isdir(aside):
                    shutil.rmtree(target, ignore_errors=True)
                    os.rename(aside, target)
                elif previous != version:
                    shutil.rmtree(target, ignore_errors=True)
                raise Failure('install', 'LOCAL4' if previous else 'LOCAL5',
                              [version, '%s: %s' % (type(error).__name__, error)] + ([previous] if previous else []),
                              '%s: %s' % (type(error).__name__, error))
        except Failure as failure:
            shutil.rmtree(staging, ignore_errors=True)
            if not in_use():
                shutil.rmtree(PROGRAM, ignore_errors=True)
                shutil.rmtree(TRUST_DIR, ignore_errors=True)
            keep(failure)
            print(failure.reason, file=sys.stderr)
            return EXIT_KEPT if in_use() else 1
        state.update({'installed': version, 'previous': previous if previous and previous != version else state.get('previous'),
                      'zip_sha256': entry['sha256'], 'installed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
                      'trust': trust, 'restart_pending': False})
        write_state(state)
        shutil.rmtree(target + '.old', ignore_errors=True)
        os.unlink(archive)
        keep_set = {version} | ({state['previous']} if state.get('previous') else set())
        prune(keep_set)
        for key in ('install', 'trust'):
            clear(key)
        out('LOCAL35', version)
        if state.get('previous'):
            out('LOCAL41', state['previous'])
    return 0


def regenerate_trust(only_if_changed=False):
    version = in_use()
    if not version:
        return 0
    state = read_state()
    try:
        bundle = sha256_of(SYSTEM_TLS)
    except OSError as error:
        failure = Failure('trust', 'LOCAL7', [str(error)], str(error))
        keep(failure)
        print(failure.reason, file=sys.stderr)
        return 1
    if only_if_changed and state.get('trust', {}).get('bundle_sha256') == bundle and os.path.isfile(os.path.join(TRUST_DIR, version, KEYSTORE_RESOURCE)):
        return 0
    with Lock():
        try:
            trust = make_trust(version, os.path.join(VERSIONS, version))
        except Failure as failure:
            keep(failure)
            print(failure.reason, file=sys.stderr)
            return 1
        except Exception as error:
            failure = Failure('trust', 'LOCAL7', ['%s: %s' % (type(error).__name__, error)], str(error))
            keep(failure)
            print(failure.reason, file=sys.stderr)
            return 1
        state['trust'] = trust
        state['restart_pending'] = signer_answers()
        write_state(state)
        clear('trust')
    return 0


def rollback():
    state = read_state()
    previous = state.get('previous')
    if not previous or not os.path.isdir(os.path.join(VERSIONS, previous)):
        print(say('LOCAL42'), file=sys.stderr)
        return 1
    with Lock():
        switch(previous)
        state.update({'installed': previous, 'previous': state.get('installed'), 'restart_pending': signer_answers()})
        write_state(state)
    out('LOCAL35', previous)
    return 0


def remove():
    with Lock():
        for path in (PROGRAM, TRUST_DIR, FFMPEG_DIR, STATE_FILE, CACHE):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
    for key in ('install', 'trust'):
        clear(key)
    out('LOCAL37')
    return 0


# ---- the signer ----------------------------------------------------------------------------------------------------

def signer_answers(timeout=2.0):
    request = urllib.request.Request(SIGNER_URL, data=b'', method='PUT', headers={
        'Content-Type': 'application/json', 'Force-Preflight': 'true', 'Origin': 'http://127.0.0.1:8800'})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status == 200 and json.loads(response.read().decode('utf-8', 'replace')).get('success') is True
    except (OSError, ValueError, urllib.error.URLError):
        return False


def status(as_json):
    state = read_state()
    try:
        version, entry, _ = load_catalogue()
    except (OSError, ValueError) as error:
        version, entry = None, None
        catalogue_error = str(error)
    else:
        catalogue_error = None
    used = in_use()
    answer = {'installed': used, 'catalogue': version, 'previous': state.get('previous'), 'state': state,
              'signer_answers': signer_answers(), 'catalogue_error': catalogue_error,
              'update': ('none' if used == version else ('pending' if used else 'not-installed'))}
    if as_json:
        print(json.dumps(answer, indent=1, sort_keys=True))
    else:
        out('LOCAL44', used, version) if used else out('LOCAL45')
        out('LOCAL38' if answer['signer_answers'] else 'LOCAL39')
    return 0


def check():
    """CNJ's update address names the version CNJ publishes. This only reads it and says what it found; the program is never
    changed by it: a new version goes through review, then the package."""
    version, entry, data = load_catalogue()
    address = data.get('update_endpoint')
    seen = {'checked': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'), 'reviewed': version}
    try:
        with urllib.request.urlopen(address, timeout=15) as response:
            text = response.read(65536).decode('utf-8', 'replace')
        found = re.search(r'(?m)^\s*app\.version\s*=\s*(\S+)', text)
        seen['published'] = found.group(1) if found else None
        seen['reachable'] = True
    except (OSError, urllib.error.URLError) as error:
        seen.update({'reachable': False, 'reason': str(error)})
    base = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local/state')
    folder = os.path.join(base, 'sparky-pjeoffice')
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, 'upstream.json'), 'w', encoding='utf-8') as stream:
        json.dump(seen, stream, indent=1, sort_keys=True)
    if not seen['reachable']:
        out('LOCAL46', address, seen['reason'])
        return 1
    published = seen['published'] or ''
    # CNJ's file says 2.5.16 for the archive named 2.5.16u: the letter after the number marks the Linux build
    if published and not re.sub(r'[A-Za-z]$', '', version) == published:
        out('LOCAL47', published, version)
    else:
        out('LOCAL48', version)
    return 0


def pid_of_signer():
    state_home = os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local/state')
    try:
        with open(os.path.join(state_home, 'sparky-pjeoffice/signer.pid')) as stream:
            pid = int(stream.read().strip())
        with open('/proc/%d/cmdline' % pid, 'rb') as stream:
            if b'PjeOfficePROUser' in stream.read():
                return pid
    except (OSError, ValueError):
        pass
    return None


def tray_running():
    for entry in os.listdir('/proc'):
        if entry.isdigit():
            try:
                with open('/proc/%s/cmdline' % entry, 'rb') as stream:
                    if stream.read().split(b'\0')[0].endswith(b'sparky-pjeoffice-tray') and os.stat('/proc/%s' % entry).st_uid == os.getuid():
                        return True
            except OSError:
                continue
    return False


def launch(wait=100, tell=False):
    """Start the tray entry and the signer for the person and wait until the signer answers (the launcher holds the start under one lock,
    so the tray's own start and this one never run two signers). With tell, a signer that does not start is kept in the person's own
    list of problems with the place of its log."""
    if os.path.exists('/usr/bin/sparky-pjeoffice-tray') and not tray_running():
        subprocess.Popen(['/usr/bin/sparky-pjeoffice-tray'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    if signer_answers():
        return 0
    try:
        result = subprocess.run(['/usr/bin/pjeoffice-pro'], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=wait)
        reason = (result.stderr or result.stdout).strip().splitlines()
        reason = reason[-1] if reason else 'the launcher exited with %d' % result.returncode
        failed = result.returncode != 0
    except subprocess.TimeoutExpired:
        reason, failed = 'it did not answer within %d seconds' % wait, True
    if not failed and signer_answers():
        engine('clear', '--person', PACKAGE, 'launch')
        return 0
    if tell:
        log = os.path.join(os.environ.get('XDG_STATE_HOME') or os.path.join(os.path.expanduser('~'), '.local/state'), 'sparky-pjeoffice/signer.log')
        tell_person(Failure('launch', 'LOCAL11', [reason, log], reason))
    return 1


def tell_person(failure):
    """A signing that fails is kept for the person in the problems engine (their own list), and printed."""
    engine('keep', '--person', PACKAGE, failure.key, failure.message, *[str(each) for each in failure.args_])
    print(failure.reason, file=sys.stderr)


def sign_pdf(paths, wait=300):
    """The program's own supported entry point: br.jus.cnj.pje.office.shell.ShellExtension cnj.assinador FILE samefolder DEFINIDO
    CADES ATTACHED SHA256withRSA. It writes a request the running signer watches; the signer asks for the certificate and the PIN
    in its own window. The result is a CAdES file beside the PDF; an embedded PAdES signature is not claimed."""
    status_code = 0
    app = os.path.realpath(CURRENT)
    if not os.path.isdir(app):
        print(say('LOCAL45'), file=sys.stderr)
        return 1
    for path in paths:
        path = os.path.abspath(path)
        if not os.path.isfile(path) or not path.lower().endswith('.pdf'):
            tell_person(Failure('sign', 'LOCAL8', [path, say('LOCAL49')], 'not a PDF file'))
            status_code = 1
            continue
        if launch() != 0:
            tell_person(Failure('sign', 'LOCAL8', [path, say('LOCAL39')], 'the signer does not answer'))
            status_code = 1
            continue
        result_path = path + '.p7s'
        before = os.path.getmtime(result_path) if os.path.exists(result_path) else None
        out('LOCAL43', path)
        env = dict(os.environ, LANG=os.environ.get('LANG') or 'C.UTF-8')
        command = [os.path.join(app, 'jre/bin/java'), '-Dpjeoffice_home=' + app, '-Duser.home=' + os.path.expanduser('~'),
                   '-cp', os.path.join(app, 'pjeoffice-pro.jar'), 'br.jus.cnj.pje.office.shell.ShellExtension',
                   'cnj.assinador', path, 'samefolder', 'DEFINIDO', 'CADES', 'ATTACHED', 'SHA256withRSA']
        result = subprocess.run(command, capture_output=True, text=True, env=env)
        if result.returncode:
            tell_person(Failure('sign', 'LOCAL8', [path, (result.stderr or result.stdout).strip()[-300:]], 'ShellExtension failed'))
            status_code = 1
            continue
        end = time.monotonic() + wait
        while time.monotonic() < end:
            if os.path.exists(result_path) and (before is None or os.path.getmtime(result_path) > before):
                break
            time.sleep(1)
        else:
            tell_person(Failure('sign', 'LOCAL8', [path, say('LOCAL50')], 'no result file'))
            status_code = 1
            continue
        engine('clear', '--person', PACKAGE, 'sign')
        out('LOCAL51', result_path)
    return status_code


# ---- the command line ----------------------------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(prog='sparky-pjeoffice', description=__doc__.split('\n\n')[0])
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('install', help='fetch, verify and install the reviewed version').add_argument('--catalogue')
    commands.add_parser('remove')
    commands.add_parser('rollback')
    trust = commands.add_parser('trust')
    trust.add_argument('--if-changed', action='store_true')
    state = commands.add_parser('status')
    state.add_argument('--json', action='store_true')
    commands.add_parser('check')
    sign = commands.add_parser('sign-pdf')
    sign.add_argument('files', nargs='+')
    sign.add_argument('--wait', type=int, default=300, help='seconds to wait for the signature file (the person types the PIN meanwhile)')
    commands.add_parser('launch').add_argument('--tell', action='store_true')
    arguments = parser.parse_args(argv)
    if arguments.command in ('install', 'remove', 'rollback', 'trust') and os.geteuid() != 0:
        print(say('LOCAL52'), file=sys.stderr)
        return 1
    try:
        return dispatch(arguments)
    except Failure as failure:
        print(failure.reason, file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print('sparky-pjeoffice: %s' % error, file=sys.stderr)
        return 1


def dispatch(arguments):
    if arguments.command == 'install':
        return install(arguments.catalogue)
    if arguments.command == 'remove':
        return remove()
    if arguments.command == 'rollback':
        return rollback()
    if arguments.command == 'trust':
        return regenerate_trust(arguments.if_changed)
    if arguments.command == 'status':
        return status(arguments.json)
    if arguments.command == 'check':
        return check()
    if arguments.command == 'sign-pdf':
        return sign_pdf(arguments.files, arguments.wait)
    return launch(tell=arguments.tell)


if __name__ == '__main__':
    sys.exit(main())
