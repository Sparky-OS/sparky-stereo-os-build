#!/bin/bash
set -euo pipefail
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.directory
export GIT_CONFIG_VALUE_0="${GIT_CONFIG_VALUE_0:?Set the safe directory path}"
export OUT=${OUT:?Set OUT}
export SKILLS_SRC=${SKILLS_SRC:?Set SKILLS_SRC}
export SKILLS_COMMIT=${SKILLS_COMMIT:?Set SKILLS_COMMIT}
export DEBEMAIL=${DEBEMAIL:?Set DEBEMAIL}
export DEBFULLNAME=${DEBFULLNAME:?Set DEBFULLNAME}
exec bash "$(dirname "$0")/build.sh"
