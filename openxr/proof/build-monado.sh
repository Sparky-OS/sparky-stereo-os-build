#!/bin/bash
# In the container. Builds the patched Monado (service mode, the drivers the proof needs) with
# the stereo declaration, and the eyes-client test aid. SRC and BUILD come from the caller.
set -eu
SRC=${SRC:-/src/monado}
BUILD=${BUILD:-/build/monado}
OFF=""
for d in UVC ANDROID ARDUINO BLUBUR_S1 CONTACTGLOVE DAYDREAM DEPTHAI EUROC HANDTRACKING TWRAP HDK HYDRA ILLIXR NS OHMD \
         OPENGLOVES PSMV PSSENSE PSVR PSVR2 REALSENSE RIFT RIFT_SENSOR RIFT_S ROKID STEAMVR_LIGHTHOUSE SURVIVE ULV2 ULV5 \
         VF VIVE WMR XREAL_AIR SIMULAVR SOLARXR; do OFF="$OFF -DXRT_BUILD_DRIVER_$d=OFF"; done
cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DXRT_HAVE_SYSTEM_CJSON=ON -DXRT_HAVE_OPENCV=OFF -DXRT_FEATURE_DEBUG_GUI=OFF -DXRT_MODULE_MONADO_GUI=OFF \
  -DXRT_FEATURE_STEAMVR_PLUGIN=OFF -DXRT_FEATURE_LIBMONADO=OFF -DXRT_FEATURE_WINDOW_PEEK=ON -DXRT_HAVE_STEREO_DECLARE=ON \
  -DXRT_BUILD_DRIVER_SIMULATED=ON -DXRT_BUILD_DRIVER_QWERTY=ON -DXRT_BUILD_DRIVER_REMOTE=ON -DBUILD_DOC=OFF \
  -DXRT_OPENXR_INSTALL_ACTIVE_RUNTIME=OFF $OFF 2>&1 | grep -E 'STEREO_DECLARE|WINDOW_PEEK|SDL2|WAYLAND:|XCB|Configuring done|Error|error' || true
ninja -C "$BUILD" -j4 2>&1 | tail -3
gcc -O1 -o "$BUILD/eyes-client" "$(dirname "$0")/eyes-client.c" -lopenxr_loader -lvulkan
echo "built: $(ls -la $BUILD/src/xrt/targets/service/monado-service $BUILD/eyes-client | awk '{print $5, $9}')"
