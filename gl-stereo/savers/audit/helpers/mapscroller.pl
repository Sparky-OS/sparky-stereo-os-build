#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# The audit's producers find this before XScreenSaver's own Mapscroller helper: it runs that
# helper verbosely, so a tile it serves from the cache logs "cached:" and a tile it would
# download logs "downloading", which fails the audit's tiles step.
exec /usr/libexec/xscreensaver/mapscroller.pl -vv "$@"
