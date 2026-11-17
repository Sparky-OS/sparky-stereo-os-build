#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Report unstable source presence for every excluded base binary before ISO construction."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys
from urllib.request import urlopen


def rows(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 2 or not all(fields) or fields[0] in result:
            raise ValueError(f'{path}: malformed or duplicate row: {line}')
        if not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', fields[0]):
            raise ValueError(f'{path}: invalid binary name: {fields[0]}')
        result[fields[0]] = fields[1]
    return result


def suites(source, record):
    if not isinstance(record, dict):
        raise ValueError(f'{source}: invalid sources.debian.org response')
    if record.get('error') == 404:
        return {}, {}
    if record.get('package') != source or not isinstance(record.get('versions'), list):
        raise ValueError(f'{source}: invalid sources.debian.org response')
    sid, testing = {}, {}
    for version in record['versions']:
        if not isinstance(version, dict) or not isinstance(version.get('suites'), list) or not isinstance(version.get('version'), str):
            raise ValueError(f'{source}: invalid version record')
        if 'sid' in version['suites'] and not sid:
            sid = version
        if 'forky' in version['suites'] and not testing:
            testing = version
    return sid, testing


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gone', type=Path, default=here.parent / 'lists/base-gone.tsv')
    parser.add_argument('--sources', type=Path, default=here.parent / 'lists/base-gone-sources.tsv')
    parser.add_argument('--snapshot', type=Path, help='Replay a saved response set for offline tests/review')
    parser.add_argument('--save', type=Path, help='Save the exact live response set outside the source tree')
    args = parser.parse_args()
    gone, mapping = rows(args.gone), rows(args.sources)
    missing = gone.keys() - mapping.keys()
    if missing:
        raise ValueError('base-gone sources unmapped: ' + ', '.join(sorted(missing)))
    # A mapping can retain a published binary: it is no longer reported after its gone row leaves.
    sources = sorted({mapping[name] for name in gone} - {'-'})
    if any(not re.fullmatch(r'[a-z0-9][a-z0-9+.-]*', source) for source in sources):
        raise ValueError('invalid source name')
    snapshot = json.loads(args.snapshot.read_text()) if args.snapshot else None
    responses, errors = {}, {}

    def fetch(source):
        try:
            if snapshot is not None:
                record = snapshot['responses'][source]
            else:
                with urlopen(f'https://sources.debian.org/api/src/{source}/', timeout=45) as response:
                    record = json.load(response)
            suites(source, record)
            return source, record, None
        except (OSError, ValueError, KeyError, TypeError) as error:
            return source, None, str(error)

    with ThreadPoolExecutor(max_workers=4) as pool:
        for source, record, error in pool.map(fetch, sources):
            if error is None:
                responses[source] = record
            else:
                errors[source] = error
    if args.save:
        args.save.write_text(json.dumps({'checked_at': datetime.now(timezone.utc).isoformat(),
                                        'responses': responses, 'errors': errors}, indent=2) + '\n')
    print('binary\tsource\tunstable\ttesting\tunstable-version\tclassification')
    for name in gone:
        source = mapping[name]
        if source == '-':
            print(f'{name}\t-\tNO\tNO\t-\tEXTERNAL-NOT-DEBIAN')
        elif source in errors:
            print(f'{name}\t{source}\tUNKNOWN\tUNKNOWN\t-\tERROR')
        else:
            sid, testing = suites(source, responses[source])
            state = 'SID-ONLY-REVIEW' if sid and not testing else 'SOURCE-IN-TESTING' if testing else 'NO-SID-SOURCE'
            print(f'{name}\t{source}\t{"YES" if sid else "NO"}\t{"YES" if testing else "NO"}\t{sid.get("version", "-")}\t{state}')
    for source, error in errors.items():
        print(f'base-gone source check: {source}: {error}', file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'base-gone source check: {error}', file=sys.stderr)
        sys.exit(1)
