#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Prove the lock packages and CUDA source install and switch in fresh containers.
# Usage: IMAGE=amd64-image lock-alternatives.sh MAIN.deb LEGACY.deb CUDA.deb OUT
set -euo pipefail
MAIN=$(realpath "${1:?main lock .deb}")
LEGACY=$(realpath "${2:?legacy lock .deb}")
CUDA=$(realpath "${3:?CUDA source .deb}")
OUT=$(mkdir -p "${4:?output directory}" && realpath "$4")
: "${IMAGE:?set IMAGE to a clean amd64 image with apt and dpkg}"
NAME_PREFIX=${NAME_PREFIX:-nvidia-lock-proof-$$}
for direction in main legacy; do
	mkdir -p "$OUT/$direction"
	docker run --rm -i --name "$NAME_PREFIX-$direction" --platform linux/amd64 \
		-e DIRECTION="$direction" -e OWNER="$(id -u):$(id -g)" \
		-v "$MAIN":/inputs/main.deb:ro -v "$LEGACY":/inputs/legacy.deb:ro \
		-v "$CUDA":/inputs/cuda.deb:ro -v "$OUT/$direction":/out "$IMAGE" bash -s <<'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
trap 'chown -R "$OWNER" /out' EXIT
run_case() {
	local name=$1 expected=$2 code
	shift 2
	set +e
	"$@" >"/out/$name.log" 2>&1
	code=$?
	set -e
	printf '%s exit=%s expected=%s\n' "$name" "$code" "$expected" | tee -a /out/results.txt
	[ "$code" -eq "$expected" ]
}
main=sparky-stereo-nvidia-driver-lock
legacy=sparky-stereo-nvidia-legacy-580xx-driver-lock
if [ "$DIRECTION" = main ]; then
	first=main second=legacy old=$main new=$legacy
	oldpin=10sparky-stereo-nvidia-driver-lock newpin=09sparky-stereo-nvidia-legacy-580xx-driver-lock
else
	first=legacy second=main old=$legacy new=$main
	oldpin=09sparky-stereo-nvidia-legacy-580xx-driver-lock newpin=10sparky-stereo-nvidia-driver-lock
fi
# Refuse a reused image with either lock already installed.
for package in "$main" "$legacy"; do
	! dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx installed
done
run_case both 100 apt-get -y -s --no-install-recommends install /inputs/main.deb /inputs/legacy.deb
run_case first-plan 0 apt-get -y -s --no-install-recommends install "/inputs/$first.deb" /inputs/cuda.deb
grep -q "^Inst $old " /out/first-plan.log
run_case first-install 0 apt-get -y --no-install-recommends install "/inputs/$first.deb" /inputs/cuda.deb
test -s "/etc/apt/preferences.d/$oldpin"
run_case switch-plan 0 apt-get -y -s --purge --no-install-recommends install "/inputs/$second.deb" /inputs/cuda.deb
grep -q "^Inst $new " /out/switch-plan.log
awk -v allowed="$old" '/^(Remv|Purg) / {if ($2 != allowed) exit 1; found=1} END {if (!found) exit 1}' /out/switch-plan.log
run_case switch-install 0 apt-get -y --purge --no-install-recommends install "/inputs/$second.deb" /inputs/cuda.deb
test ! -e "/etc/apt/preferences.d/$oldpin"
test -s "/etc/apt/preferences.d/$newpin"
dpkg-query -W -f='${Package} ${db:Status-Status}\n' "$new" sparky-stereo-cuda-repo > /out/installed.txt
run_case both-after 100 apt-get -y -s --no-install-recommends install /inputs/main.deb /inputs/legacy.deb
EOF
done
