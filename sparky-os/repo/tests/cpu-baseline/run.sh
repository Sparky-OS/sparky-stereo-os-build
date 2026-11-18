#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# repo/cpu-baseline.py on programs built here (ORDER 108 milestone 8): C as before, and Go.
#   C   green: gcc -march=x86-64; red: gcc -march=x86-64-v3 (the old behaviour, unchanged: the listing of instructions)
#   Go  green: GOAMD64=v1 (the default) of a program that uses math, bits and sha256; OpenLinkHub when OPENLINKHUB_BIN is set
#       red:   the same program built with GOAMD64=v3; and a GOAMD64=v1 program whose own assembly uses AVX2 unguarded
# Needs gcc, go and objdump; exit 0 when every case behaves as named. Usage: run.sh [WORKDIR]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HERE/../../cpu-baseline.py
W=${1:-$(mktemp -d)}
mkdir -p "$W" && cd "$W"
failed=0
expect() { # NAME WANT_EXIT FILE
	out=$(python3 -I "$TOOL" "$3" 2>&1); rc=$?
	if [ "$rc" = "$2" ]; then echo "PASS $1 (exit $rc): $(echo "$out" | head -1 | cut -c1-150)"; else echo "FAIL $1: exit $rc, wanted $2"; echo "$out" | head -5; failed=1; fi
}
cat >c.c <<'EOC'
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) { unsigned n = (unsigned)argc, s = 0; for (unsigned i = 0; i < 1000; i++) s += __builtin_popcount(i * n); double d = 0; for (int i = 0; i < 100; i++) d += (double)(i * argc) * 1.5; printf("%u %f\n", s, d); return 0; }
EOC
gcc -O2 -march=x86-64 -o c-base c.c && expect "C at the baseline" 0 c-base
gcc -O2 -march=x86-64-v3 -o c-v3 c.c && expect "C built for x86-64-v3" 1 c-v3
mkdir -p g && cd g
cat >go.mod <<'EOG'
module fixture

go 1.21
EOG
cat >main.go <<'EOG'
package main

import (
	"crypto/sha256"
	"fmt"
	"math"
	"math/bits"
	"os"
)

func work(x []float64, y []uint64) (float64, int) {
	s := 0.0
	for _, v := range x {
		s += math.Floor(v*1.5) + math.FMA(v, 2, 1)
	}
	n := 0
	for _, v := range y {
		n += bits.OnesCount64(v) + bits.TrailingZeros64(v|1)
	}
	return s, n
}

func main() {
	x := make([]float64, 64+len(os.Args))
	y := make([]uint64, 64+len(os.Args))
	for i := range x {
		x[i] = float64(i) * 0.7
		y[i] = uint64(i) * 0x9e3779b97f4a7c15
	}
	s, n := work(x, y)
	fmt.Printf("%f %d %x\n", s, n, sha256.Sum256([]byte(os.Args[0])))
}
EOG
for level in v1 v3; do GOAMD64=$level GOFLAGS=-mod=mod CGO_ENABLED=0 go build -trimpath -buildvcs=false -o ../go-$level . || failed=1; done
mkdir -p ../asm && cp go.mod ../asm/ && cp main.go ../asm/main.go
cat >../asm/avx.s <<'EOA'
#include "textflag.h"
TEXT ·avx2xor(SB), NOSPLIT, $0-0
	VPXOR Y0, Y0, Y0
	VZEROUPPER
	RET
EOA
cat >>../asm/main.go <<'EOG'

func avx2xor()

func init() {
	if len(os.Args) > 99 {
		avx2xor()
	}
}
EOG
(cd ../asm && GOAMD64=v1 GOFLAGS=-mod=mod CGO_ENABLED=0 go build -trimpath -buildvcs=false -o ../go-asm . ) || failed=1
cd ..
expect "Go, GOAMD64=v1 (guarded forms and library dispatch only)" 0 go-v1
expect "Go built with GOAMD64=v3" 1 go-v3
expect "Go at v1 whose own assembly uses AVX2 unguarded" 1 go-asm
if [ -n "${OPENLINKHUB_BIN:-}" ]; then expect "OpenLinkHub" 0 "$OPENLINKHUB_BIN"; fi
exit $failed
