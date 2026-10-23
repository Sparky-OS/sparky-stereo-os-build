#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Writes the linux-headers package's postinst for a kernel release (argument 1) to standard output.
# Debian's own linux-headers packages run the header_postinst.d hooks when they are configured, through
# linux-base's linux-run-hooks (linux-headers-7.2.11+deb14-amd64: "linux-run-hooks headers postinst
# $version -- "$@""); the upstream deb-pkg gives maintainer scripts only to the image package. So when the
# headers are installed after the image, the image's postinst.d/dkms hook found no headers and nothing ran
# later: DKMS modules were never built for our kernel (queue item 139, the A10). Since build 11 (ORDER 222)
# the script is Debian's own, with linux-base (>= 4.17~) as a dependency of the headers package.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <kernel release>" >&2; exit 2; }
cat <<EOS
#!/bin/sh

set -e

version=$1

linux-run-hooks headers postinst \$version -- "\$@"

exit 0
EOS
