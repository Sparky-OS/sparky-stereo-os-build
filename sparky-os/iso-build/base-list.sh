#!/bin/sh
# Prints Sparky KDE 2026.09's package names that have an install candidate today, without library
# names (dependencies bring them), Debian's kernels (versioned and their metapackages such as
# linux-image-amd64: the edition ships only its own kernels) and the edition's removals
# (lists/base-remove.list, systemd-timesyncd among them: the edition keeps time with chrony).
set -eu
grep -v -E '^(lib[^r]|lib$|linux-image-[0-9]|linux-headers-[0-9]|linux-base-|linux-binary-|linux-modules-|linux-(image|headers|signed)-.*amd64$)' ${NAMES:-/build/sparky-kde-2026.09.names} \
	| grep -v -x -F -f ${REMOVE:-/edition-lists/base-remove.list} > /tmp/base.all
apt-cache policy $(cat /tmp/base.all) 2>/dev/null | awk '/^[^ ].*:$/{p=substr($1,1,length($1)-1)} /Candidate:/{if($2!="(none)") print p}' | sort -u
