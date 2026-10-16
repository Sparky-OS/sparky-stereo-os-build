#!/bin/sh
# Indexes the lane's staged packages (/stage, flat) with the edition's Origin, so the edition's pins
# (o=Sparky Stereo OS at 1001) treat them like the development repository and the higher version wins.
set -eu
cd /stage
dpkg-scanpackages -m . 2>/dev/null > Packages
printf 'Origin: Sparky Stereo OS\nLabel: Sparky Stereo OS beta-iso-lutz stage\nSuite: stage\nCodename: stage\nDate: %s\n' "$(date -Ru)" > Release
grep -c '^Package:' Packages
