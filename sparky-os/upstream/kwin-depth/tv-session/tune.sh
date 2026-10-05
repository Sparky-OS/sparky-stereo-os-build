#!/bin/bash
# usage: tune.sh SUNK POPPED   (pixels at 1920 wide; 0 switches that side off). Changes the limits of the running test session.
DIR=$(cd "$(dirname "$0")" && pwd)
if [ $# -ne 2 ] || ! [[ $1 =~ ^[0-9.]+$ && $2 =~ ^[0-9.]+$ ]]; then
    echo "usage: tune.sh SUNK POPPED" >&2; exit 2
fi
[ -e "$DIR/session.env" ] || { echo "the test session is not running (no session.env)" >&2; exit 1; }
. "$DIR/session.env"
kwriteconfig6 --file kwinrc --group StereoDepth --key SunkLimit "$1"
kwriteconfig6 --file kwinrc --group StereoDepth --key PoppedLimit "$2"
qdbus6 org.kde.KWin /KWin reconfigure
echo "sunk $1, popped $2"
