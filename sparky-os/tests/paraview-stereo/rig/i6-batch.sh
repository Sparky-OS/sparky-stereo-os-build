#!/bin/bash
# Item 6 (row 50 step 5): jmol +stereo3d2 and python3-stereo-matplotlib 0.1.1 from the stage (image sci50f-rig:green-i6).
# The pair once each, the told-once sentences in de and ja, the loaders for all eight languages. Builds are paused meanwhile.
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
export DOCKER_HOST=unix:///K3D/partners/queue/science-paraview-edition-build-and-vtk-draw-buffer-50f/docker.sock
IMG=sci50f-rig:green-i6
b=$(docker ps --format '{{.Names}}' --filter name=sci50f-build- --filter status=running | head -1); [ -n "$b" ] && docker pause "$b" >/dev/null
run() { rig/run-case.sh "$@" > /dev/null; }
run jm-i6-pair $IMG jmol-case.sh LANG=en_US.UTF-8
run mpl-i6-tk-pair $IMG mpl-case.sh MPLBACKEND=TkAgg LANG=en_US.UTF-8
for l in de_DE ja_JP; do
  run jm-i6-support5-$l $IMG jmol-case.sh "JMOL_ARGS=-Djna.library.path=/rig/shim" LANG=$l.UTF-8 LC_ALL=$l.UTF-8
  run mpl-i6-tk-$l $IMG mpl-case.sh MPLBACKEND=TkAgg LANG=$l.UTF-8 LC_ALL=$l.UTF-8
  run mpl-i6-qtwl-$l $IMG mpl-case.sh MPLBACKEND=QtAgg LANG=$l.UTF-8 LC_ALL=$l.UTF-8
done
# the loaders, outside any session
mkdir -p runs/i6-loaders
docker run --rm --name sci50f-i6-loaders --pull=never --ulimit core=1 --cpus 4 --network none --user 1000:1000 -v $S/rig:/rig:ro \
  -v $S/runs/i6-loaders:/out $IMG sh -c 'cd /tmp && cp /rig/i6/BundleCheck.java . && java -cp /usr/share/java/jmol.jar BundleCheck.java de es fr ja ko pl zh_CN zh_TW pt_BR en > /out/jmol-bundles.txt 2>&1; echo "rc=$?" >> /out/jmol-bundles.txt; python3 /rig/i6/mo-check.py de es fr ja ko pl zh_CN zh_TW pt_BR > /out/mpl-catalogues.txt 2>&1; echo "rc=$?" >> /out/mpl-catalogues.txt; python3 -c "import zipfile; z=zipfile.ZipFile(\"/usr/share/java/jmol.jar\"); print(chr(10).join(f\"{i.file_size} {i.filename}\" for i in z.infolist() if \"Stereo3D\" in i.filename))" > /out/jar-entries.txt; ls -la /usr/share/java/jmol.jar >> /out/jar-entries.txt'
[ -n "$b" ] && docker unpause "$b" >/dev/null
for d in runs/jm-i6-*; do echo "$(basename $d) $(python3 -I rig/jmol_analyze.py $d 2>&1 | head -c 400)"; done > runs/i6-summary.txt
for d in runs/mpl-i6-*; do echo "$(basename $d) $(python3 -I rig/mpl_analyze.py $d 2>&1 | head -c 400)"; done >> runs/i6-summary.txt
echo done
