#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Every installed Partners or caption catalogue enters the viewport matrix."""
import json
from pathlib import Path
languages={'en'}
languages.update(p.stem for p in Path('/usr/share/sparky-stereo/live-captions/lang').glob('*.json'))
languages.update(p.parent.parent.name for p in Path('/usr/share/locale').glob('*/LC_MESSAGES/kcm_sparkystereo_partners.mo'))
print(json.dumps(sorted(languages)))
