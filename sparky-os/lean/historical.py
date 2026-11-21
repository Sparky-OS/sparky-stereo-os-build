# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Optional dated public indexes for an otherwise unsolvable published predecessor."""

from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from . import archive, package


def instant(value):
    try:
        result = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if result.tzinfo is None:
            raise ValueError('timezone missing')
        return result.astimezone(timezone.utc)
    except (AttributeError, ValueError) as exc:
        raise package.Invalid(f'invalid publication instant: {value!r}') from exc


def authenticated_view(context, cutoff=None, cutoff_exempt=()):
    """Bind every APT-authenticated Packages target back to its signed InRelease."""
    targets = context.run(['apt-get', 'indextargets'], 'historical-index-targets')
    frozen = {row['path']: row for row in context.metadata}
    rows, sources = [], {}
    for paragraph in targets.strip().split('\n\n'):
        target = archive.fields(paragraph)
        if target.get('Identifier') != 'Packages':
            continue
        path = Path(target['Filename'])
        meta = target['MetaKey']
        suffix = meta.replace('_', '%5f').replace('/', '_')
        name = path.name
        for ext in ('.lz4', '.xz', '.gz', '.bz2', '.zst'):
            if name.endswith(ext):
                name = name[:-len(ext)]
                break
        if not name.endswith(suffix) or target.get('Trusted') != 'yes':
            raise package.Invalid(f'unqualified Packages target: {path}')
        release = path.with_name(name[:-len(suffix)] + 'InRelease')
        for item in (path, release):
            rel = str(item.relative_to(context.base))
            if rel not in frozen or archive.digest(item) != frozen[rel]['sha256']:
                raise package.Invalid(f'authenticated metadata missing or changed: {item}')
        body = release.read_text().split('\n\n', 1)[1].split('\n-----BEGIN PGP SIGNATURE-----', 1)[0]
        info = archive.fields(body)
        try:
            date = parsedate_to_datetime(info['Date'])
            if date.tzinfo is None:
                raise ValueError('signed Date has no timezone')
            date = date.astimezone(timezone.utc)
        except (KeyError, TypeError, ValueError) as exc:
            raise package.Invalid(f'{release}: missing or invalid signed Date') from exc
        entry = target['Sourcesentry'].rsplit(':', 1)[1]
        dated = cutoff is not None and entry not in cutoff_exempt
        if dated and date > cutoff:
            raise package.Invalid(f'{release}: dated view is later than predecessor publication: {date.isoformat()}')
        if dated and info.get('Origin') == 'Debian':
            match = re.fullmatch(r'https://snapshot\.debian\.org/archive/(debian(?:-security)?)/(\d{8}T\d{6}Z)/?',
                                 target['Repo-URI'])
            if not match or datetime.strptime(match[2], '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc) > cutoff:
                raise package.Invalid('dated Debian view requires snapshot.debian.org at or before publication')
        expected = {}
        for line in info.get('SHA256', '').splitlines():
            words = line.split()
            if len(words) == 3:
                expected[words[2]] = (words[0], int(words[1]))
        # apt-helper decodes exactly the retained target; no new download or trust decision.
        context.ensure_space(path.stat().st_size * 12)
        data = subprocess.check_output(['/usr/lib/apt/apt-helper', 'cat-file', str(path)], env=context.env)
        actual = hashlib.sha256(data).hexdigest(), len(data)
        if expected.get(meta) != actual:
            raise package.Invalid(f'{path}: Packages differs from its InRelease SHA256')
        key = Path(target['Signed-By'])
        identity = {k: info.get(k, '') for k in ('Origin', 'Label', 'Suite', 'Codename')}
        entry = target['Sourcesentry'].rsplit(':', 1)[1]
        source = context.sources[[i for i in range(len(context.sources)) if i not in context.skipped_sources][int(entry)-1]]
        signature = (source['suite'], tuple(source.get('components', [])),
                     tuple(source.get('architectures', [])), archive.digest(key), tuple(identity.items()))
        sources[entry] = signature
        rows.append({'source': entry, 'identity': identity, 'date': date.isoformat(),
                     'uri': target['URI'], 'InRelease': str(release), 'InRelease_sha256': archive.digest(release),
                     'key_sha256': archive.digest(key), 'Packages': str(path), 'Packages_sha256': actual[0],
                     'Packages_size': actual[1], 'MetaKey': meta, 'Repo-URI': target['Repo-URI']})
    active = len(context.sources) - len(context.skipped_sources)
    if len(sources) != active or not rows:
        raise package.Invalid('dated view must authenticate Packages from every configured archive')
    found = {row['Packages'] for row in rows}
    for item in context.metadata:
        if re.search(r'_Packages(?:\.(?:lz4|xz|gz|bz2|zst))?$', item['path']):
            if str(context.base / item['path']) not in found:
                raise package.Invalid('unbound Packages file in dated view')
    return sources, rows


def retain_view(context, destination):
    """Copy authenticated archive views, never hard-link them, for the round's supply-chain record."""
    _, rows = authenticated_view(context)
    destination = Path(destination) / context.arch
    destination.mkdir(parents=True, exist_ok=True)
    files = {Path(row[field]) for row in rows for field in ('InRelease', 'Packages')}
    files.update((context.base / 'etc').glob('key-*.gpg'))
    for path in sorted(files):
        target = destination / path.relative_to(context.base)
        target.parent.mkdir(parents=True, exist_ok=True)
        context.ensure_space(path.stat().st_size)
        shutil.copyfile(path, target)
        if archive.digest(path) != archive.digest(target):
            raise package.Invalid(f'archive view copy changed: {path}')
    for row in rows:
        for field in ('InRelease', 'Packages'):
            row[field] = str(Path(row[field]).relative_to(context.base))
    (destination / 'archive-view.json').write_text(json.dumps({'architecture': context.arch,
        'sources': context.sources, 'authenticated_indexes': rows,
        'qualification': 'APT Signed-By plus independent Packages/InRelease hash equality'}, indent=2) + '\n')
    (destination / 'SHA256SUMS').write_text(''.join(archive.digest(path) + '  ' + str(path.relative_to(destination)) + '\n'
        for path in sorted(destination.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS'))
    return destination


def search_evidence(policy, context, cutoff):
    if policy is None:
        return {}
    obj = json.loads(Path(policy).read_text())
    if instant(obj.get('publication', '')) != cutoff:
        raise package.Invalid('historical search evidence has a different publication cutoff')
    entries = obj.get('candidate_frozen', {})
    active = [s for i, s in enumerate(context.sources) if i not in context.skipped_sources]
    for number, row in entries.items():
        if not number.isdigit() or not 1 <= int(number) <= len(active):
            raise package.Invalid('historical search names an unknown archive')
        source = active[int(number)-1]
        if row.get('uri', '').rstrip('/') != source['uri'].rstrip('/') or row.get('suite') != source['suite']:
            raise package.Invalid('historical search evidence does not identify its archive')
        searches = row.get('searches', [])
        if {s.get('method') for s in searches} != {'official-mirrors', 'retained-baseline', 'archive-search'}:
            raise package.Invalid('historical search needs official mirrors, retained baseline and archive search evidence')
        for search in searches:
            if search.get('result') != 'no-dated-signed-copy' or not search.get('summary') or not search.get('files'):
                raise package.Invalid('historical search does not record absence of a dated signed copy')
            for evidence in search['files']:
                path = Path(evidence['path'])
                if not path.is_file() or archive.digest(path) != evidence.get('sha256'):
                    raise package.Invalid(f'historical search evidence missing or changed: {path}')
    return entries


def package_archives(context, rows):
    result = {}
    for row in rows:
        data = subprocess.check_output(['/usr/lib/apt/apt-helper', 'cat-file', row['Packages']], env=context.env)
        for name in re.findall(rb'^Package: ([^\n]+)', data, re.M):
            result.setdefault(name.decode(), set()).add(row['source'])
    return result


def failure_names(text):
    names = set(re.findall(r'\b([a-z0-9][a-z0-9+.-]*):(?:amd64|i386|all|native)\b', text))
    names.update(re.findall(r'(?:PreDepends|Pre-Depends|Depends|Conflicts|Breaks):?\s+([a-z0-9][a-z0-9+.-]*)', text))
    return names | set(failure_owners(text))


def failure_owners(text):
    terminal = re.search(r'^   2\. .*', text, re.M)
    if terminal:
        owners = re.findall(r'^\s+(?:\d+\.\s+|- )?([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)? '
                            r'(?:PreDepends|Pre-Depends|Depends|Conflicts|Breaks)\b',
                            text[terminal.start():], re.M)
        return owners
    return re.findall(r'^ ([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)? : '
                      r'(?:PreDepends|Pre-Depends|Depends|Conflicts|Breaks):', text, re.M)


class PreviousView:
    def __init__(self, current, config, published_at, candidates, policy=None):
        self.cutoff = instant(published_at)
        self.candidates = {archive.identity(current.input(p)['control']) for p in candidates}
        self.names = {obj[0] for obj in self.candidates}
        self.dated = archive.Archive(config, current.scratch / 'dated-predecessor', current.arch,
                                     current.minimum >> 30, current.root_minimum >> 30)
        now_sources, now_rows = authenticated_view(current)
        exceptions = search_evidence(policy, current, self.cutoff)
        old_sources, old_rows = authenticated_view(self.dated, self.cutoff, exceptions)
        if now_sources != old_sources:
            raise package.Invalid('dated predecessor view must contain the same archives, components and signing keys')
        self.archives = []
        self.exempt = set(exceptions)
        self.changed = set()
        for number in now_sources:
            new = [r for r in now_rows if r['source'] == number]
            old = [r for r in old_rows if r['source'] == number]
            def hashes(rows):
                return {(r['MetaKey'], r['InRelease_sha256'], r['Packages_sha256']) for r in rows}
            equal = hashes(new) == hashes(old)
            label = new[0]['Repo-URI'] + ' [' + new[0]['identity']['Suite'] + ']'
            if number in exceptions:
                if not equal:
                    raise package.Invalid(f'{label}: unrelated archive differs from candidate frozen index')
                mode, reason = 'candidate-frozen', 'no dated signed copy; bound search evidence; absent from solver failure'
            elif equal:
                mode, reason = 'candidate-frozen', 'identical signed index already at or before publication'
            else:
                self.changed.add(number)
                mode, reason = 'dated', 'signed snapshot at or before publication'
            self.archives.append({'source': number, 'archive': label, 'view': mode, 'reason': reason,
                                  'InRelease_sha256': old[0]['InRelease_sha256'],
                                  'candidate_InRelease_sha256': new[0]['InRelease_sha256']})
        self.owners = package_archives(current, now_rows)
        self.dated_owners = package_archives(self.dated, old_rows)
        self.mode = 'mixed' if exceptions else 'dated'
        self.evidence = {'publication': self.cutoff.isoformat(), 'candidate': now_rows, 'dated': old_rows,
                         'archive_decisions': self.archives, 'search_evidence': exceptions}
        (current.base / 'predecessor-views.json').write_text(json.dumps(self.evidence, indent=2) + '\n')
        # Candidate packages must not be available from the public indexes used by the previous edition.
        for context in (current, self.dated):
            available = context.run(['apt-cache', 'dumpavail'], 'historical-public-universe')
            contamination = [archive.identity(obj) for p in available.split('\n\n')
                             if (obj := archive.fields(p)).get('Package') and archive.identity(obj) in self.candidates]
            if contamination:
                raise package.Invalid(f'candidate packages in predecessor public universe: {contamination}')

    def private(self):
        import copy
        other = copy.copy(self)
        other.dated = self.dated.private()
        return other

    def qualify(self, current, deb, siblings):
        prior = [current.input(p) for p in dict.fromkeys([deb] + list(siblings))]
        overlap = [archive.identity(p['control']) for p in prior if archive.identity(p['control']) in self.candidates]
        if overlap:
            raise package.Invalid(f'candidate packages in previous edition snapshot: {overlap}')
        current.predecessor_result = {'view': 'unqualified', 'attempted': 'candidate', 'predecessor': str(deb)}
        try:
            qualified = current.qualify(deb, siblings)
            current.predecessor_result['view'] = 'candidate'
            current.predecessor_result['archives'] = [dict(r, view='candidate', reason='predecessor solves in candidate view',
                                                            InRelease_sha256=r['candidate_InRelease_sha256'])
                                                       for r in self.archives]
            return qualified
        except archive.PolicySolveFailure as exc:
            # Only a complete dependency-solver refusal is eligible; download, signature,
            # extraction, runtime and space failures never enter the dated path.
            failures = getattr(exc, "attempts", ())
            reasons = []
            changed_causes = set()
            for attempt in failures:
                text = Path(attempt['solver']).read_text()
                # APT 3's terminal conflicting assignment is the unsatisfied relation;
                # its preceding numbered chain explains why that package was requested.
                owners = failure_owners(text)
                if not owners or self.names.intersection(owners):
                    raise package.Invalid('predecessor failure is not exclusively outside the candidate set; '
                                          f'see {attempt["solver"]}') from exc
                names = failure_names(text)
                attribution = {n: sorted(self.owners.get(n, ())) for n in sorted(names)}
                affected = set().union(*(set(v) for v in attribution.values()))
                if affected & self.exempt:
                    blocked = [r['archive'] for r in self.archives if r['source'] in affected & self.exempt]
                    raise package.Invalid('solver failure names an archive with only a later index: ' +
                                          ', '.join(blocked) + '; see ' + attempt['solver']) from exc
                changed_causes.update(set().union(*(self.owners.get(n, set()) for n in owners)) & self.changed)
                reasons.append({'solver': attempt['solver'], 'sha256': archive.digest(attempt['solver']),
                                'outside_candidate': sorted(set(owners)), 'named_package_archives': attribution})
            if not reasons:
                raise package.Invalid('no recorded previous-edition solver failure') from exc
            if self.exempt and not changed_causes:
                raise package.Invalid('no changed dated archive is identified by the predecessor failure') from exc
            record = {'view': self.mode, 'archives': self.archives, 'predecessor': str(deb), 'publication': self.cutoff.isoformat(),
                      'failure_in_candidate_view': reasons,
                      'previous_inputs': [{'identity': archive.identity(p['control']), 'sha256': p['sha256']} for p in prior]}
            (Path(exc.directory) / 'dated-predecessor-eligibility.json').write_text(json.dumps(record, indent=2) + '\n')
            current.predecessor_result['attempted'] = self.mode
            try:
                qualified = self.dated.qualify(deb, siblings)
            except archive.PolicySolveFailure as failure:
                details = []
                for attempt in failure.attempts:
                    text = Path(attempt['solver']).read_text()
                    owners = failure_owners(text)
                    named = {n: [r['archive'] for r in self.archives if r['source'] in self.dated_owners.get(n, ())]
                             for n in owners}
                    details.append({'solver': attempt['solver'], 'package_archives': named, 'lines': text})
                (Path(failure.directory) / 'mixed-view-failure.json').write_text(json.dumps(details, indent=2) + '\n')
                raise package.Invalid('predecessor does not solve in the dated/mixed view: ' +
                                      json.dumps(details, indent=2)) from failure
            current.predecessor_result = record
            (qualified.directory / 'predecessor-view.json').write_text(json.dumps(record, indent=2) + '\n')
            return qualified
