#!/bin/sh
# as-rig.sh COMMAND...: in a lab audio image, as root: make the runtime folder, then run COMMAND in the rig's private
# PipeWire and WirePlumber session as the unprivileged user rig (uid 1001).
mkdir -p /run/user/1001 /run/sa631 && chown 1001:1001 /run/user/1001 && chmod 700 /run/user/1001 && chmod 1777 /run/sa631
exec setpriv --reuid 1001 --regid 1001 --clear-groups env HOME=/home/rig bash /opt/lab/rig/session.sh "$@"
