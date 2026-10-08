set -e
FLAGS=$(cat /qtgl/debflags.txt | tr '\n' ' ')
cmake -S /qtgl/src -B /qtgl/build-deb -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_LIBRARY_PATH=x86_64-linux-gnu -DQT_BUILD_EXAMPLES=OFF -DQT_BUILD_TESTS=OFF -DFEATURE_sql_ibase=OFF -DFEATURE_sctp=ON $FLAGS > /qtgl/confdeb.log 2>&1 || { tail -30 /qtgl/confdeb.log; exit 1; }
cd /qtgl/build-deb
ninja -j4 > /qtgl/builddeb.log 2>&1
echo "rc=$?" >> /qtgl/builddeb.log
