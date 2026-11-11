cd /work/src/qt6-base-6.11.2+dfsg
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch --date "$SOURCE_DATE_RFC2822" -v 6.11.2+dfsg-5+stereo3d3 -D unstable --force-distribution "Sparky Stereo OS: a translucent window keeps the depth it asks for. New patch stereo3d-translucent-keeps-requested-depth: QWidget gave every Qt::WA_TranslucentBackground top-level an 8-bit alpha buffer, the Wayland EGL window and context added 8 bits of alpha again, and the EGL chooser wanted exactly that alpha, so a window asking for 10/10/10/2 or 16/16/16/16 got 8/8/8/8 or lost its alpha. For a format asking for more than 8 bits per channel the alpha it asks for is kept (any alpha when it asks for none), and the chooser takes the config with the same colour sizes and the nearest deeper alpha. Windows that ask for 8 bits or less behave as before."
head -6 debian/changelog
