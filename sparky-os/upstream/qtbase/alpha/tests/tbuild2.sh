cd /work/tbuild
T=$(tr ' ' '\n' < /work/ttargets.txt | grep -E '^tst_[a-z0-9_]+$' | grep -v -E '_(autogen|check|autogen_timestamp_deps)$' | tr '\n' ' ')
ninja -j4 $T tst_client_fullscreenshellv1 tst_qwidget tst_qopenglwidget > /work/tbuild2.log 2>&1
echo "rc=$?" >> /work/tbuild2.log
