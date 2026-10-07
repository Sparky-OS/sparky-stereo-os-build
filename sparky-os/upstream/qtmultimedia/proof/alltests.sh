#!/bin/bash
# usage: alltests.sh <tree name> : runs the video tests of /w/b-<tree> (inside the KWin container), one file per test in /w/out/tests-<tree>
t=$1; B=/w/b-$t; O=/w/out/tests-$t; mkdir -p $O
export QT_QPA_PLATFORM=wayland QT_PLUGIN_PATH=$B/lib/x86_64-linux-gnu/qt6/plugins LD_LIBRARY_PATH=$B/lib/x86_64-linux-gnu QML_IMPORT_PATH=$B/lib/x86_64-linux-gnu/qt6/qml
cd $B
for bin in $(ls tests/auto/unit/multimedia/qvideoframeformat/tst_qvideoframeformat tests/auto/unit/multimedia/qvideoframe/tst_qvideoframe tests/auto/unit/multimedia/qvideotexturehelper/tst_qvideotexturehelper tests/auto/unit/multimedia/qvideoframecolormanagement/tst_qvideoframecolormanagement tests/auto/unit/multimedia/qvideobuffers/tst_qvideobuffers tests/auto/unit/multimedia/qabstractvideobuffer/tst_qabstractvideobuffer tests/auto/unit/multimedia/qvideotransformation/tst_qvideotransformation tests/auto/integration/qquickvideooutput/tst_qquickvideooutput tests/auto/integration/qquickvideooutput_window/tst_qquickvideooutput_window tests/auto/integration/qvideoframebackend/tst_qvideoframebackend tests/auto/integration/qquickvideostereo/tst_qquickvideostereo 2>/dev/null); do
  n=$(basename $bin)
  ( cd $(dirname $bin); timeout 900 ./$n > $O/$n.txt 2>&1; echo "exit $?" >> $O/$n.txt )
done
echo finished > $O/done
