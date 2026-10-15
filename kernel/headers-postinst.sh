#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Writes the linux-headers package's postinst for a kernel release (argument 1) to standard output.
# Debian's own linux-headers packages run the header_postinst.d hooks when they are configured
# (linux-run-hooks headers postinst); the upstream deb-pkg gives maintainer scripts only to the image
# package. So when the headers are installed after the image, the image's postinst.d/dkms hook found no
# headers and nothing ran later: DKMS modules were never built for our kernel (queue item 139, the A10).
# The script is shaped like the image's own postinst from scripts/package/builddeb.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <kernel release>" >&2; exit 2; }
cat <<EOS
#!/bin/sh

set -e

# Pass maintainer script parameters to hook scripts
export DEB_MAINT_PARAMS="\$*"

# run-parts will error out if one of its directory arguments does not
# exist, so filter the list of hook directories accordingly.
hookdirs=
for dir in /etc/kernel /usr/share/kernel; do
test -d "\$dir/header_postinst.d" || continue
hookdirs="\$hookdirs \$dir/header_postinst.d"
done
hookdirs="\${hookdirs# }"
test -n "\$hookdirs" && run-parts --arg="$1" \$hookdirs
exit 0
EOS
