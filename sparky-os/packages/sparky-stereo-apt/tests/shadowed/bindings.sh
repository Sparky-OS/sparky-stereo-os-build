#!/bin/bash
# ORDER 458b: MLT's Perl and Ruby bindings under the pins, inside the systemd container of run-systemd.sh bindings (the rig of setup.sh, the new
# sparky-stereo-apt at /new, the .debs of our MLT +stereo3d6 at /mlt). A person who had deb-multimedia's libmlt7-perl and libmlt7-ruby3.3 (which
# take our libmlt7 out) upgrades, finds them left and told, then asks for ours, which take theirs. The last pipeline's status is never the verdict.
set -u
FAIL=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
. /t/setup.sh || { echo "rig setup failed"; exit 2; }
NEWDEB=$(ls /new/sparky-stereo-apt_*_all.deb | grep -v -- '-lc-hr')
UNIT=sparky-stereo-apt-shadowed.service
export LC_ALL=C.UTF-8
inst() { dpkg-query -W -f='${db:Status-Status}\n' "$1" 2>/dev/null | grep -qx installed; }
wait_unit() {
	local i st
	for i in $(seq 300); do
		st=$(systemctl show -p ActiveState --value $UNIT)
		{ [ "$st" = inactive ] || [ "$st" = failed ]; } && journalctl -u $UNIT -o cat --no-pager | grep -q . && break
		sleep 1
	done
	echo "unit: ActiveState=$st Result=$(systemctl show -p Result --value $UNIT) (waited ${i}s)"
}
# where the loaded libmlt comes from: the file mapped into the process and the package that owns it
perl_lib() { perl -e 'use mlt; mlt::Factory::init(); open(M,"/proc/$$/maps"); my %s; while(<M>){ $s{$1}=1 if m{(/\S*libmlt-7\.so\S*)} } print join(" ", sort keys %s), "\n"'; }
ruby_lib() { ruby -e 'require "mlt"; Mlt::Factory.init; puts File.readlines("/proc/self/maps").map { |l| l[%r{(/\S*libmlt-7\.so\S*)}, 1] }.compact.uniq.sort.join(" ")'; }
owner() { dpkg -S "$(readlink -f "$1")" 2>/dev/null | sed 's/:.*//' | head -1; }
echo "== a machine of today (sparky-stereo-apt $(dpkg-query -W -f='${Version}' sparky-stereo-apt)): deb-multimedia's bindings installed beside its MLT"
apt-get install -y -q perl ruby libmlt7-perl libmlt7-ruby3.3 >/tmp/dmo.log 2>&1; eq "today: libmlt7-perl and libmlt7-ruby3.3 install" "$?" 0
check "today: our libmlt7 went out for deb-multimedia's libmlt-7-7" sh -c '! dpkg-query -W -f="\${db:Status-Status}" libmlt7 2>/dev/null | grep -qx installed && dpkg-query -W -f="\${db:Status-Status}" libmlt-7-7 | grep -qx installed'
P0=$(perl_lib); R0=$(ruby_lib)
echo "perl -Mmlt maps: $P0 (owner $(owner "${P0%% *}"))"
echo "ruby require 'mlt' maps: $R0 (owner $(owner "${R0%% *}"))"
check "today: both load deb-multimedia's libmlt-7-7" test "$(owner "${P0%% *}")" = libmlt-7-7 -a "$(owner "${R0%% *}")" = libmlt-7-7
apt-mark manual libmlt7-perl libmlt7-ruby3.3 >/dev/null
echo "== the upgrade to the new sparky-stereo-apt: deb-multimedia's bindings keep working, the unit leaves what they need and says so"
apt-get install -y "$NEWDEB" >/tmp/new-install.log 2>&1; eq "the upgrade exits" "$?" 0
wait_unit
journalctl -u $UNIT -o cat --no-pager | grep -v 'Reading\|Building\|Solving' | cut -c1-300
check "libmlt-7-7 is left (the bindings need it)" inst libmlt-7-7
check "the engine names the package that needs it" sh -c 'sparky-stereo-problems list 2>&1 | grep -q "needed by libmlt7-perl"'
check "perl still loads" perl -e 'use mlt; mlt::Factory::init()'
echo "== our MLT with the bindings (/mlt, a flat test repository)"
apt-get install -y -q dpkg-dev >/dev/null 2>&1
mkdir -p /srv/mlt && cp /mlt/*.deb /srv/mlt/ && (cd /srv/mlt && dpkg-scanpackages . >Packages 2>/dev/null)
printf 'deb [trusted=yes] file:/srv/mlt ./\n' >/etc/apt/sources.list.d/rig-mlt.list
# the test repository outranks the published tree for the new MLT (a local file source has an empty origin)
printf 'Package: *\nPin: origin ""\nPin-Priority: 1002\n' >/etc/apt/preferences.d/00-rig-mlt
apt-get -qq update >/dev/null 2>&1
echo "apt-cache policy libmlt-perl: $(apt-cache policy libmlt-perl | sed -n 2,3p | tr -s ' ' | tr '\n' ' ')"
echo "apt-cache policy libmlt-ruby: $(apt-cache policy libmlt-ruby | sed -n 2,3p | tr -s ' ' | tr '\n' ' ')"
echo "apt-get -s install libmlt-perl libmlt-ruby: $(apt-get -s install libmlt-perl libmlt-ruby 2>&1 | grep -E '^(E:|Inst|Remv)' | awk '{print $1" "$2}' | tr '\n' ',')"
check "apt plans to take deb-multimedia's two bindings out" sh -c 'apt-get -s install libmlt-perl libmlt-ruby 2>&1 | grep -q "^Remv libmlt7-perl" && apt-get -s install libmlt-perl libmlt-ruby 2>&1 | grep -q "^Remv libmlt7-ruby3.3"'
apt-get install -y libmlt-perl libmlt-ruby >/tmp/swap.log 2>&1; eq "installing ours exits" "$?" 0
grep -E 'sparky-stereo-apt:' /tmp/swap.log
wait_unit
journalctl -u $UNIT -o cat --no-pager | grep -v 'Reading\|Building\|Solving' | cut -c1-300 | tail -12
for p in libmlt-perl libmlt-ruby libmlt7 libmlt++7; do inst $p && ok "$p is installed ($(dpkg-query -W -f='${Version}' $p))" || bad "$p is not installed"; done
for p in libmlt7-perl libmlt7-ruby3.3 libmlt-7-7 libmlt++-7-7 libmlt7-data; do inst $p && bad "$p is still installed" || ok "$p is gone"; done
P1=$(perl_lib); R1=$(ruby_lib)
echo "perl -Mmlt maps: $P1 (owner $(owner "${P1%% *}"))"
echo "ruby require 'mlt' maps: $R1 (owner $(owner "${R1%% *}"))"
eq "perl loads our libmlt7" "$(owner "${P1%% *}")" libmlt7
eq "ruby loads our libmlt7" "$(owner "${R1%% *}")" libmlt7
eq "only one libmlt is mapped by perl" "$(echo $P1 | wc -w)" 1
perl -e 'use mlt; mlt::Factory::init(); my $p = mlt::Profile->new("atsc_720p_25"); print "perl: profile ", $p->width, "x", $p->height, "\n"' 2>&1
ruby -e 'require "mlt"; Mlt::Factory.init; p = Mlt::Profile.new("atsc_720p_25"); puts "ruby: profile #{p.width}x#{p.height}"' 2>&1
eq "perl builds a profile 1280x720" "$(perl -e 'use mlt; mlt::Factory::init(); my $p = mlt::Profile->new("atsc_720p_25"); print $p->width, "x", $p->height' 2>/dev/null)" 1280x720
eq "ruby builds a profile 1280x720" "$(ruby -e 'require "mlt"; Mlt::Factory.init; p = Mlt::Profile.new("atsc_720p_25"); print "#{p.width}x#{p.height}"' 2>/dev/null)" 1280x720
echo "files: $(dpkg -L libmlt-perl | grep -v '/$' | grep -v doc | tr '\n' ' ')"
echo "files: $(dpkg -L libmlt-ruby | grep -v '/$' | grep -v doc | tr '\n' ' ')"
echo "== what apt chooses now"
for p in libmlt7-perl libmlt7-ruby3.3; do echo "apt-get -s install $p: $(apt-get -s install $p 2>&1 | grep -E '^(E:|Inst|Remv)' | head -3 | tr '\n' ' ')"; done
check "libmlt7-perl is not installable beside ours" sh -c '! apt-get -s install libmlt7-perl >/dev/null 2>&1'
check "libmlt7-ruby3.3 is not installable beside ours" sh -c '! apt-get -s install libmlt7-ruby3.3 >/dev/null 2>&1'
echo "FAIL count: $FAIL"
exit $((FAIL != 0))
