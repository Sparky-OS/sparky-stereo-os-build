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


def _control(deb):
    out = subprocess.run(['dpkg-deb', '-f', str(deb), 'Package', 'Version', 'Architecture', 'Source'],
                         capture_output=True, text=True, check=True).stdout
    fields = dict(line.split(': ', 1) for line in out.splitlines() if ': ' in line)
    source, version = fields.get('Source', fields['Package']), fields['Version']
    m = re.match(r'^(\S+)\s*\((.+)\)$', source)
    if m:
        source, version = m.groups()
    return source, version, fields['Architecture']


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
    in each folder. Stops (Incomplete) when SPARKY_PROVENANCE_REQUIRED=1 and a host fact is missing."""
    environ = os.environ if environ is None else environ
    groups = {}
    for deb in sorted(Path(d).resolve() for d in debs):
        source, version, _ = _control(deb)
        groups.setdefault((deb.parent, source, version), []).append(deb)
    _, optout = _init_state(environ)
    facts, unrecorded_hosts = _host_facts(environ)
    if unrecorded_hosts and environ.get('SPARKY_PROVENANCE_REQUIRED') == '1':
        raise Incomplete('provenance required, but the build script did not pass: ' +
                         ', '.join(HOST_FACTS[k][0] for k in unrecorded_hosts) +
                         ' (source sparky-os/repo/build-provenance.sh)')
    return [_write(folder, source, version, group, facts, unrecorded_hosts, environ, now, optout)
            for (folder, source, version), group in sorted(groups.items())]


def _write(folder, source, version, debs, facts, unrecorded_hosts, environ, now, optout=None):
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
    if optout:
        obj['provenanceOptOut'] = optout
    obj['debs'] = [_file_row(d) for d in debs]
    kept = []
    for pattern in ('*.buildinfo', '*.changes', '*.dsc'):
        kept += [_file_row(p) for p in sorted(folder.glob(f'{source}_*{pattern[1:]}'))
                 if f'_{version.split(":", 1)[-1]}' in p.name]
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
