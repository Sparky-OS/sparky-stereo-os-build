#!/usr/bin/env python3
"""The check itself: each kind of finding is raised on a small repository, and the helper's forms pass. ORDER 400b."""
import os
import subprocess
import sys
import tempfile
import unittest

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'check.py')
FORM = ('RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \\\n'
        '    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \\\n'
        '    sh /run/https-only-apt.sh && apt-get update\n')
FILES = {
    'dockerfile-ok/Dockerfile': 'FROM debian:testing\n' + FORM,
    'dockerfile-bad/Dockerfile': 'FROM debian:testing\nRUN apt-get update && apt-get -y install gcc\n',
    'dockerfile-late/Dockerfile': 'FROM debian:testing\nRUN apt-get update && sh /run/https-only-apt.sh\n',
    'launcher-ok.sh': '#!/bin/sh\ndocker run --rm -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v tools/https-only-apt.sh:/run/https-only-apt.sh:ro debian:testing sh -c "sh /run/https-only-apt.sh && apt-get update"\n',
    'launcher-bad.sh': '#!/bin/sh\ndocker run --rm debian:testing sh -c "apt-get update && apt-get -y install gcc"\n',
    'launcher-py-bad.py': "import subprocess\nsubprocess.run(['docker', 'run', '--rm', 'debian:testing', 'sh', '-c', 'apt-get -y update'])\n",
    'inner-bad.sh': '#!/bin/sh\n# runs in a container\napt-get update\n',
    'inner-covered/outer.sh': '#!/bin/sh\ndocker run --rm -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v x:/run/https-only-apt.sh:ro debian:testing sh /t/inner.sh\n',
    'inner-covered/inner.sh': '#!/bin/sh\n# runs in a container\napt-get update\n',
    'no-apt.sh': '#!/bin/sh\ndocker run --rm debian:testing true\n',
    'src-bad.sh': "#!/bin/sh\nprintf 'deb http://deb.debian.org/debian testing main\\n' > /etc/apt/sources.list\n",
    'src-bad.sources': 'Types: deb\nURIs: http://deb.debian.org/debian\n',
    'src-ok.sh': "#!/bin/sh\nprintf 'deb https://deb.debian.org/debian testing main\\n' > /etc/apt/sources.list\n",
}
EXPECT = {'dockerfile-bad/Dockerfile', 'dockerfile-late/Dockerfile', 'launcher-bad.sh', 'launcher-py-bad.py', 'inner-bad.sh', 'src-bad.sh', 'src-bad.sources'}


class CheckTest(unittest.TestCase):
    def test_kinds(self):
        with tempfile.TemporaryDirectory() as root:
            for name, text in FILES.items():
                path = os.path.join(root, name)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w') as f:
                    f.write(text)
            subprocess.run(['git', 'init', '-q', root], check=True)
            subprocess.run(['git', '-C', root, 'add', '-A'], check=True)
            run = subprocess.run([sys.executable, '-I', CHECK, root], capture_output=True, text=True)
            self.assertEqual(run.returncode, 1, run.stdout)
            flagged = {line.split(':')[0] for line in run.stdout.splitlines() if ':' in line and not line.startswith('https-only-apt check')}
            self.assertEqual(flagged, EXPECT, run.stdout)

    def test_clean_repository_passes(self):
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, 'ok.sh'), 'w') as f:
                f.write(FILES['launcher-ok.sh'])
            subprocess.run(['git', 'init', '-q', root], check=True)
            subprocess.run(['git', '-C', root, 'add', '-A'], check=True)
            run = subprocess.run([sys.executable, '-I', CHECK, root], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout)


if __name__ == '__main__':
    unittest.main()
