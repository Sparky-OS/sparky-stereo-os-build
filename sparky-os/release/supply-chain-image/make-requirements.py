#!/usr/bin/env python3
"""Write requirements.txt with a sha256 for every package the supply-chain tools need (ORDER 394b).

Run it inside the tools image's base (Python 3.14, network, no other tool):
    python3 make-requirements.py top-level.txt requirements.txt
It installs the pinned top-level packages in a throwaway virtual environment to resolve their dependencies, downloads
each resolved package once (pip download, no dependencies), takes the sha256 of the bytes it got, asks PyPI's JSON API
(https://pypi.org/pypi/NAME/VERSION/json, field urls[].digests.sha256) for the hash PyPI declares for that same file name,
and stops unless the two agree. The Dockerfile installs with `pip install --require-hashes`, so a changed upload fails.
"""
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def main(top, out):
    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        run(sys.executable, '-m', 'venv', str(work / 'v'))
        pip = str(work / 'v/bin/pip')
        run(pip, 'install', '-q', '-r', top)
        pins = []
        for line in run(pip, 'freeze').splitlines():
            if re.fullmatch(r'[A-Za-z0-9._-]+==[A-Za-z0-9._!+-]+', line):
                pins.append(line)
            elif line:
                sys.exit('unexpected freeze line (a pin is needed): ' + line)
        rows = []
        for pin in sorted(pins, key=str.lower):
            name, version = pin.split('==')
            dl = work / 'dl' / name
            run(pip, 'download', '-q', '--no-deps', '-d', str(dl), pin)
            files = sorted(dl.iterdir())
            if len(files) != 1:
                sys.exit(f'{pin}: pip downloaded {len(files)} files')
            data = files[0].read_bytes()
            ours = hashlib.sha256(data).hexdigest()
            url = f'https://pypi.org/pypi/{name}/{version}/json'
            with urllib.request.urlopen(url, timeout=60) as response:
                declared = {f['filename']: f['digests']['sha256'] for f in json.load(response)['urls']}
            if declared.get(files[0].name) != ours:
                sys.exit(f'{pin}: {files[0].name} sha256 {ours} differs from PyPI\'s {declared.get(files[0].name)}')
            rows.append(f'{pin} \\\n    --hash=sha256:{ours}')
            print(f'{pin}: {files[0].name} {ours}', file=sys.stderr)
    Path(out).write_text('# Written by make-requirements.py; installed with pip install --require-hashes --no-deps.\n' +
                         '\n'.join(rows) + '\n')


if __name__ == '__main__':
    main(*sys.argv[1:3])
