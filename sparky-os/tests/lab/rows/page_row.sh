#!/bin/bash
# page_row.sh SIDE STEPS: in a lab22-page image, as root. Runs the Sound Quality page's own QML type (the SoundFormats type of
# plasma-pa, org.kde.plasma.private.volume) from the page rig's harness against a private PipeWire, WirePlumber and pipewire-pulse
# session whose sound devices are the rig's fake ones, driven by the steps file STEPS (a JSON list of apply, dump and wait steps
# in /lab/rows). What it prints goes to /evidence/page.txt for rows/page_judge.py; the raw output of qml6 to /evidence/qml-raw.log.
# SIDE ours: the engine (sparky-stereo-audio detect --write) has made its choices first, as at install time. SIDE stock: Debian's
# plasma-pa, no engine. Exit codes are the judge's: 0 holds, 1 does not, 77 the session could not start, 2 a crash.
set -u
ulimit -c 1
SIDE=$1 STEPS=${2:-page-steps.json}
mkdir -p /run/sa631 && chmod 777 /run/sa631
export SPARKY_STEREO_AUDIO_PROC=/opt/sa631/proc-asound
if [ "$SIDE" = ours ]; then
	SPARKY_STEREO_AUDIO_CPU_COST=10 sparky-stereo-audio detect --write > /evidence/engine-detect.txt 2>&1
fi
# a systemctl that restarts this private session the way systemd would restart the user's units
cat > /usr/local/bin/systemctl <<'SC'
#!/bin/bash
if [ "$1" = "--user" ] && [ "$2" = "restart" ]; then
  for p in wireplumber pipewire-pulse pipewire; do pkill -x $p 2>/dev/null; done
  sleep 0.5
  export XDG_RUNTIME_DIR=/run/user/1001 HOME=/home/rig
  setsid pipewire >/tmp/pipewire.log 2>&1 </dev/null &
  for i in $(seq 50); do [ -S $XDG_RUNTIME_DIR/pipewire-0 ] && break; sleep 0.1; done
  setsid wireplumber >/tmp/wireplumber.log 2>&1 </dev/null &
  setsid pipewire-pulse >/tmp/pipewire-pulse.log 2>&1 </dev/null &
  exit 0
fi
exit 1
SC
chmod +x /usr/local/bin/systemctl
mkdir -p /run/user/1001 /home/rig/.config && chown -R rig:rig /run/user/1001 /home/rig && chmod 700 /run/user/1001
cp /lab/rows/$STEPS /tmp/steps.json && chmod 644 /tmp/steps.json
cat > /tmp/page-qml.sh <<'Q'
cd /tmp
qml6 /opt/lab/rig/harness.qml > /tmp/qml-raw.log 2>&1
grep -E "^qml: (DUMP|RESULT)" /tmp/qml-raw.log | sed 's/^qml: //' > /tmp/page.txt
# the running graph as PipeWire itself says it, after the page's last change, read here and not by the page
pw-metadata -n settings > /tmp/graph-after.txt 2>&1
Q
export PATH=/usr/local/bin:$PATH
setpriv --reuid 1001 --regid 1001 --clear-groups env HOME=/home/rig XDG_RUNTIME_DIR=/run/user/1001 SA631_PULSE=1 PATH=$PATH \
	SPARKY_STEREO_AUDIO_PROC=$SPARKY_STEREO_AUDIO_PROC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen bash /opt/lab/rig/session.sh bash /tmp/page-qml.sh
cp /tmp/qml-raw.log /evidence/qml-raw.log 2>/dev/null || true
cp /tmp/page.txt /evidence/page.txt 2>/dev/null || true
cp /tmp/graph-after.txt /tmp/pipewire.log /tmp/wireplumber.log /evidence/ 2>/dev/null || true
exec python3 -I /lab/rows/page_judge.py /evidence/page.txt /evidence/qml-raw.log /evidence/graph-after.txt
