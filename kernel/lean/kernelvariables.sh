#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# kernelvariables.sh RELEASE CC_VERSION_TEXT: the .kernelvariables file of the headers package, Debian's
# (linux-headers-7.2.12+deb14-amd64 ships the same lines), read by the Makefile through series group 40 (Debian's
# kernelvariables.patch). External modules then build with the kernel's own compiler, x86_64-linux-gnu-gcc-N, which
# gcc-N-for-host provides, so DKMS no longer needs a plain gcc command; the exact compiler-version comparison is
# skipped as Debian skips it (makefile-make-compiler-version-comparison-optional.patch), since our kernel itself is
# built by gcc and the version texts differ in their first word only.
set -euo pipefail
release=${1:?usage: kernelvariables.sh RELEASE CC_VERSION_TEXT}
text=${2:?usage: kernelvariables.sh RELEASE CC_VERSION_TEXT}
if [[ ! "$text" =~ ^gcc\ \(.*\)\ ([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
	echo "Unsupported CONFIG_CC_VERSION_TEXT: $text" >&2
	exit 1
fi
cat <<KV
override ARCH = x86
override KERNELRELEASE = $release
CCACHE = ccache
CC = \$(if \$(DEBIAN_KERNEL_USE_CCACHE),\$(CCACHE)) \$(CROSS_COMPILE)gcc-${BASH_REMATCH[1]}
DEB_BUILD_ARCH ?= \$(shell dpkg --print-architecture)
override CROSS_COMPILE = x86_64-linux-gnu-
DEBIAN_KERNEL_NO_CC_VERSION_CHECK = y
KV
