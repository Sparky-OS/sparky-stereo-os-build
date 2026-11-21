#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Every program and ggml back end of the named packages resolves every library it needs (ldd), so a runner the engine opens can load.
# Usage: runners-link.sh PACKAGE...   Exit 0 when nothing is "not found".
set -u
fail=0
for pkg in "$@"; do
	n=0
	while IFS= read -r f; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		file -b "$f" | grep -q 'ELF 64-bit LSB' || continue
		# what the engine starts or opens: its programs and the ggml back ends; their libraries load through them, breadth
		# first, so a library whose own RUNPATH lacks $ORIGIN (upstream's hipBLASLt and rocRoller) finds HIP and comgr loaded
		case $(basename "$f") in ollama|llama-server|llama-quantize|libggml-*.so|libggml-*.so.*) ;; *) continue ;; esac
		n=$((n + 1))
		# a back end in a subfolder (vulkan/, cuda_v13/, rocm_v7_2/) is opened by the engine after it loaded libggml-base.so.0
		# from /usr/lib/ollama, so that folder is on the search path here, as the loaded base is in the engine
		missing=$(LD_LIBRARY_PATH=/usr/lib/ollama ldd "$f" 2>&1 | grep 'not found' | awk '{print $1}' | sort -u | tr '\n' ' ')
		if [ -n "$missing" ]; then echo "FAIL $pkg: $f needs $missing"; fail=1; fi
	done < <(dpkg -L "$pkg")
	echo "$pkg: $n ELF files checked"
done
[ $fail = 0 ] && echo "PASS every library resolves"
exit $fail
