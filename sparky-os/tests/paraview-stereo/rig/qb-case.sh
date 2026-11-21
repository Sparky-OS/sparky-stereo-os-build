#!/bin/bash
# Inside a session: the VTK reproducer (a QVTKOpenGLStereoWidget in Crystal Eyes, 60 frames), its output and exit status
# in $OUT, the declarations and a capture while it draws.
( WAYLAND_DEBUG=client /rig/vtk-quad-buffer-blit > $OUT/qb.out 2> >(grep -v '^\[' > $OUT/qb.err); echo "rc=$?" > $OUT/rc.txt ) 2>&1 | grep -E --line-buffered "kde_stereo_content|set_content" > $OUT/wl.txt &
sleep 1.2
python3 /rig/capture.py $OUT/shot1.png > $OUT/shot1.json 2>&1
python3 /rig/x11_props.py > $OUT/props.json 2>&1
wait
