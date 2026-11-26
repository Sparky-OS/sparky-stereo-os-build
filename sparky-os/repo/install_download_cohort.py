# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the install-time download providers in the selected publication set."""
import re

from sparky_install_downloads import FIELD_SIZE, FIELD_SOURCE, declaration

REQUIRES = 'Sparky-Install-Download-Requires'
CONTROL_FIELDS = (REQUIRES, FIELD_SIZE, FIELD_SOURCE)
CALAMARES = 'calamares-settings-sparky-stereo'
FIRST_FONTS_STEP = '20261111.1~sparky9~0'
PACKAGE_NAME = re.compile(r'[a-z0-9][a-z0-9+.-]+\Z')


def provider(records, name, arch, compare):
    native = 'amd64' if arch == 'amd64v3' else arch
    specific = records.get((name, arch)) or records.get((name, native))
    common = records.get((name, 'all'))
    if not specific:
        return common
    if common and compare(common[0], specific[0]) > 0:
        return common
    return specific


def check_install_downloads(records, compare):
    """Yield problems from the newest selected binaries, before changing the pool."""
    native_arches = sorted({arch for _, arch in records if arch != 'all'}) or ['all']
    if 'amd64' not in native_arches and native_arches != ['all']:
        native_arches.insert(0, 'amd64')

    for (consumer, arch), (version, fields) in sorted(records.items()):
        declared = fields.get(REQUIRES)
        if declared is None:
            if consumer != CALAMARES or compare(version, FIRST_FONTS_STEP) < 0:
                continue
            # Published settings before this field already have shellprocess@corefonts.
            declared = 'ttf-mscorefonts-installer'
        names = [part.strip() for part in declared.split(',')]
        if any(not PACKAGE_NAME.fullmatch(name) for name in names):
            yield f'{consumer} {version} ({arch}): invalid {REQUIRES}: {declared!r}'
            continue

        targets = native_arches if arch == 'all' else [arch]
        if arch == 'amd64' and 'amd64v3' in native_arches and (consumer, 'amd64v3') not in records:
            targets = ['amd64', 'amd64v3']
        for target in targets:
            for name in names:
                identity = f'{consumer} {version} ({target}) requires {name}'
                available = provider(records, name, target, compare)
                if available is None:
                    yield f'{identity}, which is absent from the selected round'
                    continue
                supplied_version, supplied_fields = available
                try:
                    if declaration(supplied_fields) is None:
                        raise ValueError('the size and source declaration is missing')
                except ValueError as error:
                    yield f'{identity} {supplied_version}: {error}'
