#!/usr/bin/env bash
# Build one source of the weather icon cohort from an immutable recipe export.
set -euo pipefail
recipe=$(realpath "${1:?recipe directory}")
shift
work=$(realpath -m "${1:?new work directory}")
input=$(realpath "${2:?source input directory}")
previous=$(realpath "${3:?published predecessor binaries directory}")
archive=$(realpath "${4:?signed link archive directory}")
published=$(realpath "${5:?published package tree}")
component=$(basename "$recipe")
image=${IMAGE:?builder image with the frozen build dependencies installed}
name=${CONTAINER_NAME:-$component-weather-build}
threads=${THREADS:-4}
tree=$(git -C "$recipe" rev-parse --show-toplevel)
commit=$(git -C "$tree" rev-parse HEAD)
test -z "$(git -C "$tree" status --porcelain -- sparky-os tools/https-only-apt.sh)" || {
    printf '%s\n' 'Commit the packaging recipe before building.' >&2
    exit 1
}
case "$component" in
    stereo-layer|kf6-kiconthemes|kf6-kirigami|plasma-runners-addons|sparky-stereo-weather-icons|sparky-stereo-hardware|sparky-stereo-weather-settings|stereo-advanced-weather-widget) ;;
    *) exit 64 ;;
esac
[[ "$threads" =~ ^[1-4]$ ]]
mkdir "$work"
mkdir "$work/recipe"
git -C "$tree" archive "$commit" sparky-os/repo sparky-os/lean sparky-os/packages/dpkg-stereo tools/copy-recipe.py \
    "sparky-os/packages/$component" tools/https-only-apt.sh | tar -xf - -C "$work/recipe"
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git -C "$tree" log -1 --format=%ct "$commit" -- "sparky-os/packages/$component" sparky-os/repo/build-weather-cohort.sh sparky-os/repo/build-weather-cohort-inner.sh)
export SPARKY_SOURCE_DATE_BASIS='the last commit changing the committed weather package recipe or shared build job'
export SPARKY_PROVENANCE_REQUIRED=1
source "$tree/sparky-os/repo/build-provenance.sh"
sparky_provenance_init "$image" "$recipe"
test "$(git -C "$tree" rev-parse HEAD)" = "$commit"
mounts=()
if [[ -n ${PUBLISHED_SIBLINGS:-} ]]; then
    mounts+=(--mount "type=bind,source=$(realpath "$PUBLISHED_SIBLINGS"),target=/published-siblings,readonly")
fi
if [[ -n ${SIBLINGS_DIR:-} ]]; then
    mounts+=(--mount "type=bind,source=$(realpath "$SIBLINGS_DIR"),target=/siblings,readonly")
fi
if [[ $component == plasma-runners-addons ]]; then
    mounts+=(--cap-add NET_ADMIN)
    if [[ -n ${IP_FIXTURE_DIR:-} ]]; then
        mounts+=(--mount "type=bind,source=$(realpath "$IP_FIXTURE_DIR"),target=/ip-fixture,readonly")
    fi
fi
if [[ $component == stereo-layer ]]; then
    revision=${LAYER_REVISION:?full stereo-layer commit ID}
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]]
    git -C "$input" archive "$revision" > "$work/layer-source.tar"
    mounts+=(--env "LAYER_REVISION=$revision")
fi
if [[ $component == stereo-advanced-weather-widget ]]; then
    revision=${WIDGET_REVISION:?full widget commit ID}
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]]
    git -C "$input" archive "$revision" contents metadata.json LICENSE 'translate/*.po' > "$work/widget-source.tar"
    mounts+=(--env "WIDGET_REVISION=$revision")
fi
if [[ -n ${CPUSET:-} ]]; then mounts+=(--cpuset-cpus "$CPUSET"); fi
cleanup() {
    local id
    if id=$(docker inspect --type container -f '{{.Id}}' "$name" 2>/dev/null); then
        if [[ -n ${CONTAINER_IDS:-} ]]; then printf '%s\n' "$id" >> "$CONTAINER_IDS"; fi
        docker rm "$name" >/dev/null
    fi
}
trap cleanup EXIT
docker run --name "$name" --pull=never --platform linux/amd64 --ulimit core=1 --cpus "$threads" --network none \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" "${mounts[@]}" \
    --env "COMPONENT=$component" --env "OWNER=$(id -u):$(id -g)" --env "THREADS=$threads" \
    --env SPARKY_LC_ROOT_MIN_FREE_GIB="${SPARKY_LC_ROOT_MIN_FREE_GIB:-1}" \
    --env SPARKY_LC_MIN_FREE_GIB="${SPARKY_LC_MIN_FREE_GIB:-4}" \
    --mount "type=bind,source=$work,target=/out" \
    --mount "type=bind,source=$work/recipe/sparky-os,target=/toolkit,readonly" \
    --mount "type=bind,source=$input,target=/input,readonly" \
    --mount "type=bind,source=$previous,target=/previous,readonly" \
    --mount "type=bind,source=$archive,target=/archive,readonly" \
    --mount "type=bind,source=$published,target=/round,readonly" \
    --mount "type=bind,source=$(command -v git),target=/usr/bin/git,readonly" \
    --mount "type=bind,source=$work/recipe/tools/copy-recipe.py,target=/tools/copy-recipe.py,readonly" \
    --mount "type=bind,source=$work/recipe/tools/https-only-apt.sh,target=/run/https-only-apt.sh,readonly" \
    --mount type=bind,source=/etc/ssl/certs/ca-certificates.crt,target=/run/host-ca.crt,readonly \
    "$image" bash -ec 'sh /run/https-only-apt.sh; bash /toolkit/repo/build-weather-cohort-inner.sh >/out/build.log 2>&1'
