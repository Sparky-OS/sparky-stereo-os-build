# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""The record a build leaves beside its .deb files (ORDER 394b): what make-provenance.py reads.

Every Lean Code build passes two points of this toolkit: lean.debhelper (no .deb is made without it) and the
release gate `lean.release check-debs` (no .deb is accepted without it). The first notes when dpkg-buildpackage
started, the second writes `SOURCE_VERSION_ARCH.sparky-build.json` next to the .deb files and names the .buildinfo
and .changes files that dpkg-buildpackage wrote there.

The host knows four things the container cannot see, so the build script passes them as SPARKY_BUILD_* variables
(sparky-os/repo/build-provenance.sh sets them): the build repository's commit, the builder image's id, the
invocation id and the moment the script started. A fact that was not passed is not guessed: the record lists it under
"unrecorded", the log says so, and make-provenance.py reports it as a gap. SPARKY_PROVENANCE_REQUIRED=1 stops the
build instead.

A build script that never called sparky_provenance_init passes none of them. That is not a fact that could not be
read; it is a recipe that forgot the call, and the gate stops with a message naming it (ORDER 412, no silent
fallbacks). A recipe that cannot have host facts says so with SPARKY_PROVENANCE_OPTOUT=<reason>; the record carries
the reason in "provenanceOptOut" and still lists the unrecorded facts.
"""
from datetime import datetime, timezone
import glob
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

FORMAT = 'sparky-build-record/1'
SUFFIX = '.sparky-build.json'
START = '.sparky-build-start.json'
# record field -> (environment variable, what it is)
HOST_FACTS = {
    'recipeCommit': ('SPARKY_BUILD_COMMIT', "the build repository's commit"),
    'builderImage': ('SPARKY_BUILD_IMAGE_ID', "the builder image's id"),
    'invocationId': ('SPARKY_BUILD_INVOCATION', 'the invocation id'),
    'startedOn': ('SPARKY_BUILD_STARTED', 'the moment the build script started'),
}
STAMP = re.compile(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')
COMMIT = re.compile(r'^[0-9a-f]{40}$')
IMAGE_ID = re.compile(r'^sha256:[0-9a-f]{64}$')
OPTOUT = 'SPARKY_PROVENANCE_OPTOUT'
# build-provenance.sh always passes these two (a uuid and the clock); a build whose container has neither never ran the call
INIT_MARKS = ('SPARKY_BUILD_INVOCATION', 'SPARKY_BUILD_STARTED')
INVOCATION = re.compile(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')


class Incomplete(ValueError):
    pass


def stamp(when=None):
    return (when or datetime.now(timezone.utc)).strftime('%Y-%m-%dT%H:%M:%SZ')


def _boot_time():
    for line in Path('/proc/stat').read_text().splitlines():
        if line.startswith('btime '):
            return int(line.split()[1])
    raise OSError('/proc/stat has no btime')


def dpkg_buildpackage_started():
    """The start of the dpkg-buildpackage process this one runs under (from /proc), or None."""
    pid = os.getppid()
    ticks = os.sysconf('SC_CLK_TCK')
    while pid > 1:
        try:
            cmdline = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
            stat = Path(f'/proc/{pid}/stat').read_text()
        except OSError:
            return None
        fields = stat[stat.rindex(')') + 2:].split()      # after "pid (comm) ": state is fields[0]; starttime is field 22 of the file
        if any(os.path.basename(arg.decode(errors='replace')) == 'dpkg-buildpackage' for arg in cmdline[:3]):
            return stamp(datetime.fromtimestamp(_boot_time() + int(fields[19]) / ticks, timezone.utc))
        pid = int(fields[1])
    return None


def note_start(build_dir):
    """Called by lean.debhelper in the build (once per dpkg-buildpackage): write the start into the folder that will hold the
    .deb files, replacing what an earlier build left."""
    (Path(build_dir) / START).write_text(json.dumps({'dpkgBuildpackageStartedOn': dpkg_buildpackage_started()}) + '\n')


def _file_row(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            h.update(block)
    return {'name': path.name, 'sha256': h.hexdigest()}


def _checksum_rows(path):
    """(source field, sha256 -> file name) of a .buildinfo or .changes: the files its Checksums-Sha256 lists. Both are
    deb822 files, possibly PGP-signed; only the two fields this needs are read."""
    source, rows, in_sums = None, {}, False
    for line in path.read_text(errors='replace').splitlines():
        if line[:1] in (' ', '\t'):
            fields = line.split()
            if in_sums and len(fields) == 3:
                rows[fields[0]] = fields[2]
            continue
        in_sums = line.startswith('Checksums-Sha256:')
        if line.startswith('Source:'):
            source = line.split(':', 1)[1].strip()
    return source, rows


def _split_source(field, version):
    """'name' or 'name (source version)' -> (name, source version); without parentheses the binary version stands."""
    m = re.match(r'^(\S+)\s*\((.+)\)$', field)
    return m.groups() if m else (field, version)


def _control(deb):
    """(source, source version, architecture, binary version) of a .deb. The source is its own Source field. A binary
    package whose name differs from its source and that carries no Source field (a recipe that wrote DEBIAN/control by
    hand) is placed by the .buildinfo or .changes beside it that lists this very file by its SHA-256; the log says so.
    With neither, the package's own name stands and the record reports the missing .buildinfo (nothing is guessed)."""
    out = subprocess.run(['dpkg-deb', '-f', str(deb), 'Package', 'Version', 'Architecture', 'Source'],
                         capture_output=True, text=True, check=True).stdout
    fields = dict(line.split(': ', 1) for line in out.splitlines() if ': ' in line)
    binary_version = fields['Version']
    if 'Source' in fields:
        source, version = _split_source(fields['Source'], binary_version)
        return source, version, fields['Architecture'], binary_version
    digest = _file_row(deb)['sha256']
    for build_file in sorted(deb.parent.glob('*.buildinfo')) + sorted(deb.parent.glob('*.changes')):
        field, rows = _checksum_rows(build_file)
        if field and rows.get(digest) == deb.name:
            source, version = _split_source(field, binary_version)
            if source != fields['Package']:
                print(f'lc1: {deb.name} has no Source field; {build_file.name} lists it as built from {source}')
            return source, version, fields['Architecture'], binary_version
    return fields['Package'], binary_version, fields['Architecture'], binary_version


