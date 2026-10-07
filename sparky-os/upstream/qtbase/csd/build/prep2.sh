set -e
cd /work/src/qt6-base-6.11.2+dfsg
cp /work/compositor-rebind.patch debian/patches/stereo3d-compositor-rebind-second-texture.patch
echo stereo3d-compositor-rebind-second-texture.patch >> debian/patches/series
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
python3 - <<'PY'
p='debian/changelog'
s=open(p).read()
a="    decoration drawn identically in both.\n"
assert a in s
s=s.replace(a,a+"  * New patch stereo-compositor-rebind-second-texture: a stereo QOpenGLWidget\n    resized while its window is shown (as a window decorated by Qt is at\n    start) left the right eye's shader bindings on a destroyed texture,\n    and the next flush crashed.\n",1)
open(p,'w').write(s)
PY
head -20 debian/changelog
