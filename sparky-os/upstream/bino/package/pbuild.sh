set -e
export HOME=/p DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Campos Ramos"
cd /p/bino-2.8
dch -v 2.8-1+stereo3d1 -D unstable --force-distribution "Update to upstream 2.8 (release tarball, signature checked)." "Fix the eye order of right-first stereo videos (the ffprobe inverted flag is a number)." "Always use OpenGL stereo output in the GUI (the edition draws every output through KWin), settings in ~/.config/Bino3D-stereo." "Desktop entry runs Bino on X11 until its stereo output works on Wayland." "Depend on ffmpeg (ffprobe) and libxcb-cursor0."
DEB_BUILD_OPTIONS="parallel=4" dpkg-buildpackage -us -uc -b > /p/build.log 2>&1; echo build=$?; tail -5 /p/build.log
