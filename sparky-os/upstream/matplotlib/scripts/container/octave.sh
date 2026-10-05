export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get -y install octave xvfb xauth >/tmp/apt.log 2>&1
cat > /tmp/work.sh <<'EOS'
export HOME=/tmp
cd /w && xvfb-run -a octave --no-gui --eval "prove_octave_stereo('octave-stereo.png')" 2>&1 | grep -E "^(\{|error)"
EOS
setpriv --reuid=1000 --regid=1000 --clear-groups bash /tmp/work.sh