def _host_facts(environ):
    """(recorded host facts, [names of the facts that were not passed]). A fact that was passed but is malformed
    is an error, never an unrecorded fact."""
    shapes = {'recipeCommit': COMMIT, 'invocationId': INVOCATION, 'startedOn': STAMP, 'builderImage': IMAGE_ID}
    facts, unrecorded = {}, []
    for key, (var, what) in HOST_FACTS.items():
        value = environ.get(var, '')
        if not value:
            unrecorded.append(key)
        elif not shapes[key].match(value):
            raise Incomplete(f'{var}={value!r} is not {what} (expected {shapes[key].pattern})')
        else:
            facts[key] = value
    return facts, unrecorded


def _init_state(environ):
    """(initialised, opt-out reason or None). Stops (Incomplete) when the build script never called
    sparky_provenance_init and gave no reason, or gave both, or gave an empty reason."""
    initialised = any(environ.get(var) for var in INIT_MARKS)
    optout = environ.get(OPTOUT)
    if optout is not None and not optout.strip():
        raise Incomplete(f'{OPTOUT} is set but empty: say why this recipe cannot have provenance')
    if optout and initialised:
        raise Incomplete(f'{OPTOUT} is set, but the build script also called sparky_provenance_init: remove one of them')
    if not initialised and not optout:
        raise Incomplete('the build script did not call sparky_provenance_init, so no host fact reached this container '
                         '(none of ' + ', '.join(INIT_MARKS) + ' is set). Source sparky-os/repo/build-provenance.sh, call '
                         '`sparky_provenance_init IMAGE` right before the docker run and add "${SPARKY_PROV_ARGS[@]}" to it. '
                         f'A recipe that cannot have provenance sets {OPTOUT}="<reason>" instead; the record carries the reason')
    return initialised, (optout.strip() if optout else None)


