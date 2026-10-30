#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# run-on-hardware.sh STEP [CARD CONNECTOR]: the hardware run of ORDER 257 milestone 5, one step at a time, each
# only when Daniel says go. Every step writes its output to ./fs-STEP-<date>.txt as well.
#
#   check  CARD CONNECTOR  read-only, in the normal desktop session (sudo for debugfs): the connector's status,
#                          its stereo_state file and Stereo KWin's frame-sequential probe lines. Changes nothing.
#   probe  CARD CONNECTOR  from a text console with no compositor on CARD (see the report for the boot): lists
#                          the connectors, TEST_ONLY of the frame-sequential mode, then the CRC runs of fs-probe.
#                          Sets modes on CONNECTOR only; the console restores its own mode when it exits.
#   refuse CARD CONNECTOR  from a text console: list and TEST_ONLY only, for connectors that must refuse
#                          (the A10's HDMI-A-1 and eDP-1, the station's DP-1 through the DP++ adaptor).
#
# Needs the kernel of the series (build 14 or later, group 39) booted; fs-probe next to this script.
set -u
STEP=${1:?check, probe or refuse}; CARD=${2:-0}; CONN=${3:-DP-1}
HERE=$(dirname "$(readlink -f "$0")")
OUT=./fs-$STEP-$(date +%Y%m%d-%H%M%S).txt
exec > >(tee "$OUT") 2>&1
echo "== $(date -u +%FT%TZ) $(uname -r) step=$STEP card=$CARD connector=$CONN"
case "$STEP" in
check)
	echo "== status"; cat "/sys/class/drm/card$CARD-$CONN/status"
	echo "== driver"; sudo cat "/sys/kernel/debug/dri/$CARD/name"
	echo "== stereo_state"; sudo cat "/sys/kernel/debug/dri/$CARD/$CONN/stereo_state"
	echo "== Stereo KWin's probe"; journalctl --user -b --no-pager | grep -i 'frame sequential' | tail -20
	;;
probe)
	sudo "$HERE/fs-probe" list "$CARD"
	sudo "$HERE/fs-probe" test "$CARD" "$CONN" || { echo "== refused: stopping before the CRC runs"; exit 1; }
	sudo "$HERE/fs-probe" run "$CARD" "$CONN"
	;;
refuse)
	sudo "$HERE/fs-probe" list "$CARD"
	sudo "$HERE/fs-probe" test "$CARD" "$CONN"
	echo "== exit $? (1 = refused, as expected here)"
	;;
*)
	echo "unknown step $STEP"; exit 2
	;;
esac
echo "== output in $OUT"
