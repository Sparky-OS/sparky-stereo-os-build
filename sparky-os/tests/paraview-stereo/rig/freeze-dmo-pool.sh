#!/bin/bash
# freeze-dmo-pool.sh -- the deb-multimedia pool files the rig needs, into $S/frozen/dmo/pool, taken from the rig's real
# install sequence: on the base image with rig/prelude.sh's sources, deb-multimedia is given as a mirror list (the frozen
# copy $S/frozen/dmo first, deb-multimedia's server second), so apt reads the frozen index alone and fetches a pool file from
# the server only when the frozen copy lacks it, checking it against the frozen index's hash as always. The sequence is
# make-rig.sh's (dist-upgrade, the rig's packages), then, download only, Debian's ten vtk9 and paraview packages of
# apt-upgrade-sim.sh and the stage with KScreen's page (make-green.sh's sets). Every deb-multimedia file apt kept in its cache is
# copied into the frozen pool when its SHA-256 matches the frozen index. List: $S/frozen/dmo-pool.txt.
set -euo pipefail
S=/var/lib/sparky-lanes/science-paraview-50f
F=$S/flat/dmo-sim; rm -rf /var/lib/sparky-lanes/science-paraview-50f/flat/dmo-sim; mkdir -p $F
for st in $S/stage/*/; do cp $st*.deb $F/; done; rm -f /var/lib/sparky-lanes/science-paraview-50f/flat/dmo-sim/*-dbgsym_*.deb; python3 -I $S/rig/flat-index.py $F
C=$S/work/dmo-cache; rm -rf /var/lib/sparky-lanes/science-paraview-50f/work/dmo-cache; mkdir -p $C
RIG="kwin-wayland xwayland libgl1-mesa-dri libegl-mesa0 libglx-mesa0 mesa-vulkan-drivers dbus dbus-x11 xdotool x11-utils x11-xserver-utils xvfb xauth procps locales python3 python3-xlib python3-pil python3-numpy python3-gi gir1.2-glib-2.0 fonts-dejavu-core fonts-noto-cjk mesa-utils gdb gettext-base jmol default-jre paraview python3-matplotlib python3-tk python3-pyqt6 qt6-wayland /sd/libstereo-declare1_1.12.1-1+lc1_amd64.deb /sd/python3-stereo-declare_1.12.1-1+lc1_all.deb"
DEB="libvtk9.6=9.6.2+ds-3 libvtk9.6-qt=9.6.2+ds-3 libvtk9-dev=9.6.2+ds-3 libvtk9-qt-dev=9.6.2+ds-3 python3-vtk9=9.6.2+ds-3 libvtk9-java=9.6.2+ds-3 vtk9=9.6.2+ds-3 paraview=6.1.1+dfsg1-3 paraview-dev=6.1.1+dfsg1-3 python3-paraview=6.1.1+dfsg1-3"
STG="libvtk9.6 libvtk9.6-qt libvtk9-dev libvtk9-qt-dev python3-vtk9 libvtk9-java vtk9 paraview paraview-dev python3-paraview jmol libjmol-java python3-stereo-matplotlib kscreen kde-cli-tools libkf6kcmutils-bin"
$S/scripts/drun.sh dmo-freeze sci50f-base:testing-20261104 --cpus 1 -v $S/rig:/rig:ro -v $S/keys:/run/keys:ro -v $S/frozen/dmo:/dmo:ro \
  -v $S/frozen/sd:/sd:ro -v /var/lib/sparky-lanes/sparky-repo-r1118a:/repo:ro -v $F:/flat:ro -v $C:/cache --user 0:0 -- bash -c "
  set -e; rm -f /etc/apt/apt.conf.d/docker-clean; . /rig/prelude.sh >/dev/null
  printf 'file:/dmo\nhttps://www.deb-multimedia.org/\n' > /etc/apt/dmo-mirrors.txt
  sed -i 's|^URIs: file:///dmo|URIs: mirror+file:/etc/apt/dmo-mirrors.txt|' /etc/apt/sources.list.d/dmo.sources
  apt-get update -qq 2>&1 | tail -3
  apt-get -y -q dist-upgrade > /tmp/du.log 2>&1 || { tail -20 /tmp/du.log; exit 1; }
  apt-get install -y -q --no-install-recommends $RIG > /tmp/in.log 2>&1 || { tail -20 /tmp/in.log; exit 1; }
  apt-get install -y -q --download-only --no-install-recommends $DEB > /tmp/deb.log 2>&1 || { tail -20 /tmp/deb.log; exit 1; }
  echo 'deb [trusted=yes] file:/flat ./' > /etc/apt/sources.list.d/stage.list; apt-get update -qq 2>/dev/null
  apt-get install -y -q --download-only $STG > /tmp/stg.log 2>&1 || { tail -20 /tmp/stg.log; exit 1; }
  cp /var/cache/apt/archives/*.deb /cache/; chown -R 1000:1000 /cache; ls /cache | wc -l"
python3 -I - "$S" <<'PY'
import hashlib, sys
from pathlib import Path
S = Path(sys.argv[1]); root = S / 'frozen' / 'dmo'; cache = S / 'work' / 'dmo-cache'
idx = {}
for comp in ('main', 'non-free'):
    for arch in ('amd64', 'all'):
        p = root / 'dists/forky' / comp / f'binary-{arch}' / 'Packages'
        for stanza in p.read_text().split('\n\n'):
            f = dict(l.split(': ', 1) for l in stanza.splitlines() if ': ' in l and not l.startswith(' '))
            if 'SHA256' in f: idx[f['SHA256']] = f['Filename']
out = []
for deb in sorted(cache.glob('*.deb')):
    h = hashlib.sha256(deb.read_bytes()).hexdigest()
    if h in idx:
        dest = root / idx[h]; dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists(): dest.write_bytes(deb.read_bytes())
        out.append(idx[h])
byname = {v: k for k, v in idx.items()}
listed = [f'{byname[str(q.relative_to(root))]}  {q.relative_to(root)}' for q in sorted((root / 'pool').rglob('*.deb'))
          if byname.get(str(q.relative_to(root))) == hashlib.sha256(q.read_bytes()).hexdigest()]
(S / 'frozen' / 'dmo-pool.txt').write_text('\n'.join(listed) + '\n')
print(len(out), 'taken from this sequence;', len(listed), 'deb-multimedia pool files in the frozen pool (SHA-256 of the frozen index)')
PY
rm -rf /var/lib/sparky-lanes/science-paraview-50f/work/dmo-cache /var/lib/sparky-lanes/science-paraview-50f/flat/dmo-sim
