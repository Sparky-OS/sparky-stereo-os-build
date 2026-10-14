#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
ulimit -c 0
export AUDIT_FIXTURE=/build/installed-fixture.so AUDIT_CAPTURE_TOOL=/build/installed-capture GL_STEREO_SEPARATION=.5 REFERENCE_SEPARATION=.5 AUDIT_TIMEOUT=80
AUDIT_LIBRARY=/usr/lib/gl-stereo/libgl-stereo.so python3 /workspace/gl-stereo/savers/audit/run-kwin.py /build/installed-flurry flurry
for eye in left right; do
 AUDIT_LIBRARY=/build/installed-reference.so AUDIT_REFERENCE_EYE=$eye python3 /workspace/gl-stereo/savers/audit/run-kwin.py /build/installed-flurry-reference-$eye flurry
done
python3 /workspace/gl-stereo/savers/audit/mono.py /build/installed-flurry-mono /build/installed-fixture.so /usr/lib/gl-stereo/libgl-stereo.so flurry
