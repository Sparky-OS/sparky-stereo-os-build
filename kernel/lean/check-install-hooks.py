#!/usr/bin/env python3
"""Execute package hooks with recording consumers in an isolated amd64 container.

Provide one --packages directory per flavour, with exactly one image archive and
one non-HR headers archive. Never execute these maintainer scripts on the host.
The output directory must not exist. This is not a boot or DKMS qualification.

It checks the maintainer scripts of builds 9 and 10 (run-parts loops, INITRD=Yes). From build 11 the image scripts are Debian's
(linux-run-hooks, linux-update-symlinks, linux-check-removal of linux-base): kernel/tests/maint-scripts-proof.sh runs them for
real against Debian's own packages instead of recording consumers.
"""
from pathlib import Path
import argparse
import io
import json
import re
import subprocess
import tarfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--packages', type=Path, action='append', required=True)
parser.add_argument('--old-image', type=Path, required=True,
                    help='Known broken image, to prove the negative control')
parser.add_argument('--container-image', required=True,
                    help='Prepared amd64 Debian image with sh, run-parts and coreutils')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = args.output.resolve()
root.mkdir()
fixtures = root / 'hook-fixtures'
fixtures.mkdir()

def archive(directory, pattern):
    matches = [p for p in directory.glob(pattern) if '-lc-hr_' not in p.name]
    assert len(matches) == 1, (directory, pattern, matches)
    return matches[0]

def package_name(path):
    return subprocess.check_output(
        ['dpkg-deb', '-f', str(path), 'Package'], text=True).strip()


def copy_script(package, phase, destination):
    data = subprocess.check_output(['dpkg-deb', '--ctrl-tarfile', str(package)])
    with tarfile.open(fileobj=io.BytesIO(data)) as control:
        destination.write_bytes(control.extractfile('./' + phase).read())


cases = []
for number, directory in enumerate(args.packages):
    flavour = 'case-' + str(number)
    image = archive(directory, 'linux-image-*.deb')
    release = package_name(image).removeprefix('linux-image-')
    assert re.fullmatch(r'[a-zA-Z0-9.+~-]+', release), release
    destination = fixtures / flavour
    destination.mkdir()
    for phase in ['preinst', 'postinst', 'prerm', 'postrm']:
        copy_script(image, phase, destination / phase)
    headers = archive(directory, 'linux-headers-*.deb')
    assert package_name(headers) == 'linux-headers-' + release
    copy_script(headers, 'postinst', destination / 'header_postinst')
    cases.append((flavour, release))
copy_script(args.old_image, 'postinst', fixtures / 'old-postinst')
old_release = package_name(args.old_image).removeprefix('linux-image-')
assert re.fullmatch(r'[a-zA-Z0-9.+~-]+', old_release), old_release
script='''#!/bin/sh
set -eu
export PATH=/test-bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /test-bin /boot
printf '#!/bin/sh\\nprintf "depmod|%%s\\\\n" "$*" >> /trace\\n' > /test-bin/depmod
chmod +x /test-bin/depmod
for root in /etc/kernel /usr/share/kernel; do
 [ ! -e "$root" ] || mv "$root" "$root.before-fixture"
 for phase in preinst postinst prerm postrm header_postinst; do
  mkdir -p "$root/$phase.d"
  case "$root" in /etc/*) origin=etc ;; *) origin=share ;; esac
  cat > "$root/$phase.d/record-$origin" <<EOF
#!/bin/sh
printf '%s|%s|%s|%s|%s\\n' '$phase' '$origin' "\\${INITRD-unset}" "\\${DEB_MAINT_PARAMS-unset}" "\\$*" >> /trace
EOF
  chmod +x "$root/$phase.d/record-$origin"
 done
done
touch /boot/System.map-OLD_RELEASE
: > /trace
sh /fixtures/old-postinst configure old-version
! grep -q '^postinst|' /trace
printf 'PASS expected old-package hook loss\\n'
'''.replace('OLD_RELEASE', old_release)
for flavour, release in cases:
    script += f'touch /boot/System.map-{release}\n'
    for phase in ['preinst', 'postinst', 'prerm', 'postrm', 'header_postinst']:
        if phase in ['postinst', 'header_postinst']:
            arg = 'configure'
        else:
            arg = 'remove' if phase in ['prerm', 'postrm'] else 'install'
        script += f': > /trace\nsh /fixtures/{flavour}/{phase} {arg} old-version\n'
        script += f'test "$(grep -c "^{phase}|" /trace)" = 2\n'
        script += f'grep -F "{arg} old-version|{release}" /trace >/dev/null\n'
        if phase in ['postinst', 'postrm']:
            script += 'head -n 1 /trace | grep -q "^depmod|"\n'
        if phase != 'header_postinst':
            script += f'grep -F "|Yes|{arg} old-version|{release} /boot/vmlinuz-{release}" /trace >/dev/null\n'
        script += f"printf 'PASS {flavour} {phase}\\n'\n"
(fixtures / 'test.sh').write_text(script)
command = ['docker', 'run', '--rm', '--network', 'none', '--platform', 'linux/amd64',
           '-v', str(fixtures) + ':/fixtures:ro', args.container_image,
           'sh', '/fixtures/test.sh']
with (root / 'hook-execution.log').open('w') as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
status = {
    'state': 'passed' if result.returncode == 0 else 'needs-repair',
    'exit_code': result.returncode,
    'scope': 'Actual image/header scripts, both hook roots, parameters, INITRD, '
             'depmod-before-hooks, and old-package negative control. '
             'Recording consumers do not generate boot files.',
}
(root / 'hook-execution-status.json').write_text(json.dumps(status, indent=2) + '\n')
assert result.returncode == 0
print(f'PASS {len(cases) * 5} kernel/header hook cases plus old-package negative control')
