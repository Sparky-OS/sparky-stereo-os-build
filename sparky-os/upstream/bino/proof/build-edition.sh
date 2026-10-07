set -e
cmake -S /src/ed -B /o/b-ed -G Ninja -DCMAKE_BUILD_TYPE=Release > /o/b-ed.cmake.log 2>&1
cmake --build /o/b-ed -j4 > /o/b-ed.build.log 2>&1 && echo built; ls -la /o/b-ed/bino
