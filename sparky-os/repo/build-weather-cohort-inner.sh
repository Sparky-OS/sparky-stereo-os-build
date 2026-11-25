#!/usr/bin/env bash
set -euo pipefail
umask 022
cd /out
trap 'chown -R "$OWNER" /out' EXIT
export PYTHONPATH=/toolkit DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH=/out/link-scratch
export SPARKY_LC_SIBLINGS_FILE=/out/candidate-siblings.txt SPARKY_LC_PREVIOUS_SIBLINGS_FILE=/out/previous-siblings.txt
export SPARKY_LC_PREVIOUS_DIR=/previous
recipe=/toolkit/packages/$COMPONENT
case "$COMPONENT" in
    sparky-stereo-hardware)
        cp /published-siblings "$SPARKY_LC_SIBLINGS_FILE"
        cp /published-siblings "$SPARKY_LC_PREVIOUS_SIBLINGS_FILE"
        OUT=/out/generated bash "$recipe/build.sh"
        descriptor=(generated/*.dsc)
        dpkg-source -x "${descriptor[0]}" source
        export DEB_BUILD_OPTIONS=parallel=1
        (cd source && dpkg-buildpackage -S -us -uc -d)
        mkdir rebuilt
        mv ./*.dsc ./*.tar.xz ./*_source.* rebuilt/
        (cd rebuilt && dpkg-source -x ./*.dsc build && cd build && dpkg-buildpackage -b -us -uc -d -j1)
        mv rebuilt/*.deb rebuilt/*.dsc rebuilt/*.tar.xz rebuilt/*.changes rebuilt/*.buildinfo .
        python3 -m lean.release check-debs /out/*+lc1_*.deb
        exit
        ;;
    kf6-kiconthemes)
        base=kf6-kiconthemes_6.32.0-1+stereo3d1+lc1.dsc
        digest=b7c6b0956a674b7df5c95d2ad7f374ee327794f4514b6bd11f84985e55954a45
        version=6.32.0-1+stereo3d5
        build_depends='libstereo-layer-dev (>= 1.23.3-1+lc1)'
        patches=("$recipe"/patches/{s2-*,s3-*,s4-*,s5-*}.patch)
        ;;
    kf6-kirigami)
        base=kf6-kirigami_6.32.0-1.dsc
        digest=304fcf326cc66f1408686817af8b9c355597f3ee66cf69e7294ec4fce40d9ec9
        version=6.32.0-1+stereo3d2
        build_depends='libkf6iconthemes-dev (>= 6.32.0-1+stereo3d4+lc1), libstereo-layer-dev (>= 1.23.3-1+lc1)'
        patches=("$recipe"/patches/{s1-*,s2-*,s3-*}.patch)
        preserve=(--preserve-source 'src/*' 'QML type registration and Qt moc use the authored declarations.'
                  --preserve-source 'templates/kirigami6/*' 'KDevelop installs these templates as authored.')
        ;;
    plasma-runners-addons)
        base=kdeplasma-addons_6.7.4-1+stereo3d2+lc1.dsc
        digest=1eca7ecc1b5b3cf767b9c67a43dbefbd7b764719dcb541ffe03ad38fcc68516f
        version=4:6.7.4-1+stereo3d3
        build_depends='libkirigami-dev (>= 6.32.0-1+stereo3d2+lc1)'
        patches=("$recipe"/weather-icon-pairs.patch "$recipe"/weather-forecast-hover.patch)
        restore=(--build-depends-at-end --edition-entry)
        ;;
    stereo-layer)
        mkdir source
        tar -xf layer-source.tar -C source
        printf '%s\n' "$LAYER_REVISION" > layer-source.commit
        version=$(dpkg-parsechangelog -l source/debian/changelog -S Version)
        upstream=${version%-*}
        mkdir orig
        cp -a source "orig/stereo-layer-$upstream"
        rm -r "orig/stereo-layer-$upstream/debian"
        tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$SOURCE_DATE_EPOCH" \
            -C orig -cf - "stereo-layer-$upstream" | xz -9e > "stereo-layer_$upstream.orig.tar.xz"
        rm -r orig
        preserve=(--preserve-source 'src/*.h' 'Qt moc and QML registration read the authored declarations.'
                  --preserve-source 'src/*.cpp' 'Qt moc and QML registration read the authored sources.')
        ;;
    sparky-stereo-weather-settings)
        cp -a "$recipe" source
        version=$(dpkg-parsechangelog -l source/debian/changelog -S Version)
        unset SPARKY_LC_PREVIOUS_DIR
        ;;
    sparky-stereo-weather-icons)
        cp -a "$recipe" source
        cp -a /input/icons source/
        version=$(dpkg-parsechangelog -l source/debian/changelog -S Version)
        unset SPARKY_LC_PREVIOUS_DIR
        ;;
esac
if [[ -n ${base:-} ]]; then
    printf '%s  %s\n' "$digest" "/input/$base" | sha256sum -c
    python3 - "/input/$base" <<'PY'
from hashlib import sha256
from pathlib import Path
from shutil import copy2
import sys

source = Path(sys.argv[1])
copy2(source, source.name)
for line in source.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    digest, size, name = line.split()
    path = source.parent / name
    if path.stat().st_size != int(size) or sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Invalid source input: {path}')
    copy2(path, name)
PY
    dpkg-source -x "$base" source
    if [[ $base == *+lc1.dsc ]]; then
        if [[ $COMPONENT == plasma-runners-addons ]]; then
            python3 - <<'PY'
from pathlib import Path
import re
p = Path('source/debian/control')
control, count = re.subn(r'^Build-Depends: [^\n]+(?:\n[ \t]+[^\n]+)*',
                          lambda match: ' '.join(s.strip() for s in match[0].splitlines()),
                          p.read_text(), count=1, flags=re.M)
if count != 1:
    raise ValueError('Missing folded Build-Depends')
p.write_text(control)
PY
        fi
        python3 /toolkit/repo/plain-from-lc.py "${restore[@]}" --save-plan /out/preserve.json source
        preserve=(--preserve-plan /out/preserve.json)
    fi
    mkdir -p source/debian/patches
    for patch in "${patches[@]}"; do
        cp "$patch" source/debian/patches/
        printf '%s\n' "${patch##*/}" >> source/debian/patches/series
    done
    (cd source && dpkg-source --before-build .)
    python3 - "$build_depends" "$COMPONENT" <<'PY'
