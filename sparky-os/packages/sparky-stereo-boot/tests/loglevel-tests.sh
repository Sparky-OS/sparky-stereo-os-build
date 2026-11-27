#!/bin/sh
set -eu

hook=$1
check() {
    actual=$(
        GRUB_CMDLINE_LINUX=$1
        GRUB_CMDLINE_LINUX_DEFAULT=$2
        SPARKY_STEREO_BOOT=${4:-yes}
        # Match a caller that inherits the previous invocation's exported value.
        [ ! -f "$hook" ] || . "$hook"
        [ ! -f "$hook" ] || . "$hook"
        printf '%s|%s' "$GRUB_CMDLINE_LINUX" "$GRUB_CMDLINE_LINUX_DEFAULT"
    )
    expected="$1|$3"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: got <%s>, expected <%s>\n' "$actual" "$expected" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$expected"
}

check '' 'quiet splash' 'quiet splash loglevel=3'
check quiet 'splash' 'splash loglevel=3'
check '' 'quiet splash loglevel=7' 'quiet splash loglevel=7'
check loglevel=7 'quiet splash' 'quiet splash'
check '' 'quiet "loglevel=7"' 'quiet "loglevel=7"'
check '' "quiet$(printf '\t')loglevel=5" "quiet$(printf '\t')loglevel=5"
check '' 'quiet debug' 'quiet debug'
check '' 'splash' 'splash'
check '' 'quiet splash' 'quiet splash' no
