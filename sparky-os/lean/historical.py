# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Optional dated public indexes for an otherwise unsolvable published predecessor."""

from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import hashlib
import json
from pathlib import Path
import re
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


def authenticated_view(context, cutoff=None):
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
        if cutoff is not None and date > cutoff:
            raise package.Invalid(f'{release}: dated view is later than predecessor publication: {date.isoformat()}')
        if cutoff is not None and info.get('Origin') == 'Debian':
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
                     'Packages_size': actual[1], 'MetaKey': meta})
    active = len(context.sources) - len(context.skipped_sources)
    if len(sources) != active or not rows:
        raise package.Invalid('dated view must authenticate Packages from every configured archive')
    found = {row['Packages'] for row in rows}
    for item in context.metadata:
        if re.search(r'_Packages(?:\.(?:lz4|xz|gz|bz2|zst))?$', item['path']):
            if str(context.base / item['path']) not in found:
                raise package.Invalid('unbound Packages file in dated view')
    return sources, rows


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
    def __init__(self, current, config, published_at, candidates):
        self.cutoff = instant(published_at)
        self.candidates = {archive.identity(current.input(p)['control']) for p in candidates}
        self.names = {obj[0] for obj in self.candidates}
        self.dated = archive.Archive(config, current.scratch / 'dated-predecessor', current.arch,
                                     current.minimum >> 30, current.root_minimum >> 30)
        now_sources, now_rows = authenticated_view(current)
        old_sources, old_rows = authenticated_view(self.dated, self.cutoff)
        if now_sources != old_sources:
            raise package.Invalid('dated predecessor view must contain the same archives, components and signing keys')
        self.evidence = {'publication': self.cutoff.isoformat(), 'candidate': now_rows, 'dated': old_rows}
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
            return qualified
        except archive.PolicySolveFailure as exc:
            # Only a complete dependency-solver refusal is eligible; download, signature,
            # extraction, runtime and space failures never enter the dated path.
            failures = getattr(exc, "attempts", ())
            reasons = []
            for attempt in failures:
                text = Path(attempt['solver']).read_text()
                # APT 3's terminal conflicting assignment is the unsatisfied relation;
                # its preceding numbered chain explains why that package was requested.
                owners = failure_owners(text)
                if not owners or self.names.intersection(owners):
                    raise package.Invalid('predecessor failure is not exclusively outside the candidate set; '
                                          f'see {attempt["solver"]}') from exc
                reasons.append({'solver': attempt['solver'], 'sha256': archive.digest(attempt['solver']),
                                'outside_candidate': sorted(set(owners))})
            if not reasons:
                raise package.Invalid('no recorded previous-edition solver failure') from exc
            record = {'view': 'dated', 'predecessor': str(deb), 'publication': self.cutoff.isoformat(),
                      'failure_in_candidate_view': reasons,
                      'previous_inputs': [{'identity': archive.identity(p['control']), 'sha256': p['sha256']} for p in prior]}
            (Path(exc.directory) / 'dated-predecessor-eligibility.json').write_text(json.dumps(record, indent=2) + '\n')
            current.predecessor_result['attempted'] = 'dated'
            qualified = self.dated.qualify(deb, siblings)
            current.predecessor_result = record
            (qualified.directory / 'predecessor-view.json').write_text(json.dumps(record, indent=2) + '\n')
            return qualified
