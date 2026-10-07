cd /work/src/qt6-base-6.11.2+dfsg
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v 6.11.2+dfsg-5+stereo3d2 -D unstable --force-distribution "Sparky Stereo OS: Qt's own client side decorations around a stereo window keep both eyes. stereo-wayland-no-csd-stereo-window is dropped. New patch stereo-wayland-egl-eye-slots: the content framebuffer of a decorated stereo window gets a color attachment per eye, QRhiGles2 draws the right eye of the default framebuffer into the second one, and the decorations blit (from a desktop OpenGL context) copies each slot into its own back buffer with the decoration drawn identically in both."
head -12 debian/changelog