from pathlib import Path
import sys

path = Path('source/debian/control')
control = path.read_text().replace('Build-Depends:', f'Build-Depends: {sys.argv[1]},', 1)
if sys.argv[2] == 'plasma-runners-addons':
    old = 'Package: plasma-widgets-addons\nArchitecture: any\nDepends:'
    if control.count(old) != 1:
        raise ValueError('Missing Plasma widgets package')
    control = control.replace(old, old + ' sparky-stereo-weather-icons,\n         qml6-module-org-kde-kirigami (>= 6.32.0-1+stereo3d2+lc1),\n        ', 1)
path.write_text(control)
PY
    (cd source && dch --date "$SOURCE_DATE_RFC2822" --newversion "$version" --distribution unstable "$(cat "$recipe/weather-changelog.txt")")
fi
if [[ $COMPONENT == plasma-runners-addons ]]; then
    # CurrencyUpdateTest uses loopback for its TLS fixture and needs an up network device.
    if [[ -d /ip-fixture ]]; then
        mkdir /tmp/weather-ip
        for archive in /ip-fixture/*.deb; do dpkg-deb -x "$archive" /tmp/weather-ip; done
        ip_path=$(find /tmp/weather-ip/usr -type f -name ip -print -quit)
        fixture_ip() { LD_LIBRARY_PATH=/tmp/weather-ip/usr/lib/x86_64-linux-gnu "$ip_path" "$@"; }
    else
        fixture_ip() { ip "$@"; }
    fi
    test -z "$(fixture_ip route show default)"
    fixture_ip link add weather-test type veth peer name weather-peer
    fixture_ip link set dev weather-test up
    fixture_ip link set dev weather-peer up
fi
shopt -s nullglob
packages=()
for file in /siblings/*.deb /siblings/*/*.deb; do
    case "$file" in *-dbgsym_*|*-lc-hr_*) ;; *) packages+=("$file");; esac
done
if (("${#packages[@]}")); then
    dpkg -i "${packages[@]}"
fi
python3 - "$COMPONENT" "${packages[@]}" <<'PY'
from pathlib import Path
import sys

component = {'plasma-runners-addons': 'kdeplasma-addons'}.get(sys.argv[1], sys.argv[1])
siblings = sys.argv[2:]
replaced = {component, *(Path(file).parent.name for file in siblings)}
listing = Path('/published-siblings')
before = listing.read_text().splitlines() if listing.exists() else []
Path('/out/candidate-siblings.txt').write_text(''.join(f'{p}\n' for p in
    [p for p in before if Path(p).parent.name not in replaced] + siblings))
Path('/out/previous-siblings.txt').write_text(''.join(f'{p}\n' for p in before if Path(p).parent.name != component))
PY
python3 -m lean.debian_prepare source "$version+lc1" --toolkit /toolkit "${preserve[@]}"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" source
export DEB_BUILD_OPTIONS=parallel=1 CTEST_OUTPUT_ON_FAILURE=1
export QT_QPA_PLATFORM=offscreen EGL_PLATFORM=surfaceless LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=1 LC_ALL=C.UTF-8
uid=${OWNER%:*}
if ! getent passwd "$uid" >/dev/null; then
    useradd --uid "$uid" --create-home builder
fi
builder=$(getent passwd "$uid" | cut -d: -f1)
chown -R "$OWNER" source
chmod g+w /out
runuser -u "$builder" -- bash -ec '
    cd /out/source
    dpkg-buildpackage -S -us -uc -d
    source=$(dpkg-parsechangelog -S Source)
    version=$(dpkg-parsechangelog -S Version)
    cd /out
    dpkg-source --no-check -x "${source}_${version#*:}.dsc" build
    cd build
    dpkg-buildpackage -b -us -uc -j1
'
python3 -m lean.release check-debs /out/*+lc1_*.deb
