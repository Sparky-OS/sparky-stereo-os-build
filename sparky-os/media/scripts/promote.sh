#!/bin/bash
# Step 4: our dmo-based FFmpeg and mpv go into the repository with their sources, the Debian-based builds move to repo-superseded, then make-repo.sh.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
W=${SPARKY_WORKSPACES:?}/media-on-dmo/work
R=${SPARKY_REPO_DIR:?}
S=${SPARKY_REPO_SUPERSEDED:?}
OLD='^(ffmpeg|ffplay|libavcodec63|libavcodec-dev|libavcodec-extra63|libavcodec-extra|libavdevice63|libavdevice-dev|libavfilter12|libavfilter-dev|libavfilter-extra12|libavfilter-extra|libavformat63|libavformat-dev|libavformat-extra63|libavformat-extra|libavutil61|libavutil-dev|libswresample7|libswresample-dev|libswscale10|libswscale-dev|mpv|libmpv2|libmpv-dev)_[^_]*(\+stereo3d[0-9]+)_(amd64|i386)\.deb$'
n=0
for f in $(ls $R | grep -E "$OLD" | grep -v 'dmo'); do mv "$R/$f" "$S/$f"; n=$((n+1)); done
echo "debs moved to repo-superseded: $n"
n=0
for f in $R/source/ffmpeg_9.0.2-1+stereo3d2* $R/source/ffmpeg_9.0.2.orig.tar.xz $R/source/mpv_0.41.0+git20260929.3186d369f9*; do mv "$f" "$S/$(basename $f)"; n=$((n+1)); done
echo "source files moved to repo-superseded: $n"
n=0
for f in $(cat $W/results/new-debs.list); do cp "$W/stage-repo/$f" "$R/$f"; n=$((n+1)); done
echo "debs copied into the repository: $n"
n=0
for f in $W/out/source/*; do cp "$f" "$R/source/$(basename $f)"; n=$((n+1)); done
echo "source files copied: $n"
