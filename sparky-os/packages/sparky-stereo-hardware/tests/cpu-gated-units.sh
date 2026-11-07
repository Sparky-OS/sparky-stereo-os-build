#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# thermald and nvidia-imex run only where they can (ORDER 43). Run in a debian:testing container, as root, with the built
# package unpacked at /t/hw, NVIDIA's nvidia-imex.service at /t/nvidia-imex.service and a cpuinfo fixture mounted over
# /proc/cpuinfo (docker run -v FIXTURE:/proc/cpuinfo:ro); WANT is "intel" or "other", the vendor the fixture says.
# Prints PASS or FAIL lines and exits 1 on any FAIL.
#   docker run --rm --ulimit core=0 -e WANT=intel -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
#     -v BUILD-CHECKOUT/tools/https-only-apt.sh:/run/https-only-apt.sh:ro -v DIR:/t:ro -v INTEL-CPUINFO:/proc/cpuinfo:ro IMAGE sh /t/cpu-gated-units.sh
set -u
sh /run/https-only-apt.sh || exit 1
export DEBIAN_FRONTEND=noninteractive
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
apt-get -qq update >/dev/null && apt-get -qq install -y --no-install-recommends thermald systemd grep >/dev/null 2>&1 || { echo "FAIL apt could not install thermald and systemd"; exit 1; }
cp /t/nvidia-imex.service /usr/lib/systemd/system/
cp -a /t/hw/usr/lib/systemd/system/thermald.service.d /t/hw/usr/lib/systemd/system/nvidia-imex.service.d /usr/lib/systemd/system/ 2>/dev/null
echo "== the CPU this container reads: $(grep -m1 '^vendor_id' /proc/cpuinfo)"
# thermald: the merged unit carries one ExecCondition, and running it gives the verdict systemd takes
cmd=$(systemd-analyze cat-config systemd/system/thermald.service 2>/dev/null | sed -n 's/^ExecCondition=//p')
if [ -n "$cmd" ]; then
	ok "thermald.service has an ExecCondition: $cmd"
	sh -c "$cmd"; rc=$?
	case $WANT:$rc in
		intel:0) ok "Intel CPU: the condition passes (exit 0), thermald starts as before" ;;
		other:1) ok "other CPU: the condition ends with exit 1, which systemd.service(5) takes as 'skip, not failed'" ;;
		*) bad "WANT=$WANT but the condition exited $rc" ;;
	esac
else
	bad "thermald.service has no ExecCondition (the package's drop-in is missing)"
fi
# nvidia-imex: skipped until the administrator's node file exists
rm -f /etc/nvidia-imex/nodes_config.cfg
if systemd-analyze condition --unit=nvidia-imex.service 2>&1 | grep -q 'ConditionPathExists=/etc/nvidia-imex/nodes_config.cfg .* failed'; then
	ok "nvidia-imex.service without /etc/nvidia-imex/nodes_config.cfg: the condition fails, the unit is skipped"
else
	bad "nvidia-imex.service without the node file is not skipped: $(systemd-analyze condition --unit=nvidia-imex.service 2>&1 | tr '\n' ' ')"
fi
mkdir -p /etc/nvidia-imex && : >/etc/nvidia-imex/nodes_config.cfg
if systemd-analyze condition --unit=nvidia-imex.service >/dev/null 2>&1; then
	ok "nvidia-imex.service with the administrator's node file: the condition succeeds, NVIDIA's daemon runs as built"
else
	bad "nvidia-imex.service with the node file still skipped"
fi
exit $failed
