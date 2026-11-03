# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
"""Read-only correspondence checks shared by dpkg's verifier and dpkg-stereo."""

import hashlib

from . import project


def projection_matches(path, original, current, package):
    """Choose the reader from the original and path; compare the resulting bytes exactly."""
    try:
        result = project.project(path, original, package.split(':')[0], check=False)
    except Exception as error:
        return 'render-refused', f'{type(error).__name__}: {error}'
    if result.status != 'projected':
        return 'render-refused', result.reason
    if result.lean != current:
        return 'projection-mismatch', 'the current renderer does not reproduce the installed bytes'
    return 'ok', ''


def validate(path, original, current, package, md5_original, sha_original, sha_lean):
    """Recheck the native caller's digests, including reads racing with the first checks."""
    if (hashlib.md5(original).hexdigest() != md5_original
            or hashlib.sha256(original).hexdigest() != sha_original):
        return 'original-mismatch', 'the pristine bytes do not match the owning package and record'
    if hashlib.sha256(current).hexdigest() != sha_lean:
        return 'current-mismatch', 'the installed bytes no longer match the recorded projection'
    return projection_matches(path, original, current, package)
