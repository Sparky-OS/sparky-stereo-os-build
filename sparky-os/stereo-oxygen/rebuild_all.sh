#!/bin/bash
# the whole chain: generate, assemble, loaders, centre check, generator check, KWin proofs
cd /K3D/temp/partners/queue/stereo-oxygen/step1
rm -rf out-all
TMO=3000 ./run-gen.sh python3 make_stereo_icon.py --oxygen-icons /q/oxygen-icons --icons $(cat icons.txt) --out /q/step1/out-all --probe --depthmaps /q/step1/depthmaps > gen-all.log 2>&1
python3 assemble.py > assemble.log 2>&1
timeout 600 docker run --rm --name stereo-oxygen-loaders -u $(id -u):$(id -g) -v /K3D/temp/partners/queue/stereo-oxygen:/q stereo-oxygen-loader-test:1 /q/step1/loader/run_loaders.sh > loader/run.log 2>&1
TMO=300 ./run-gen.sh python3 /q/step1/loader/check_loaders.py > loader/check.log 2>&1
TMO=300 ./run-gen.sh python3 /q/step1/centre_vs_plain.py $(cat icons.txt) > centre_vs_plain.log 2>&1
timeout 300 docker run --rm --name stereo-oxygen-build -u $(id -u):$(id -g) -v /K3D/temp/partners/queue/stereo-oxygen:/q kwin-forky-builddeps:6.7.4 /q/step1/viewer/build.sh > viewer/build.log 2>&1
cd proofs; rm -rf out/p? out/h? out-*.log
# path 1: our Mesa (EGL_EXT_multiview_window), KWin +stereo3d13+depth3
./run.sh pa 1700x1300 1 2 > out-pa.log 2>&1; ./run.sh pb 2800x2300 3 > out-pb.log 2>&1; ./run.sh pc 2100x1700 4:32 4:48 4:128 > out-pc.log 2>&1; ./run.sh pd 2100x6000 4:256 > out-pd.log 2>&1
# path 2: Debian's stock Mesa (the host image), KWin +stereo3d13+depth4~host
export IMAGE=stereo-oxygen-host:1 CAPBIN=/q/step1/proofs/bin-host/qt-capture
./run.sh ha 1700x1300 1 2 > out-ha.log 2>&1; ./run.sh hb 2800x2300 3 > out-hb.log 2>&1; ./run.sh hc 2100x1700 4:32 4:48 4:128 > out-hc.log 2>&1; ./run.sh hd 2100x6000 4:256 > out-hd.log 2>&1
unset IMAGE CAPBIN
cd ..
chk() { echo "=== $1 $2 (path $4)"; TMO=900 ./run-gen.sh python3 /q/step1/proofs/check_sheet.py /q/step1/proofs/out/$1 $2 $3 $4 2>&1 | tail -n 14; }
{ chk pa page1 1700 multiview; chk pa page2 1700 multiview; chk pb page3 2800 multiview; chk pc page4-32 2100 multiview; chk pc page4-48 2100 multiview; chk pc page4-128 2100 multiview; chk pd page4-256 2100 multiview
  chk ha page1 1700 declare; chk ha page2 1700 declare; chk hb page3 2800 declare; chk hc page4-32 2100 declare; chk hc page4-48 2100 declare; chk hc page4-128 2100 declare; chk hd page4-256 2100 declare; } > proofs/check-all.log 2>&1
TMO=3000 ./run-gen.sh python3 check_generator.py > check_generator.log 2>&1
TMO=3000 ./run-gen.sh python3 check_rule_c.py > check_rule_c.log 2>&1
echo chain-done > chain-done.log
