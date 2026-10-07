cd /work/tbuild
ninja -j4 > /work/tinc.log 2>&1
echo "rc=$?" >> /work/tinc.log
