# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""The docker run arguments that carry the host's build facts into a container (ORDER 412).

The Python build drivers cannot source build-provenance.sh, so this runs its sparky_provenance_init in bash and returns
"${SPARKY_PROV_ARGS[@]}" for the docker run command: `command = ['docker', 'run', '--rm', *provenance_args(IMAGE), ...]`.
A fact that cannot be read is said on stderr by the shell function and left out, exactly as in the shell recipes;
SPARKY_PROVENANCE_REQUIRED=1 stops the driver. Without these arguments lean.release check-debs stops the build
(lean/buildrecord.py), so a driver that forgets them fails loudly instead of writing an incomplete record.
"""
import inspect
from pathlib import Path
import subprocess

SCRIPT = Path(__file__).resolve().parents[1] / 'repo' / 'build-provenance.sh'


def provenance_args(image, recipe=None):
    """recipe: the folder whose last commit dates the sources (ORDER 421b); the calling driver's folder when not given.
    SOURCE_DATE_EPOCH in the environment wins, as in the shell function."""
    recipe = Path(recipe) if recipe else Path(inspect.stack()[1].filename).resolve().parent
    done = subprocess.run(['bash', '-c', '. "$1" && sparky_provenance_init "$2" "$3" && printf "%s\\0" "${SPARKY_PROV_ARGS[@]}"',
                           'provenance', str(SCRIPT), image, str(recipe)], stdout=subprocess.PIPE)
    if done.returncode:
        raise SystemExit(f'sparky_provenance_init {image} stopped (no source date for {recipe}, SPARKY_PROVENANCE_REQUIRED=1 or an unreadable script): no build starts without it')
    return [part.decode() for part in done.stdout.split(b'\0') if part]
