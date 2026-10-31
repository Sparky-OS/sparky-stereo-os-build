# SPDX-License-Identifier: GPL-2.0-only
"""The upstream Linux tags the edition's kernel may be built from, and the version strings each one gives.

A tag is accepted only with the commit it was verified to point to (the tag's signature checked with its signer's key
and the commit compared with git.kernel.org): Linus Torvalds's, ABAF11C65A2970B130ABE3C479BE3E4300411886, for mainline
tags, and Greg Kroah-Hartman's, 647F28654894E3BD457199BE38DBBDC86092693E, for the stable releases of the stable tree.
The rule is build-deb.sh's: v7.3-rc6 gives 7.3.0-rc6 (uname -r) and 7.3.0~rc6 (Debian), v7.3 gives 7.3.0, v7.3.1 gives 7.3.1.
"""
import re

PINNED = {
    'v7.3-rc6': 'a90ee4305c4a5df72c11b31dacfdc76e00fcf78a',  # builds 9 to 12
    'v7.3': 'c03c1a14507dfaf8b856c2608f9ac216021fc222',  # build 13 (tag object 091b06388b11, 2026-10-18)
    'v7.3.1': '79a907609d53d5cd645b42c11550d295d43abf99',  # build 14 on (stable, tag object dfc1145bbaa1, 2026-10-30)
}
CURRENT = 'v7.3.1'


def versions(tag):
    """Return (kernel version, Debian upstream version) for a pinned tag."""
    if tag not in PINNED:
        raise ValueError(f'{tag} is not a pinned upstream tag')
    match = re.fullmatch(r'v(\d+)\.(\d+)(?:\.(\d+))?(?:-(rc\d+))?', tag)
    kernel = f'{match[1]}.{match[2]}.{match[3] or 0}'
    if match[4]:
        return kernel + '-' + match[4], kernel + '~' + match[4]
    return kernel, kernel
