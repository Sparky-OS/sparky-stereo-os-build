set -e
cd /work/src/qt6-base-6.11.2+dfsg
export QUILT_PATCHES=debian/patches QUILT_PC=.pc
quilt pop -q   # drops stereo3d-wayland-no-csd-stereo-window from the applied stack
quilt delete -r stereo3d-wayland-no-csd-stereo-window.patch
git_patch=/work/eye-slots.patch
# the lane's patch format: strip the mail header, keep description and diff
cp $git_patch debian/patches/stereo3d-wayland-egl-eye-slots.patch
quilt import -P stereo3d-wayland-egl-eye-slots.patch debian/patches/stereo3d-wayland-egl-eye-slots.patch 2>&1 | tail -1 || true
