#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]] || { echo "Run in Docker only"; exit 1; }
exec >evidence/build.log 2>&1
export OUT=$PWD/out
P=$PWD/sparky-stereo-os-build/sparky-os/packages
for package in firmware-creative-stereo xpadneo-dkms sparky-stereo-hardware; do
 bash "$P/$package/build.sh"
done
bash -n "$P/sparky-stereo-hardware/bin/sparky-stereo-hardware" "$P/sparky-stereo-hardware/lib/actions.sh"
shellcheck -x -S warning "$P/sparky-stereo-hardware/bin/sparky-stereo-hardware" "$P/sparky-stereo-hardware/lib/actions.sh"
printf 'BUILD COMPLETE\n'
