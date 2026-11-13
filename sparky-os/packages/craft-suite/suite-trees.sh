#!/bin/bash
# trees.sh SUITE TREEDIR FEATURES BIN...: the per-program and whole-selection dependency listings suite-tree.py reads.
set -euo pipefail
suite=$1; out=$2; feats=$3; shift 3
mkdir -p "$out"; cd "$suite"
all=()
for b in "$@"; do
  all+=(-p "$b")
  f=$(tr ',' '\n' <<<"$feats" | grep "^$b/" | paste -sd, || true)
  cargo tree --offline -e normal --target x86_64-unknown-linux-gnu -p "$b" ${f:+--features "$f"} --prefix depth -f '{p}|{f}' 2>/dev/null > "$out/$b.txt"
done
cargo tree --offline -e normal --target x86_64-unknown-linux-gnu "${all[@]}" --features "$feats" --prefix depth -f '{p}|{f}' 2>/dev/null > "$out/all.txt"
wc -l "$out"/*.txt
