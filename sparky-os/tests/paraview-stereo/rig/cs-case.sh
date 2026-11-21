#!/bin/bash
# Inside a session: the colour-size reproducer (a mono QVTKOpenGLNativeWidget, 60 frames), with the shim over VTK's
# GetColorBufferSizes when SHIM is probe or fix (LD_PRELOAD); its output, stderr and exit status in $OUT.
if [ -n "${SHIM:-}" ]; then export LD_PRELOAD=/rig/libcolour-size-shim.so COLOUR_SIZE_SHIM=$SHIM; fi
/rig/vtk-native-colour-size > $OUT/cs.out 2> $OUT/cs.err; echo "rc=$?" > $OUT/rc.txt
