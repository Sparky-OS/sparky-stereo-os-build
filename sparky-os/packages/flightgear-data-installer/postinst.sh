#!/bin/sh
# postinst script
set -e
# FlightGear's data is fetched here, as ttf-mscorefonts-installer fetches its fonts. A failure stops the
# configuration and says what failed, why and what to do: dpkg then keeps the package unconfigured, and
# `dpkg --configure flightgear-data-installer` (or flightgear-data-installer itself) tries again.
if [ "$1" = "configure" ]; then
	/usr/sbin/flightgear-data-installer install
fi
exit 0
