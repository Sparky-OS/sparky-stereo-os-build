# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Link and start gate for lc1 packages: a rebuild must still link and load like the build it replaces.

Why this exists (ORDER 198, found 2026-10-22): torcs 1.3.7+dfsg-5+stereo3d1+lc1 was published
and installed although torcs-bin could not start ("undefined symbol XRRConfigCurrentConfiguration
in libtgfclient.so"). The lc1 link dropped libXrandr from NEEDED and libxrandr2 from Depends
because nothing checked that the rebuilt ELF files still resolve every symbol. The payload
hashes of `check-debs` prove the archive bytes, not that the programs run.

Four checks, none installs anything and none needs a display:

  stereo   a symbol with "stereo" in its name that an ELF file imported in the previous build
           and no longer imports: the stereo feature was compiled out (blocks).
  needed   NEEDED libraries and shlib Depends lost against the previous build of the same
           package. Reported; blocks only together with an unresolved symbol (a library
           that is no longer needed because nothing uses it is a legitimate --as-needed result).
  resolve  archive-loader tracing equivalent to `ldd -r` on every ELF the host loads, with
           private library directories inside the qualified root. Every "not found" and every
           "undefined symbol" must already exist in the previous build's result; a package
           without a previous build must have no missing library and no undefined symbol in
           an executable (a library alone reports what its program supplies). An ELF file of
           another machine is guest data only where Debian keeps it (GUEST_DATA); it is noted.
  smoke    start the programs named in a smoke table with LD_BIND_NOW=1 (every symbol is bound
           at load, which is exactly what failed for torcs) and no display; a dynamic-loader
           error in the output blocks.

The stereo and needed checks read each host ELF file's inventory with readelf -d and nm -D. An inventory that
cannot be read (the tool fails, times out or is missing) blocks, naming the tool's own error: it never stands for
a file that imports nothing (U58, ORDER 346b). A static file has a readable, empty inventory (readelf: "There is
no dynamic section", nm: "no symbols", both exit 0).

Recommends, narrowly (ORDER 311 step 4, fltk1.4's flpuzzle): Depends-only resolution is the rule. Where an ELF's
missing library is shipped by a package that the supplied package's own Recommends names, that ELF is resolved again
with those Recommends installed, and the result is a note naming them; the predecessor is treated the same way. Debian
Policy 7.2: Recommends "declares a strong, but not absolute, dependency" and "should list packages that would be found
together with this one in all but unusual installations"; dpkg-shlibdeps(1) -ddependency-field puts a program's library
dependencies in that field ("The default dependency-field is Depends"), and Debian's fltk1.4 sends flpuzzle's there
(-dRecommends). The edition installs Recommends by default, so its systems have them. A library that no Depends and no
such Recommends provides still fails.

Runtime dependencies come from explicit signed archives through lean.archive.
The loader and smoke programs run in a bubblewrap root containing only qualified
inputs, without workstation library paths, cache, configuration or environment.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile

from . import archive, package

LOADER_ERRORS = re.compile(
    r'symbol lookup error|undefined symbol|cannot open shared object file|'
    r'error while loading shared libraries|version `[^\']+\' not found')


def _is_elf(path):
    try:
        with open(path, 'rb') as handle:
            return handle.read(4) == b'\x7fELF'
    except OSError:
        return False


def elf_files(root):
    """Regular ELF files of an extracted tree, never following symlinks, debug-symbol files excluded."""
    root = Path(root)
    found = []
    for base, dirs, names in os.walk(root):
        if '/usr/lib/debug' in base[len(str(root)):] + '/':
            dirs[:] = []
            continue
        for name in names:
            path = Path(base) / name
            if not path.is_symlink() and path.is_file() and _is_elf(path):
                found.append(path)
    return sorted(found)


class InventoryError(package.Invalid):
    """An ELF inventory (NEEDED, stereo imports) that could not be read: never an empty inventory (U58)."""


def probe(args, what, path, timeout):
    """The output of an inventory tool, read in the C locale; its failure is an InventoryError naming the tool's own
    error, so a failed probe never passes for a file with nothing to report."""
    try:
        run = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                             env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
    except subprocess.TimeoutExpired:
        raise InventoryError(f'cannot verify the {what} of {path}: {args[0]} timed out after {timeout} s')
    except OSError as exc:
        raise InventoryError(f'cannot verify the {what} of {path}: {args[0]}: {exc}')
    if run.returncode:
        error = ' '.join(run.stderr.strip().splitlines()[-2:]) or 'no message'
        raise InventoryError(f'cannot verify the {what} of {path}: {" ".join(args[:-1])} exited {run.returncode}: '
                             f'{error}')
    return run.stdout


def needed(path):
    out = probe(['readelf', '-d', '-W', str(path)], 'NEEDED libraries', path, 30)
    return sorted(line.split('[', 1)[1].rstrip(']') for line in out.splitlines() if '(NEEDED)' in line)


MULTIARCH = {'amd64': 'x86_64-linux-gnu', 'i386': 'i386-linux-gnu', 'arm64': 'aarch64-linux-gnu'}

STEREO = re.compile(r'stereo', re.I)


def stereo_imports(path):
    """Dynamic symbols a file imports whose names mention stereo (stereo_declare_*, libstereo-layer, ...). A file
    without dynamic symbols (a static program) has none: nm says "no symbols" and exits 0."""
    out = probe(['nm', '-D', '--undefined-only', str(path)], 'stereo imports', path, 60)
    found = set()
    for line in out.splitlines():
        part = line.split()
        if len(part) >= 2 and part[0] == 'U' and STEREO.search(part[-1]):
            found.add(part[-1].split('@')[0])
    return found


RETIRED_ENV = 'SPARKY_LC_RETIRED_STEREO_IMPORTS'


def retired_stereo_imports():
    """Stereo imports the source being built declares it no longer calls, on purpose: {symbol: reason}. A lost stereo
    import blocks the gate, because an optional build dependency that switched a stereo feature off links cleanly; a
    call that moved to another function by design is lost in the same way, and the source says so here, one line a
    symbol: the name exactly as `nm -D` prints it, white space, the reason. lean.debhelper names the file
    (debian/sparky-lean-retired-stereo-imports of the source) in the environment when the source has one. Every other
    lost import still blocks, and each one let through is a note in the build's log. A line without a reason, a name
    that does not mention stereo, or a file that cannot be read stops the gate: a declaration is never guessed."""
    name = os.environ.get(RETIRED_ENV)
    if not name:
        return {}
    try:
        lines = Path(name).read_text(encoding='utf-8').splitlines()
    except OSError as error:
        raise package.Invalid(f'{name}: the retired stereo imports cannot be read: {error}') from error
    retired = {}
    for number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2 or not parts[1].strip() or not STEREO.search(parts[0]):
            raise package.Invalid(f'{name}:{number}: a retired stereo import is its symbol, white space and the reason')
        retired[parts[0]] = parts[1].strip()
    return retired


def extract(deb, dest, check_space=None):
    archive.unpack(deb, Path(dest), check_space)


def control_field(deb, field):
    return subprocess.run(['dpkg-deb', '-f', str(deb), field], capture_output=True, text=True, check=True).stdout.strip()


def private_dirs(root):
    """Directories of the tree holding shared objects outside the system multiarch directories."""
    root = Path(root)
    dirs = set()
    for path in elf_files(root):
        if '.so' in path.name:
            rel = '/' + str(path.parent.relative_to(root))
            if rel not in ('/usr/lib', '/lib') and not rel.endswith('-linux-gnu'):
                dirs.add(str(path.parent))
    return sorted(dirs)



LOADERS = {'amd64': '/lib64/ld-linux-x86-64.so.2', 'i386': '/lib/ld-linux.so.2',
           'arm64': '/lib/ld-linux-aarch64.so.1'}
MACHINES = {'amd64': 'Advanced Micro Devices X86-64', 'i386': 'Intel 80386', 'arm64': 'AArch64'}


# An ELF file of another machine that no host loader loads (ORDER 340): QEMU's guest firmware, which
# qemu-system-data ships in /usr/share/qemu and its machine models read with load_elf(). Debian's rule:
# Lintian's binary-from-other-architecture compares each ELF with its package's architecture and has none
# to compare in an Architecture: all package (lib/Lintian/Check/Binaries/Architecture/Other.pm); such a
# package's "binary blobs for other purposes independent of the host architecture (such as BIOS updates or
# firmware)" take an override (arch-independent-package-contains-binary-or-object), and /usr/share is
# reserved for architecture-independent files (arch-dependent-file-in-usr-share; FHS 3.0, 4.11), which is
# where Debian's qemu-system-data overrides both. Neither the dynamic loader nor dpkg-shlibdeps looks for
# libraries there (Dpkg::Shlibs: /lib, /usr/lib, ld.so.conf, the multilib directories), while /usr/lib may
# hold both kinds (Debian Policy 9.1.1) and its plugins are loaded by path. An ELF file of the host's
# machine is traced wherever it is, and a foreign one anywhere else still fails the machine check.
GUEST_DATA = {'architecture': 'all', 'under': ('/usr/share/',)}


def guest_data(path, rel, qualified):
    """The machine of an ELF file another consumer loads, or None when it is the host's to load."""
    if (qualified.candidate.get('Architecture') != GUEST_DATA['architecture']
            or not rel.startswith(GUEST_DATA['under'])):
        return None
    run = subprocess.run(['readelf', '-h', '-W', str(path)], capture_output=True, text=True, timeout=30,
                         env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
    machine = re.search(r'Machine:\s*(.+)', run.stdout)
    if run.returncode or not machine or machine[1].strip() == MACHINES.get(qualified.arch):
        return None
    return machine[1].strip()


def loader_command(path, root, qualified):
    """Use the matching archive loader and libc inside the qualified filesystem."""
    run = subprocess.run(['readelf', '-h', '-l', '-d', '-W', str(path)], capture_output=True,
                         text=True, timeout=30, env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
    if run.returncode:
        raise package.Invalid(f'unusable ELF: {run.stderr.strip()}')
    machine = re.search(r'Machine:\s*(.+)', run.stdout)
    if not machine or machine[1].strip() != MACHINES.get(qualified.arch):
        raise package.Invalid(f'ELF machine does not match {qualified.arch}')
    rel = '/' + str(path.relative_to(root))
    interp = re.search(r'Requesting program interpreter: ([^]]+)', run.stdout)
    # A static-pie executable (no interpreter, no NEEDED, DF_1_PIE) starts with no loader at all, as file(1)
    # ("static-pie linked"), glibc's ldd ("statically linked") and Lintian's statically-linked-binary
    # (#1068304) see it: Debian builds qemu-user's programs so. A library without NEEDED is still traced.
    pie = re.search(r'\(FLAGS_1\)\s+Flags:.*\bPIE\b', run.stdout)
    if not interp and '(NEEDED)' not in run.stdout and ('There is no dynamic section' in run.stdout or pie):
        return [rel], True
    loader = interp[1] if interp else LOADERS.get(qualified.arch)
    if not loader or not archive.rooted(qualified.root, loader).is_file():
        raise package.Invalid(f'qualified interpreter missing: {loader}; declare the matching libc dependency')
    directories = [str(Path(d).relative_to(root)) for d in private_dirs(root)]
    directories += [str(Path(d).relative_to(qualified.root)) for d in private_dirs(qualified.root)]
    directories += [f'usr/lib/{MULTIARCH[qualified.arch]}', f'lib/{MULTIARCH[qualified.arch]}', 'usr/lib', 'lib']
    search = ':'.join(dict.fromkeys('/' + d for d in directories))
    return [loader, '--inhibit-cache', '--library-path', search, rel], False


def resolve(root, timeout=20, extra_dirs=(), qualified=None, notes=None):
    """{(relative file, kind, item): True}, confined to the qualified archive root; guest data goes to notes."""
    if extra_dirs:
        raise package.Invalid('unqualified library directories are forbidden; supply sibling .debs')
    if qualified is None:
        raise package.Invalid('archive-qualified execution context required; use lean.release check-link')
    root = Path(root)
    # Loader diagnostics are parsed in the C locale even when the invoking desktop
    # uses another language; static ELF detection does not depend on translated ldd output.
    result = {}
    for path in elf_files(root):
        rel = '/' + str(path.relative_to(root))
        machine = guest_data(path, rel, qualified)
        if machine:
            if notes is not None:
                notes.append(f'{rel}: {machine} ELF in an Architecture: all package under /usr/share, '
                             'data for another consumer, never loaded by the host')
            continue
        try:
            command, static = loader_command(path, root, qualified)
            if static:
                continue
            run = qualified.run(command, {'LD_TRACE_LOADED_OBJECTS': '1', 'LD_WARN': 'yes',
                                           'LD_BIND_NOW': 'yes'}, timeout)
        except subprocess.TimeoutExpired:
            result[(rel, 'timeout', '')] = True
            continue
        except archive.ExecutionUnavailable:
            raise
        except package.Invalid as exc:
            result[(rel, 'loader error', str(exc))] = True
            continue
        text = run.stdout + run.stderr
        parsed = False
        for line in text.splitlines():
            line = line.strip()
            if 'not found' in line:
                result[(rel, 'not found', line.split('=>')[0].strip())] = True
                parsed = True
            elif 'undefined symbol' in line:
                symbol = line.split('undefined symbol:', 1)[1].split(',')[0].split('\t')[0].strip()
                result[(rel, 'undefined', symbol)] = True
                parsed = True
            elif LOADER_ERRORS.search(line):
                result[(rel, 'loader error', line.split('error while loading shared libraries:', 1)[-1].strip())] = True
                parsed = True
        if run.returncode != 0 and not parsed:
            last = text.strip().splitlines()[-1] if text.strip() else f'loader exited {run.returncode}'
            result[(rel, 'loader error', last.strip())] = True
    return result


def inventories(root, qualified, findings, whose):
    """({file: NEEDED}, {file: stereo imports}) of the ELF files the host loads; guest data is resolve()'s note, never
    loaded by the host. A file whose inventory cannot be read is a finding (U58: a failed readelf or nm gave an empty
    inventory, the same as a file that imports nothing, and could hide a lost stereo import)."""
    needed_of, stereo_of = {}, {}
    for path in elf_files(root):
        rel = str(path.relative_to(root))
        if guest_data(path, '/' + rel, qualified):
            continue
        try:
            needed_of[rel] = needed(path)
            stereo_of[rel] = stereo_imports(path)
        except InventoryError as exc:
            findings.append(f'/{rel} ({whose}): {str(exc).replace(str(path), "/" + rel)}')
    return needed_of, stereo_of


def recommends_of(deb):
    """The package's Recommends: one list of alternative package names per relation."""
    fields = control_field(deb, 'Recommends')
    return [[re.split(r'[ (:]', alt.strip())[0] for alt in part.split('|') if alt.strip()]
            for part in fields.split(',') if part.strip()]


def deb_basenames(deb):
    """The names (last path component) of the files a package ships."""
    listing = subprocess.run(['dpkg-deb', '--fsys-tarfile', str(deb)], capture_output=True, check=True).stdout
    import io
    import tarfile
    with tarfile.open(fileobj=io.BytesIO(listing)) as tar:
        return {Path(m.name).name for m in tar.getmembers() if not m.isdir()}


def selected_debs(qualified):
    """{package name: .deb} of what a qualified case installed: the archives it downloaded and the inputs it selected."""
    import json
    evidence = json.loads((qualified.directory / 'resolution.json').read_text())
    out = {}
    for item in evidence['packages']:
        out[item['identity'][0]] = qualified.owner.cache / (item['sha256'] + '.deb')
    for item in evidence['inputs']:
        if item['selected']:
            out[item['identity'][0]] = Path(item['source'])
    return out


def with_recommends(deb, siblings, root, result, archive_context, notes, whose):
    """The narrow Recommends case (module docstring): `result` with each ELF whose every missing library a package
    named in the supplied package's own Recommends ships resolved again with those Recommends installed."""
    missing = {}
    for name, kind, item in result:
        if kind == 'not found':
            missing.setdefault(name, set()).add(item)
    groups = recommends_of(deb)
    if not missing or not groups:
        return result
    names = [alts[0] for alts in groups]
    try:
        rq = archive_context.qualify(deb, siblings, recommends=names)
    except (OSError, package.Invalid) as exc:
        notes.append(f'{whose}: its Recommends ({", ".join(names)}) could not be installed with it, so the missing '
                     f'libraries stay missing: {str(exc).splitlines()[0][:200]}')
        return result
    try:
        again = resolve(root, qualified=rq)
        debs = selected_debs(rq)
        shipped = {alt: deb_basenames(debs[alt]) for alts in groups for alt in alts if alt in debs}
    finally:
        rq.close()
    out = dict(result)
    for rel, libs in sorted(missing.items()):
        providers = {lib: sorted(alt for alt, files in shipped.items() if lib in files) for lib in libs}
        if not all(providers.values()):
            continue
        for key in [k for k in out if k[0] == rel]:
            del out[key]
        out.update({k: v for k, v in again.items() if k[0] == rel})
        named = ', '.join(f'{lib} from {" | ".join(p)}' for lib, p in sorted(providers.items()))
        notes.append(f'{rel} ({whose}): resolved with its Recommends installed, which ship its libraries ({named}); '
                     f'Depends alone leave them out (Debian Policy 7.2: "all but unusual installations")')
    return out


def compare(new_deb, previous_deb=None, extra_dirs=(), qualified=None, previous_qualified=None,
            archive_context=None, siblings=(), previous_siblings=None):
    """Return (findings, notes). A finding blocks the release, a note is informational.
    With `archive_context`, the predecessor is qualified here (after this build's narrow Recommends case, so that
    at most two roots are live), and both builds get the narrow Recommends case."""
    findings, notes = [], []
    with tempfile.TemporaryDirectory(prefix='inspect-new-', dir=qualified.directory) as new_root:
        extract(new_deb, new_root, qualified.owner.ensure_space)
        now = resolve(new_root, extra_dirs=extra_dirs, qualified=qualified, notes=notes)
        if archive_context is not None:
            now = with_recommends(new_deb, siblings, new_root, now, archive_context, notes, 'this build')
        if previous_deb:
            # the inventories are compared with the previous build's, so they are read only when there is one
            new_needed, new_stereo = inventories(new_root, qualified, findings, 'this build')
            own_previous = previous_qualified is None
            old_inputs = siblings if previous_siblings is None else previous_siblings
            if own_previous:
                try:
                    previous_qualified = archive_context.qualify(previous_deb, old_inputs)
                except (OSError, package.Invalid) as exc:
                    raise package.Invalid(f'{Path(previous_deb).name}: previous edition dependency qualification '
                                          f'failed; provide the matching previous sibling snapshot:\n{exc}') from exc
            try:
                with tempfile.TemporaryDirectory(prefix='inspect-old-', dir=previous_qualified.directory) as old_root:
                    extract(previous_deb, old_root, previous_qualified.owner.ensure_space)
                    before = resolve(old_root, qualified=previous_qualified)
                    if own_previous:
                        previous_qualified.close()
                    if archive_context is not None:
                        before = with_recommends(previous_deb, old_inputs, old_root, before, archive_context, notes,
                                                 'the previous build')
                    old_needed, old_stereo = inventories(old_root, previous_qualified, findings, 'the previous build')
            finally:
                if own_previous:
                    previous_qualified.close()
            # An unusable predecessor cannot establish a successful regression
            # baseline. Library-only imports supplied by a program remain valid.
            broken_before = [key for key in before if key[1] != 'undefined' or not re.search(r'\.so(\.|$)', key[0])]
            # A library the previous build could not find and this build finds is an improvement, not a regression
            # (qt6-declarative-examples: Qt's attachedstyleproperties plugin had a run path one directory short of its
            # libMyStyle.so, fixed in +stereo3d2). The gate says so and goes on. A library missing in both builds
            # stays a block: a carried defect is fixed, not noted; any other unusable predecessor stops the build.
            # The key is also absent when this build no longer ships the ELF file at all: then nothing finds the
            # library, and the note says that instead.
            shipped = {'/' + str(path.relative_to(new_root)) for path in elf_files(new_root)}
            for name, kind, item in [k for k in broken_before if k[1] == 'not found' and k not in now]:
                notes.append(f'{name}: the previous build could not find {item}; this build finds it' if name in shipped
                             else f'{name}: the previous build could not find {item}; this build no longer ships the file')
            broken_before = [k for k in broken_before if k[1] != 'not found' or k in now]
            if broken_before:
                raise package.Invalid('predecessor failed archive-qualified resolution: ' +
                                      '; '.join(f'{name}: {kind} {item}' for name, kind, item in broken_before[:5]))
            grouped = {}
            for key in sorted(now):
                if key not in before:
                    grouped.setdefault((key[0], key[1]), []).append(key[2])
            for (name, kind), items in sorted(grouped.items()):
                shown = ', '.join(items[:3]) + (f' and {len(items) - 3} more' if len(items) > 3 else '')
                findings.append(f'{name}: {len(items)} new {kind}: {shown} (the previous build resolved them)')
            # A stereo feature that an optional build dependency switched off compiles and links
            # cleanly (analitza 4:26.04.0-1+stereo3d2+lc1 lost stereo_declare_wayland this way).
            retired = retired_stereo_imports()
            for rel in sorted(set(old_stereo) & set(new_stereo)):
                gone = sorted(old_stereo[rel] - new_stereo[rel])
                for symbol in [symbol for symbol in gone if symbol in retired]:
                    notes.append(f'/{rel}: stereo import {symbol} is no longer called, as the source declares: {retired[symbol]}')
                gone = [symbol for symbol in gone if symbol not in retired]
                if gone:
                    findings.append(f'/{rel}: stereo imports lost: {", ".join(gone[:4])}'
                                    f'{" and more" if len(gone) > 4 else ""} (the previous build called them)')
            for rel in sorted(set(old_needed) & set(new_needed)):
                lost = sorted(set(old_needed[rel]) - set(new_needed[rel]))
                if lost:
                    notes.append(f'{rel}: NEEDED no longer lists {", ".join(lost)}')
            old_dep = _depends(previous_deb)
            new_dep = _depends(new_deb)
            for name in sorted(old_dep - new_dep):
                notes.append(f'Depends no longer names {name}')
        else:
            library_only = {}
            for key in sorted(now):
                is_exec = not re.search(r'\.so(\.|$)', key[0])
                # A library alone reports symbols that its program supplies; only a program
                # or a missing library is a certain failure without a baseline.
                if key[1] != 'undefined' or is_exec:
                    findings.append(f'{key[0]}: {key[1]} {key[2]} (no previous build to compare)')
                else:
                    library_only[key[0]] = library_only.get(key[0], 0) + 1
            for name, count in sorted(library_only.items()):
                notes.append(f'{name}: {count} symbols left to its program (no previous build to compare)')
    return findings, notes


def _depends(deb):
    fields = control_field(deb, 'Depends')
    return {re.split(r'[ (:]', alt.strip())[0] for part in fields.split(',') for alt in part.split('|') if alt.strip()}


def smoke(deb, table, timeout=10, extra_dirs=(), qualified=None):
    """Start smoke programs with immediate binding in the qualified, headless root."""
    if extra_dirs or qualified is None:
        raise package.Invalid('smoke requires archive-qualified inputs; supply sibling .debs')
    name, arch = control_field(deb, 'Package'), qualified.arch
    findings = []
    rows = [line.split('\t') for line in Path(table).read_text().splitlines()
            if line.strip() and not line.startswith('#')]
    with tempfile.TemporaryDirectory(prefix='inspect-smoke-', dir=qualified.directory) as root:
        extract(deb, root, qualified.owner.ensure_space)
        for row in rows:
            if row[0] != name:
                continue
            program = row[1].replace('{multiarch}', MULTIARCH.get(arch, arch))
            exe = Path(root) / program.lstrip('/')
            if not exe.is_file():
                findings.append(f'{program}: listed in the smoke table, missing from the package')
                continue
            args = row[2].split() if len(row) > 2 else ['--version']
            try:
                command, _ = loader_command(exe, Path(root), qualified) if _is_elf(exe) else ([program], False)
                run = qualified.run(command + args, {'LD_BIND_NOW': '1'}, timeout)
                text = run.stdout + run.stderr
                if 'bwrap:' in text:
                    findings.append(f'{program}: isolated smoke runner failed: {text.strip()[:300]}')
            except subprocess.TimeoutExpired as exc:
                text = (exc.stdout or b'').decode(errors='replace') + (exc.stderr or b'').decode(errors='replace')
            except (OSError, package.Invalid) as exc:
                findings.append(f'{program}: loader error at start: {exc}')
                continue
            if LOADER_ERRORS.search(text):
                findings.append(f'{program}: loader error at start: {text.strip()[:300]}')
    return findings


def check(new_deb, previous_deb=None, smoke_table=None, extra_dirs=(), archive_context=None, siblings=(),
          previous_siblings=None):
    """Compare correct old/new edition universes against one frozen public archive."""
    if extra_dirs or archive_context is None:
        raise package.Invalid('archive context required; configure --archive-config and --scratch, and supply sibling .debs')
    qualified = previous_qualified = None
    try:
        qualified = archive_context.qualify(new_deb, siblings)
        # the predecessor is qualified inside compare, after this build's narrow Recommends case (two live roots)
        findings, notes = compare(new_deb, previous_deb, qualified=qualified, archive_context=archive_context,
                                  siblings=siblings, previous_siblings=previous_siblings)
        if smoke_table:
            findings += smoke(new_deb, smoke_table, qualified=qualified)
        for note in notes:
            print(f'lc1 link note: {Path(new_deb).name}: {note}')
        if findings:
            raise package.Invalid(f'{Path(new_deb).name}: link check failed:\n  ' + '\n  '.join(findings))
        return notes
    finally:
        for context in (previous_qualified, qualified):
            if context is not None:
                context.close()
