# SPDX-License-Identifier: GPL-2.0-only
"""The upstream Linux tags the edition's kernel may be built from, and the version strings each one gives.

A tag is accepted only with the commit it was verified to point to (the tag's signature checked with Linus
Torvalds's key, ABAF11C65A2970B130ABE3C479BE3E4300411886, and the commit compared with git.kernel.org).
The rule is build-deb.sh's: v7.3-rc6 gives 7.3.0-rc6 (uname -r) and 7.3.0~rc6 (Debian), v7.3 gives 7.3.0.
"""
import re

PINNED = {
    'v7.3-rc6': 'a90ee4305c4a5df72c11b31dacfdc76e00fcf78a',  # builds 9 to 12
    'v7.3': 'c03c1a14507dfaf8b856c2608f9ac216021fc222',  # build 13 on (tag object 091b06388b11, 2026-10-18)
}
CURRENT = 'v7.3'


def versions(tag):
    """Return (kernel version, Debian upstream version) for a pinned tag."""
    if tag not in PINNED:
        raise ValueError(f'{tag} is not a pinned upstream tag')
    match = re.fullmatch(r'v(\d+)\.(\d+)(?:\.(\d+))?(?:-(rc\d+))?', tag)
    kernel = f'{match[1]}.{match[2]}.{match[3] or 0}'
    if match[4]:
        return kernel + '-' + match[4], kernel + '~' + match[4]
    return kernel, kernel
