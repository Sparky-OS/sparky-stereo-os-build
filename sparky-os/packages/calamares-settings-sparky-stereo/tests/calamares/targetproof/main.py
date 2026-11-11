# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Register an already copied disposable target; never partition or mount a disk."""
import os
from pathlib import Path
import libcalamares


def pretty_name():
    return 'Register the disposable target for the font-step proof'


def run():
    root = Path(os.environ['CORE_FONTS_TEST_TARGET']).resolve(strict=True)
    if root == Path('/') or not (root / 'var/lib/dpkg/status').is_file():
        return ('Invalid disposable target', str(root))
    libcalamares.globalstorage.insert('rootMountPoint', str(root))
    # The ordinary locale job supplies this map; omit disk and locale jobs here.
    libcalamares.globalstorage.insert('localeConf', {'LANG': os.environ.get('CORE_FONTS_TEST_LOCALE', 'en_US.UTF-8')})
    return None
