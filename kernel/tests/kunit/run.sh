#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# run.sh SRC BUILD_DIR KUNITCONFIG LOG : one kunit.py run on x86_64 QEMU, in the kernel build image, as the invoking user.
#   drm-stereo.kunitconfig  DRM core and helper tests (series group 34's drm_edid_hdmi_3d, hdmi_vendor_infoframe_3d,
#                           drm_modes_stereo, the HDMI state helper; group 36's drm_frame_sequential, drm_edid_stereo
#                           and the DisplayPort SDP suites) and vkms (build 10's set)
#   amdgpu-dm.kunitconfig   the AMD display core's own suites (amdgpu_dm/tests/.kunitconfig without the UML-only
#                           coverage lines), the amdgpu path a machine without an AMD GPU can run
#   nouveau.kunitconfig     nouveau's own suites (DRM_NOUVEAU_KUNIT_TEST, series group 37), built into the driver
# The shipped kernels have CONFIG_KUNIT off: these are test kernels from the same source.
# IMAGE: an image with gcc, make, flex, bison, bc, libelf, libssl and qemu-system-x86 (the EFI mixed rig image, kernel/tests/efi-mixed/docker, has them).
set -euo pipefail
SRC=$(readlink -f "$1"); B=$(mkdir -p "$2" && readlink -f "$2"); K=$(readlink -f "$3"); LOG=$(readlink -f "$4")
docker run --rm --platform linux/amd64 --cpus "${CPUS:-4}" --memory 8g --user "$(id -u):$(id -g)" -e HOME=/tmp \
	--device /dev/kvm --group-add "$(getent group kvm | cut -d: -f3)" \
	-v "$SRC":/src:ro -v "$B":/b -v "$K":/k.kunitconfig:ro -v "$(dirname "$LOG")":/out "${IMAGE:?an image with the kernel build tools and qemu-system-x86}" \
	sh -c "cd /src && python3 tools/testing/kunit/kunit.py run --arch=x86_64 --build_dir=/b --kunitconfig=/k.kunitconfig \
		--jobs=${JOBS:-4} --raw_output=kunit > /out/$(basename "$LOG") 2>&1; echo exit=\$? >> /out/$(basename "$LOG")"
tail -3 "$LOG"