def record(debs, environ=None, now=None):
    """Write the build record for the .deb files of a build and return the paths: one record for each source version
    in each folder, however many binary packages the source built (dpkg names the .buildinfo after the source). Stops (Incomplete) when SPARKY_PROVENANCE_REQUIRED=1 and a host fact is missing."""
    environ = os.environ if environ is None else environ
    groups = {}
    for deb in sorted(Path(d).resolve() for d in debs):
        source, version, _, binary_version = _control(deb)
        groups.setdefault((deb.parent, source, version), []).append((deb, binary_version))
    _, optout = _init_state(environ)
    facts, unrecorded_hosts = _host_facts(environ)
    if unrecorded_hosts and environ.get('SPARKY_PROVENANCE_REQUIRED') == '1':
        raise Incomplete('provenance required, but the build script did not pass: ' +
                         ', '.join(HOST_FACTS[k][0] for k in unrecorded_hosts) +
                         ' (source sparky-os/repo/build-provenance.sh)')
    return [_write(folder, source, version, group, facts, unrecorded_hosts, environ, now, optout)
            for (folder, source, version), group in sorted(groups.items())]


def _write(folder, source, version, built, facts, unrecorded_hosts, environ, now, optout=None):
    debs = [deb for deb, _ in built]
    unrecorded = list(unrecorded_hosts)
    started = None
    start_file = folder / START
    if start_file.exists():
        started = json.loads(start_file.read_text()).get('dpkgBuildpackageStartedOn')
    obj = {'format': FORMAT, 'source': source, 'version': version,
           'buildArchitecture': subprocess.run(['dpkg', '--print-architecture'], capture_output=True, text=True,
                                               check=True).stdout.strip()}
    obj.update(facts)
    if 'startedOn' in facts:
        obj['startBasis'] = 'build-script'
    elif started:
        obj['startedOn'], obj['startBasis'] = started, 'dpkg-buildpackage'
        unrecorded.remove('startedOn')
    obj['finishedOn'] = stamp(now)
    if environ.get('SPARKY_BUILD_IMAGE_NAME'):
        obj['builderImageName'] = environ['SPARKY_BUILD_IMAGE_NAME']
    if environ.get('SPARKY_BUILD_IMAGE_REPO_DIGESTS'):
        obj['builderImageRepoDigests'] = environ['SPARKY_BUILD_IMAGE_REPO_DIGESTS'].split()
    if environ.get('SPARKY_BUILD_REPOSITORY'):
        obj['recipeRepository'] = environ['SPARKY_BUILD_REPOSITORY']
    if 'recipeCommit' in facts:
        obj['recipeDirty'] = environ.get('SPARKY_BUILD_DIRTY') == '1'
    if re.fullmatch(r'\d{1,12}', environ.get('SOURCE_DATE_EPOCH', '')):
        obj['sourceDateEpoch'] = int(environ['SOURCE_DATE_EPOCH'])
        if environ.get('SPARKY_SOURCE_DATE_BASIS'):
            obj['sourceDateBasis'] = environ['SPARKY_SOURCE_DATE_BASIS']
    if optout:
        obj['provenanceOptOut'] = optout
    obj['debs'] = [_file_row(d) for d in debs]
    # dpkg-genbuildinfo and dpkg-genchanges name their files SOURCE_BINARYVERSION_ARCH.*, the .dsc SOURCE_SOURCEVERSION.dsc
    # (they differ for a binNMU); the version is matched whole, so 1.0-1 never takes the files of 1.0-10
    plain = version.split(':', 1)[-1]
    binary_versions = sorted({bv.split(':', 1)[-1] for _, bv in built} | {plain})
    kept = []
    for suffix in ('.buildinfo', '.changes'):
        names = {p.name: p for v in binary_versions for p in folder.glob(f'{glob.escape(source)}_{glob.escape(v)}_*{suffix}')}
        kept += [_file_row(names[n]) for n in sorted(names)]
    kept += [_file_row(p) for p in sorted(folder.glob(f'{glob.escape(source)}_{glob.escape(plain)}.dsc'))]
    obj['files'] = kept
    if not any(row['name'].endswith('.buildinfo') for row in kept):
        unrecorded.append('buildinfo')
    obj['unrecorded'] = unrecorded
    name = f'{source}_{version.split(":", 1)[-1]}_{obj["buildArchitecture"]}{SUFFIX}'
    path = folder / name
    path.write_text(json.dumps(obj, indent=1, sort_keys=True) + '\n')
    start_file.unlink(missing_ok=True)
    if unrecorded:
        why = (f' (opted out, {OPTOUT}: {obj["provenanceOptOut"]})' if 'provenanceOptOut' in obj else
               ' (the build script passes the host facts through sparky-os/repo/build-provenance.sh)')
        print('lc1: build record NOT complete, unrecorded: ' + ', '.join(unrecorded) + why)
    print(f'lc1: build record {name}')
    return path
