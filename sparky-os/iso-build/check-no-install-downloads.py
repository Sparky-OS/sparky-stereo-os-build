#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
"""Refuse, in an image, any package that downloads data while it is installed, and FlightGear's data.

Daniel, 2026-11-04: "if the user choosed on install to include the games, that's already during install, so no big deal, and
yes, we will not ship with the iso heavy files ... aiming to max out at 7.5 Gb"; memory image-ships-our-stereo-programs:
"TORCS and FlightGear stay out". A package declares its install-time download in its control file (Install-Download-Size
and Install-Download-Source, sparky-stereo-apt's reader); a package that does so runs a download in its postinst, which an
image build must never do: it would put the data on the ISO or fail the build. This gate reads the image's dpkg status
(dpkg keeps the fields) and refuses every installed package that declares one, and the data folder FlightGear's downloader
fills.

  check-no-install-downloads.py [ROOT]          an image root (default /)
  check-no-install-downloads.py --status FILE   a dpkg status file only (the resolver model of simulate-image.py)

Exit status: 0 nothing found; 1 refused; 2 usage or an unreadable status file (nothing passes unread).
"""
import sys
from pathlib import Path

FIELD = 'Install-Download-Size'
DATA = ('usr/share/games/flightgear/version',)


def declared(status_text):
    found = []
    for stanza in status_text.split('\n\n'):
        fields = {}
        for line in stanza.splitlines():
            if line[:1] in ' \t' or ':' not in line:
                continue
            key, _, value = line.partition(':')
            fields[key] = value.strip()
        if FIELD in fields and fields.get('Status', 'install ok installed').endswith('installed'):
            found.append((fields.get('Package', '?'), fields[FIELD], fields.get('Install-Download-Source', '')))
    return found


def main(argv):
    if argv[:1] == ['--status'] and len(argv) == 2:
        status, root = Path(argv[1]), None
    elif len(argv) <= 1 and not argv[:1] == ['--status']:
        root = Path(argv[0] if argv else '/')
        status = root / 'var/lib/dpkg/status'
    else:
        print(__doc__.split('\n\n')[2], file=sys.stderr)
        return 2
    try:
        text = status.read_text(errors='replace')
    except OSError as error:
        print('check-no-install-downloads: cannot read %s: %s' % (status, error), file=sys.stderr)
        return 2
    bad = 0
    for name, size, source in declared(text):
        print('REFUSED %s is installed and downloads %s bytes from %s when it is installed: it does not belong on the image' % (name, size, source))
        bad = 1
    if root is not None:
        for rel in DATA:
            if (root / rel).exists():
                print('REFUSED /%s exists: FlightGear\'s data is on the image' % rel)
                bad = 1
    if not bad:
        print('PASS no installed package declares an install-time download%s' % ('' if root is None else ', and FlightGear\'s data is not there'))
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
