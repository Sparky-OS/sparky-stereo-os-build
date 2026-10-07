set -e
for v in orig fixed; do
  cmake -S /src/$v -B /o/b-$v -G Ninja -DCMAKE_BUILD_TYPE=Release > /o/b-$v.cmake.log 2>&1
  cmake --build /o/b-$v -j4 > /o/b-$v.build.log 2>&1 && echo "$v built"; ls -la /o/b-$v/bino
done
