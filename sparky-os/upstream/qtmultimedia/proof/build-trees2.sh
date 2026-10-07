#!/bin/bash
cd /K3D/temp/qtmm-lane
./build-tree.sh offer 0add909 -DQT_NO_STEREO_LAYER=ON
./build-tree.sh final 883fbea
for t in offer final; do ./run/rtests.sh $t; done
echo alldone > trees-done2
