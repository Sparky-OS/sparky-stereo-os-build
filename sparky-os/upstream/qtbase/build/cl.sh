cd /work/src/qt6-base-6.11.2+dfsg
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch --date "$SOURCE_DATE_RFC2822" -v 6.11.2+dfsg-5+stereo3d1 -D unstable --force-distribution "Sparky Stereo OS: stereo for Qt programs on Wayland. QSurfaceFormat::StereoBuffers had no effect there, so QOpenGLWidget never rendered its right buffer. Two patches for the Wayland client: stereo-wayland-egl-two-views creates the EGL window surface with two views (EGL_EXT_multiview_window) and reports stereo in the window and context formats; stereo-wayland-no-csd-stereo-window draws no client side decorations around a stereo OpenGL window (they render the content into a mono FBO)."
head -10 debian/changelog
