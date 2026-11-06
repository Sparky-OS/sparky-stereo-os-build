cd /work/src/qt6-base-6.11.2+dfsg
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -S -d -us -uc -sa > /work/srcbuild.log 2>&1; echo rc=$? >> /work/srcbuild.log
tail -5 /work/srcbuild.log
