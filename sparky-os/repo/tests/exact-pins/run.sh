#!/bin/bash
# check-exact-pins.py (row 944) on small fixture indexes: the codec pinned to PipeWire 1.6.9-2 against a testing that moved
# to 1.6.11-2 is a FAIL (red); its successor pinned to 1.6.11-2 passes, with a WARN when unstable already has 1.6.12-1;
# a pin satisfied by a versioned Provides passes; a pin on a package no index has is a NOTE; a pin on an edition package
# is judged against the edition's own records. Plain Python on the host, no network.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
check=${CHECK:-$here/../../check-exact-pins.py}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0
pkg() { printf 'Package: %s\nVersion: %s\nArchitecture: %s\n%s\n\n' "$@"; }
{ pkg pipewire-bluez5-codec-aac 1.6.9-2+aac2+lc1 amd64 'Depends: libspa-0.2-bluetooth (= 1.6.9-2), libc6 (>= 2.38)'
  pkg nvidia-kernel-open-dkms-stereo3d 615.71.09-2+stereo3d1 amd64 'Depends: nvidia-modprobe (= 615.71.09-2)'
  pkg sparky-stereo-graphics 0.2.13 all 'Depends: qt6-base-private-abi (= 6.11.2), python3'
  pkg libqt6core6t64 6.11.2+dfsg-5+stereo3d23+lc1 amd64 'Provides: qt6-base-private-abi (= 6.11.2)'
  pkg libfoo 1.0-1 amd64 'Depends: libbar (= 2.0-1) | libbaz (= 3.0-1)'
} >"$work/published"
pkg pipewire-bluez5-codec-aac 1.6.11-2+aac2+lc1 amd64 'Depends: libspa-0.2-bluetooth (= 1.6.11-2), libc6 (>= 2.38)' >"$work/pool"
{ pkg libspa-0.2-bluetooth 1.6.11-2 amd64 ''; pkg libbaz 3.0-1 amd64 ''; } >"$work/testing"
{ pkg libspa-0.2-bluetooth 1.6.12-1 amd64 ''; pkg libbaz 3.0-1 amd64 ''; } >"$work/unstable"
gzip -k "$work/testing"
expect() { # $1 name, $2 expected exit, $3 grep pattern that must appear (or !pattern that must not), rest: arguments
	local name=$1 want=$2 pattern=$3 rc=0
	shift 3
	python3 -I "$check" "$@" >"$work/out" 2>&1 || rc=$?
	if [ "$rc" != "$want" ]; then echo "FAIL $name: exit $rc, expected $want"; cat "$work/out"; failures=$((failures + 1)); return; fi
	if [[ $pattern == !* ]]; then
		! grep -q -- "${pattern#!}" "$work/out" || { echo "FAIL $name: found ${pattern#!}"; cat "$work/out"; failures=$((failures + 1)); return; }
	else
		grep -q -- "$pattern" "$work/out" || { echo "FAIL $name: missing $pattern"; cat "$work/out"; failures=$((failures + 1)); return; }
	fi
	echo "ok   $name"
}
expect 'published codec against a moved testing' 1 'FAIL testing pipewire-bluez5-codec-aac 1.6.9-2+aac2+lc1 (amd64) Depends libspa-0.2-bluetooth (= 1.6.9-2); testing has libspa-0.2-bluetooth 1.6.11-2' \
	--edition "$work/published" --debian "testing=$work/testing"
expect 'successor in the pool passes testing' 0 '!FAIL testing' --edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing.gz"
expect 'unstable already moved: a warning' 0 'WARN unstable pipewire-bluez5-codec-aac 1.6.11-2+aac2+lc1 (amd64) Depends libspa-0.2-bluetooth (= 1.6.11-2); unstable has libspa-0.2-bluetooth 1.6.12-1' \
	--edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing" --debian "unstable=$work/unstable"
expect 'the warning fails with --fail-on-warn' 1 'WARN unstable' --fail-on-warn \
	--edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing" --debian "unstable=$work/unstable"
expect 'an edition pin met by a versioned Provides' 0 '!sparky-stereo-graphics' --edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing"
expect 'a pin outside every index is a note' 0 'NOTE nvidia-kernel-open-dkms-stereo3d' --edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing"
expect 'an alternative that testing has satisfies the group' 0 '!libfoo' --edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing"
pkg nvidia-modprobe 550.163.01-1 amd64 '' >>"$work/testing"
expect 'a pin Debian has at another version, another repository not given' 1 'FAIL testing nvidia-kernel-open-dkms-stereo3d' \
	--edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing"
pkg nvidia-modprobe 615.71.09-2 amd64 '' >"$work/cuda"
expect 'the same pin met by another repository the edition reads' 0 '!nvidia-kernel-open-dkms-stereo3d' \
	--edition "$work/published" --edition "$work/pool" --debian "testing=$work/testing" --also "nvidia-cuda=$work/cuda"
pkg libqt6core6t64 6.12.0+dfsg-1+stereo3d1+lc1 amd64 'Provides: qt6-base-private-abi (= 6.12.0)' >"$work/qt"
expect 'an edition pin the edition no longer meets' 1 'FAIL edition sparky-stereo-graphics 0.2.13 (all) Depends qt6-base-private-abi (= 6.11.2)' \
	--edition "$work/published" --edition "$work/pool" --edition "$work/qt" --debian "testing=$work/testing"
echo "exact-pins: $failures failing"
[ "$failures" = 0 ]
