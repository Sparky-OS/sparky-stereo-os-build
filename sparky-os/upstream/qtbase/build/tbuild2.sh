cd /work/tbuild
ninja -j4 > /work/tbuild2.log 2>&1
echo "rc=$?" >> /work/tbuild2.log
