#!/bin/sh
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Write data/71-sparky-stereo-headset.rules from the list of headsets of the headsetcontrol program (its own `-u`), one line per headset:
# the same devices that program gives to the person (uaccess, 70-headsets.rules) start the user service that applies the saved choices.
# Usage: tools/make-rules.sh HEADSETCONTROL OUTPUT
set -eu
"$1" -u 2>/dev/null | awk '
BEGIN { print "# Start the headset service of the person at the seat when a headset that HeadsetControl supports appears.\n# Written by tools/make-rules.sh from `headsetcontrol -u` (the program carries the list); do not edit by hand.\nACTION!=\"add\", GOTO=\"sparky_headset_end\"\nSUBSYSTEM!=\"hidraw\", GOTO=\"sparky_headset_end\"\n" }
/^# / { name = substr($0, 3); next }
/idVendor/ { sub(/TAG\+="uaccess"/, "TAG+=\"systemd\", ENV{SYSTEMD_USER_WANTS}+=\"sparky-stereo-headset.service\""); print "# " name; print; print "" }
END { print "LABEL=\"sparky_headset_end\"" }' >"$2"
