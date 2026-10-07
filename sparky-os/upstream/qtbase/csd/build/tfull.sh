cd /work/tbuild
ninja -j4 > /work/tfull.log 2>&1
echo "rc=$?" >> /work/tfull.log
