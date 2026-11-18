#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make a generated stand-in for CNJ's ZIP: the same layout (one top folder, pjeoffice-pro.jar holding pjeoffice.jks, cutplayer4jfx.jar,
jre/bin/java, pjeoffice-update.properties, ffmpeg.exe) with generated content, so the installer's transaction can be tested for a
second version, a wrong digest, an interrupted download and a program that fails its checks without any file of CNJ.
Usage: make-fixture.py OUT_DIR VERSION [--bad-java] [--roots N]
Writes OUT_DIR/pjeoffice-pro-vVERSION-linux_x64.zip and OUT_DIR/catalogue-VERSION.json (address https://pje-fixture.test:8443/...)."""
import hashlib, json, os, subprocess, sys, tempfile, zipfile
from pathlib import Path
sys.path.insert(0, '/usr/lib/sparky-pjeoffice')
import jks

out, version = Path(sys.argv[1]), sys.argv[2]
bad_java = '--bad-java' in sys.argv
roots = int(sys.argv[sys.argv.index('--roots') + 1]) if '--roots' in sys.argv else 3
out.mkdir(parents=True, exist_ok=True)
work = Path(tempfile.mkdtemp(dir=out))


def certificate(name):
    key, crt = work / (name + '.key'), work / (name + '.crt')
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(key), '-out', str(crt), '-days', '3', '-subj', '/CN=' + name],
                   check=True, capture_output=True)
    pem = crt.read_text()
    from ssl import PEM_cert_to_DER_cert
    return PEM_cert_to_DER_cert(pem)


entries = [('generated-root-%d-%s' % (i, version), 1000 + i, certificate('pj18-fixture-%d-%s' % (i, version))) for i in range(roots)]
jar = work / 'pjeoffice-pro.jar'
with zipfile.ZipFile(jar, 'w', zipfile.ZIP_DEFLATED) as bundle:
    bundle.writestr('META-INF/MANIFEST.MF', 'Manifest-Version: 1.0\nMain-Class: br.jus.cnj.pje.office.imp.PjeOfficePROUser\n')
    bundle.writestr('pjeoffice.jks', jks.write(entries, 'pjeoffice'))
    bundle.writestr('generated.txt', 'generated fixture ' + version + '\n')
java = ('#!/bin/sh\necho \'openjdk version "1.8.0_999"\' >&2\nexit 1\n' if bad_java else
        '#!/bin/sh\nif [ "$1" = "-version" ]; then echo \'openjdk version "1.8.0_999"\' >&2; exit 0; fi\nexec sleep 3600\n')
properties = ('update.url=https://pje-office.pje.jus.br/pro/\nhelp.url = https://example.invalid/\nupdate.architecture=linux.x64.u\n')
top = 'pjeoffice-pro'
zpath = out / ('pjeoffice-pro-v%s-linux_x64.zip' % version)
with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in (('pjeoffice-pro.jar', jar.read_bytes()), ('cutplayer4jfx.jar', b'PK\x05\x06' + b'\0' * 18),
                       ('ffmpeg.exe', b'#!/bin/sh\nexit 0\n'), ('jre/bin/java', java.encode()), ('jre/bin/keytool', b'#!/bin/sh\nexit 0\n'),
                       ('pjeoffice-update.properties', properties.encode()), ('LEIA-ME.TXT', b'generated\n')):
        z.writestr(top + '/' + name, data)
data = zpath.read_bytes()
catalogue = {'format': 1, 'program': 'PJeOffice Pro', 'update_endpoint': 'https://pje-fixture.test:8443/update.properties', 'current': version,
             'versions': {version: {'url': 'https://pje-fixture.test:8443/' + zpath.name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                                    'top': top, 'java': '1.8.0', 'reviewed': 'generated'}}}
(out / ('catalogue-%s.json' % version)).write_text(json.dumps(catalogue, indent=1) + '\n')
subprocess.run(['rm', '-rf', str(work)])
print(zpath, len(data))
