#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
WORK=${1:?Usage: installed.sh NEW_SCRATCH_DIRECTORY}
test ! -e "$WORK"
mkdir -p "$WORK"
WORK=$(realpath "$WORK")
export ZIG_GLOBAL_CACHE_DIR=$WORK/global-cache ZIG_LOCAL_CACHE_DIR=$WORK/local-cache
cd "$WORK"
test "$(command -v zig)" = /usr/bin/zig
test "$(readlink -f /usr/bin/zig)" = /usr/lib/cgm-zig/bin/zig
test "$(zig version)" = 0.16.0+cgm.0399d2b19b
cat > hello.zig <<'ZIG'
const std = @import("std");
pub fn main() void {
    std.debug.print("Hello, cgm-zig!\n", .{});
}
ZIG
zig build-exe hello.zig -O ReleaseSafe -j4 -femit-bin=hello
test "$(./hello 2>&1)" = 'Hello, cgm-zig!'
cat > answer.zig <<'ZIG'
export fn answer(a: c_int, b: c_int) c_int {
    return a + b;
}
ZIG
cat > caller.c <<'C'
#include <stdio.h>
extern int answer(int, int);
int main(void) {
    int result = answer(19, 23);
    printf("%d\n", result);
    return result == 42 ? 0 : 1;
}
C
zig build-lib answer.zig -dynamic -lc -O ReleaseSafe -j4 --name answer -femit-bin=libanswer.so
cc caller.c -L. -Wl,-rpath,"$WORK" -lanswer -o caller
test "$(./caller)" = 42
printf 'PASS: packaged version, hello world and C caller of Zig library\n'
