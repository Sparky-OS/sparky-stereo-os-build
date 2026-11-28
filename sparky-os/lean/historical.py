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


def failure_terminal(text):
    terminal = re.search(r'^   2\. .*', text, re.M)
    return text[terminal.start():] if terminal else text


def failure_owners(text):
    terminal = re.search(r'^   2\. .*', text, re.M)
    if terminal:
        owners = re.findall(r'^\s+(?:\d+\.\s+|- )?([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)?(?:=[^\s]+)? '
                            r'(?:PreDepends|Pre-Depends|Depends|Conflicts|Breaks)\b',
                            text[terminal.start():], re.M)
        return owners
    return re.findall(r'^ ([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)? : '
                      r'(?:PreDepends|Pre-Depends|Depends|Conflicts|Breaks):', text, re.M)


class EligibilityStop(package.Invalid):
    """A recorded predecessor refusal; collection mode may continue, but never pass it."""


def providers(controls):
    """Name presence, deliberately ignoring versions: an existing provider is never absent."""
    result = {}
    for obj, source in controls:
        # Presence is conservative, not a second archive-policy validator. Some
        # signed third-party indexes retain legacy mixed-case aliases that APT
        # accepts; retain their literal names rather than rejecting the index.
        names = [obj['Package']] + [re.split(r'[\s(:]', entry.strip(), maxsplit=1)[0]
                                  for entry in obj.get('Provides', '').split(',') if entry.strip()]
        for name in names:
            result.setdefault(name, []).append({'identity': archive.identity(obj), 'archive': source,
                                               'Provides': obj.get('Provides', '')})
    return result


def archive_providers(context, rows):
    controls = []
    for row in rows:
        data = subprocess.check_output(['/usr/lib/apt/apt-helper', 'cat-file', row['Packages']], env=context.env)
        for paragraph in data.decode().split('\n\n'):
            obj = archive.fields(paragraph)
            if obj.get('Package'):
                controls.append((obj, row['source']))
    return providers(controls)


def solver_evidence(failure):
    return [{'solver': a['solver'], 'sha256': archive.digest(a['solver']),
             'lines': Path(a['solver']).read_text(), 'enabled': a.get('enabled', [])}
            for a in failure.attempts]


