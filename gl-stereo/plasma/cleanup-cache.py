# SPDX-License-Identifier: GPL-2.0-or-later
"""Discard only the completed private rig's rebuildable shader caches."""
from pathlib import Path
import shutil
for cache in Path('out/plasma').glob('rig-verify-*/home/.cache'):
    shutil.rmtree(cache)
