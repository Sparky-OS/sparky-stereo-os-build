cd /work/src/qt6-base-6.11.2+dfsg
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 6.11.2+dfsg-5+stereo3d1 -D unstable --force-distribution "Sparky Stereo OS: stereo for Qt programs on Wayland. QSurfaceFormat::StereoBuffers had no effect there, so QOpenGLWidget never rendered its right buffer. Two patches for the Wayland client: stereo-wayland-egl-two-views creates the EGL window surface with two views (EGL_EXT_multiview_window) and reports stereo in the window and context formats; stereo-wayland-no-csd-stereo-window draws no client side decorations around a stereo OpenGL window (they render the content into a mono FBO)."
head -10 debian/changelog