class PreviousView:
    def __init__(self, current, config, published_at, candidates, policy=None, allow_unavailable=False, frozen_view=None):
        self.allow_unavailable = allow_unavailable
        self.cutoff = instant(published_at)
        self.candidates = {archive.identity(current.input(p)['control']) for p in candidates}
        self.names = {obj[0] for obj in self.candidates}
        self.candidate_controls = [current.input(p)['control'] for p in candidates]
        self.candidate_providers = providers((obj, 'candidate-set') for obj in self.candidate_controls)
        self.dated = archive.Archive(config, current.scratch / 'dated-predecessor', current.arch,
                                     current.minimum >> 30, current.root_minimum >> 30, frozen_view)
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
        self.current_providers = archive_providers(current, now_rows)
        self.dated_providers = archive_providers(self.dated, old_rows)
        self.owners = {name: {p['archive'] for p in entries} for name, entries in self.current_providers.items()}
        self.dated_owners = {name: {p['archive'] for p in entries} for name, entries in self.dated_providers.items()}
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
        try:
            return self._qualify(current, deb, siblings)
        except package.NoSpace:
            raise
        except (OSError, package.Invalid) as exc:
            current.predecessor_result['stop'] = str(exc)
            raise EligibilityStop(str(exc)) from exc

    def moved_relations(self, text, prior, previous_providers):
        """The terminal's exact relations on packages only outside archives carry, met at publication and not now.

        A published package of ours that pins an outside archive's version (the AAC codec's
        `libspa-0.2-bluetooth (= 1.6.9-2)`, row 933) stops solving when that archive moves, and its successor in
        the candidate set is the repair. The owner's name is then a candidate's while the cause is outside the
        candidate set. Every relation of the terminal must be such a pin, or none counts; the dated solve that
        follows still has to succeed.
        """
        terminal = failure_terminal(text)
        named = set(re.findall(r'(?:PreDepends|Pre-Depends|Depends):?\s+([a-z0-9][a-z0-9+.-]*)', terminal))
        pins = set(re.findall(r'(?:PreDepends|Pre-Depends|Depends):?\s+([a-z0-9][a-z0-9+.-]*)(?::[a-z0-9-]+)?'
                              r'\s*\((<<|<=|=|>=|>>)\s*([^\s()]+)\)', terminal))
        previous = {p['control']['Package'] for p in prior}
        if not pins or {name for name, _, _ in pins} != named or not set(failure_owners(text)) <= previous:
            return []
        moved = []
        for name, operator, version in sorted(pins):
            if name in self.candidate_providers or name in previous_providers:
                return []
            now = sorted({p['identity'][1] for p in self.current_providers.get(name, []) if p['identity'][0] == name})
            then = sorted({p['identity'][1] for p in self.dated_providers.get(name, []) if p['identity'][0] == name})
            if (any(archive.version_matches(v, operator, version) for v in now)
                    or not any(archive.version_matches(v, operator, version) for v in then)):
                return []
            moved.append({'name': name, 'relation': f'{operator} {version}', 'candidate_view': now,
                          'publication_view': then})
        return moved

    def absent_relations(self, current, deb, prior, failure):
        """A required path through exact previous inputs, ending at a name absent in both views.

        Alternative or unparsed groups never establish a required path. APT still
        solves both complete views; this proves absence, it does not solve relations.
        """
        previous = {p['control']['Package']: p['control'] for p in prior}
        previous_providers = providers((obj, 'previous-set') for obj in previous.values())
        logs = solver_evidence(failure)
        seen, pending, absent = set(), [(current.input(deb)['control']['Package'], [])], []
        candidate_by_name = {obj['Package']: obj for obj in self.candidate_controls}
        while pending:
            owner, chain = pending.pop()
            if owner in seen or owner not in previous:
                continue
            seen.add(owner)
            obj = previous[owner]
            for field in ('Depends', 'Pre-Depends'):
                for group in obj.get(field, '').split(','):
                    if not group.strip() or '|' in group:
                        continue
                    relations = list(archive.policy_relations(group))
                    name, qualifier, operator, version = relations[0]
                    if qualifier not in (None, 'native', current.arch):
                        continue
                    edge = {'owner': archive.identity(obj), 'field': field, 'relation': group.strip()}
                    path = chain + [edge]
                    if name in previous:
                        target = previous[name]
                        alternatives = (previous_providers.get(name, []) + self.current_providers.get(name, [])
                                        + self.dated_providers.get(name, []))
                        unique_owner = all(p['identity'][0] == name for p in alternatives)
                        if unique_owner and (not operator or archive.version_matches(target['Version'], operator, version)):
                            pending.append((name, path))
                    if any(name in p for p in (self.candidate_providers, previous_providers,
                                               self.current_providers, self.dated_providers)):
                        continue
                    # At least one real solver attempt must identify this missing
                    # relation. Other policy attempts may terminate at a policy conflict.
                    if not any(re.search(r'\b' + re.escape(owner) + r'(?::[a-z0-9-]+)?(?: :)? '
                               r'(?:PreDepends|Pre-Depends|Depends):?\s+' + re.escape(name) + r'(?![a-z0-9+.-])',
                               a['lines']) for a in logs):
                        continue
                    successor = candidate_by_name.get(owner)
                    if not successor:
                        continue
                    new_names = archive.hard_dependencies(successor) - archive.hard_dependencies(obj)
                    replacements = {n: self.current_providers.get(n, []) + self.candidate_providers.get(n, [])
                                    for n in sorted(new_names)}
                    absent.append({'name': name, 'required_path': path, 'candidate_relation_owner': archive.identity(successor),
                                   'successor_dependencies': replacements,
                                   'providers': {'candidate-set': [], 'previous-set': [], 'candidate-archives': [], 'dated-archives': []}})
        return absent

    def unavailable(self, current, deb, prior, failure, affected):
        """No permitted historical universe can be assembled; never inherit its findings."""
        blocked = [dict(row, reason='named by failed solve; no dated signed index exists')
                   for row in self.archives if row['source'] in affected & self.exempt]
        if not self.allow_unavailable or not blocked:
            raise package.Invalid('solver failure names an archive with only a later index: ' +
                                  ', '.join(row['archive'] for row in blocked))
        record = {'view': 'no-baseline-available', 'predecessor': str(deb),
                  'publication': self.cutoff.isoformat(), 'archives': [dict(row, view='unavailable' if row['source'] in affected & self.exempt else 'not-used', reason='no predecessor comparison; candidate must pass independently') for row in self.archives],
                  'unavailable_archives': blocked, 'archive_evidence': self.evidence,
                  'failure_in_candidate_view': solver_evidence(failure),
                  'previous_inputs': [{'identity': archive.identity(p['control']), 'sha256': p['sha256']} for p in prior],
                  'reason': 'current view failed; a required publication archive has no dated signed index; mixed solve forbidden'}
        current.predecessor_result = record
        (Path(failure.directory) / 'no-baseline-available.json').write_text(json.dumps(record, indent=2) + '\n')
        return None

    def _qualify(self, current, deb, siblings):
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
            current.predecessor_result['failure_in_candidate_view'] = solver_evidence(exc)
            absent = self.absent_relations(current, deb, prior, exc)
            if absent:
                # Unrelated current indexes are still permitted only when no failure
                # names one of their packages, including the complete request chain.
                for attempt in failures:
                    named = failure_names(Path(attempt['solver']).read_text())
                    affected = set().union(*(self.owners.get(n, set()) for n in named))
                    if affected & self.exempt:
                        return self.unavailable(current, deb, prior, exc, affected)
                current.predecessor_result['attempted'] = self.mode
                try:
                    qualified = self.dated.qualify(deb, siblings)
                except archive.PolicySolveFailure as old_failure:
                    current.predecessor_result['failure_in_publication_view'] = solver_evidence(old_failure)
                    for attempt in old_failure.attempts:
                        named = failure_names(Path(attempt['solver']).read_text())
                        affected = set().union(*(self.dated_owners.get(n, set()) for n in named))
                        if affected & self.exempt:
                            raise package.Invalid('dated solver failure names an archive with only a later index: ' + attempt['solver'])
                    dated_absent = self.absent_relations(current, deb, prior, old_failure)
                    both = [row for row in absent if row in dated_absent]
                    if not both:
                        raise package.Invalid('dated solver does not confirm the same absent external relation') from old_failure
                    record = {'view': 'uninstallable-at-publication', 'predecessor': str(deb),
                              'publication': self.cutoff.isoformat(), 'archives': self.archives,
                              'missing_relations': both,
                              'failure_in_candidate_view': solver_evidence(exc),
                              'failure_in_publication_view': solver_evidence(old_failure),
                              'archive_evidence': self.evidence,
                              'previous_inputs': [{'identity': archive.identity(p['control']), 'sha256': p['sha256']} for p in prior]}
                    current.predecessor_result = record
                    (Path(exc.directory) / 'uninstallable-at-publication.json').write_text(json.dumps(record, indent=2) + '\n')
                    return None
                else:
                    # A solvable dated predecessor always remains a real baseline.
                    record = {'view': self.mode, 'archives': self.archives, 'predecessor': str(deb),
                              'publication': self.cutoff.isoformat(), 'failure_in_candidate_view': solver_evidence(exc)}
                    current.predecessor_result = record
                    return qualified
            reasons = []
            changed_causes = set()
            for attempt in failures:
                text = Path(attempt['solver']).read_text()
                # APT 3's terminal conflicting assignment is the unsatisfied relation;
                # its preceding numbered chain explains why that package was requested.
                owners = failure_owners(text)
                previous_providers = providers((p['control'], 'previous-set') for p in prior)
                candidate_owned = self.names.intersection(owners)
                external_relations = set(re.findall(r'(?:PreDepends|Pre-Depends|Depends):?\s+([a-z0-9][a-z0-9+.-]*)', failure_terminal(text)))
                external_missing = (external_relations and all(n not in self.candidate_providers and n not in previous_providers
                                    and n not in self.current_providers for n in external_relations))
                moved = (self.moved_relations(text, prior, previous_providers)
                         if owners and candidate_owned and not external_missing else [])
                if not owners or (candidate_owned and not external_missing and not moved):
                    raise package.Invalid('predecessor failure is not exclusively outside the candidate set; '
                                          f'see {attempt["solver"]}') from exc
                names = failure_names(text)
                attribution = {n: sorted(self.owners.get(n, ())) for n in sorted(names)}
                affected = set().union(*(set(v) for v in attribution.values()))
                if affected & self.exempt:
                    blocked = [r['archive'] for r in self.archives if r['source'] in affected & self.exempt]
                    return self.unavailable(current, deb, prior, exc, affected)
                changed_causes.update(set().union(*(self.owners.get(n, set()) for n in owners)) & self.changed)
                if external_missing or moved:
                    changed_causes.update(set().union(*(self.dated_owners.get(n, set()) for n in external_relations)) & self.changed)
                reasons.append({'solver': attempt['solver'], 'sha256': archive.digest(attempt['solver']),
                                'outside_candidate': sorted(set(owners)), 'named_package_archives': attribution,
                                **({'moved_outside_relations': moved} if moved else {})})
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
