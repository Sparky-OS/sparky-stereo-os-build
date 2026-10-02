#!/bin/bash
# Review round 1 tests, run inside the locales-r1-base container (see tests/run.sh).
# Usage: round1.sh TEST   (DEB=/path/to/sparky-stereo-locales_x.deb)
export DEBIAN_FRONTEND=noninteractive
TOOL=sparky-stereo-locales
FAILS=0

ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
installed() { [ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" = "ii " ]; }
present() { check "$1 installed" installed "$1"; }
not() { ! "$@"; }
absent() { check "$1 removed" not installed "$1"; }

setup() {
	dpkg -i "$DEB" >/dev/null 2>&1 || { echo "cannot install $DEB"; exit 99; }
	echo 'LANG=en_US.UTF-8' >/etc/default/locale
}

# A package that depends on a language package: apt purge drags it along.
fake_app() {
	local d=/tmp/fake-app
	mkdir -p $d/DEBIAN
	cat >$d/DEBIAN/control <<CTL
Package: fake-app
Version: 1
Architecture: all
Maintainer: test <t@example.org>
Depends: hunspell-de-de
Description: test
 test
CTL
	dpkg-deb -b $d /tmp/fake-app.deb >/dev/null && dpkg -i /tmp/fake-app.deb >/dev/null 2>&1
}

# A package with files under locale names that are prefixed by other languages' names.
fake_locale_files() {
	local d=/tmp/fake-loc n
	mkdir -p $d/DEBIAN
	cat >$d/DEBIAN/control <<CTL
Package: fake-loc
Version: 1
Architecture: all
Maintainer: test <t@example.org>
Description: test
 test
CTL
	for n in fi fil fr frp ko kok ja jam cs csb pt_BR pt_PT de_AT en_GB zh_CN zh_TW sr@latin; do
		mkdir -p $d/usr/share/locale/$n/LC_MESSAGES
		echo x >$d/usr/share/locale/$n/LC_MESSAGES/fake.mo
	done
	dpkg-deb -b $d /tmp/fake-loc.deb >/dev/null
}

t1_kept_not_removed() {
	setup
	timeout 600 $TOOL --keep en,pl,pt >/tmp/out 2>&1
	for p in libreoffice-help-pl libreoffice-help-en-us libreoffice-help-pt libreoffice-help-pt-br libreoffice-l10n-pl \
		hunspell-pl hunspell-en-us hunspell-pt-br hunspell-tools libreoffice-help-common libreoffice-writer firefox-esr; do
		present $p
	done
	absent libreoffice-help-de
	absent hunspell-de-de
}

t1_refuse_extras() {
	setup
	fake_app
	timeout 600 $TOOL --keep en,pl,pt >/tmp/out 2>&1
	local rc=$?
	check "exit status is not 0 (got $rc)" test $rc -ne 0
	present fake-app
	present hunspell-de-de
	present firefox-esr-l10n-de
	check "message names fake-app" grep -q fake-app /tmp/out
}

t1_dryrun_exact() {
	setup
	fake_app
	timeout 600 $TOOL --keep en,pl,pt --dry-run >/tmp/out 2>&1
	local rc=$?
	check "dry run with an apt side effect refuses (exit $rc)" test $rc -ne 0
	check "dry run names fake-app" grep -q fake-app /tmp/out
	apt-get -y purge fake-app >/dev/null 2>&1
	timeout 600 $TOOL --keep en,pl,pt --dry-run >/tmp/out 2>&1
	check "dry run exit 0 without the side effect" test $? -eq 0
	sed -n 's/^apt-get purge -y //p' /tmp/out | tr ' ' '\n' | sort -u >/tmp/planned
	dpkg-query -W -f='${Package}\n' | sort >/tmp/before
	timeout 600 $TOOL --keep en,pl,pt >/dev/null 2>&1
	dpkg-query -W -f='${Package}\n' | sort >/tmp/after
	comm -23 /tmp/before /tmp/after >/tmp/removed
	check "dry run list equals what the real run removed ($(wc -l </tmp/planned) planned, $(wc -l </tmp/removed) removed)" cmp -s /tmp/planned /tmp/removed
}

has_pkgs() { local want="$1"; shift; for p in "$@"; do installed "$p" || return 1; done; }

t2_locale_codes() {
	setup
	local rc
	for code in pt_BR pt-br PT_br; do
		echo "--- keep en,pl,$code"
		timeout 600 $TOOL --keep en,pl,$code --dry-run >/tmp/out 2>&1
		rc=$?
		check "$code accepted (exit $rc)" test $rc -eq 0
		for p in firefox-esr-l10n-pt-br hunspell-pt-br hyphen-pt-br mythes-pt-br libreoffice-l10n-pt-br libreoffice-help-pt-br; do
			check "$code keeps $p in the plan" not grep -qw $p /tmp/out
		done
		check "$code drops pt-pt in the plan" grep -qw hunspell-pt-pt /tmp/out
	done
	echo "--- zh_CN"
	timeout 600 $TOOL --keep zh_CN >/tmp/out 2>&1
	for p in firefox-esr-l10n-zh-cn libreoffice-l10n-zh-cn libreoffice-help-zh-cn fcitx5-chinese-addons firefox-esr-l10n-en-gb; do present $p; done
	for p in firefox-esr-l10n-zh-tw libreoffice-l10n-zh-tw libreoffice-help-zh-tw fcitx5-chewing fcitx5-mozc fcitx5-hangul firefox-esr-l10n-pl; do absent $p; done
}

t2_sr_latin() {
	setup
	timeout 600 $TOOL --keep sr@latin >/tmp/out 2>&1
	check "sr@latin accepted (exit $?)" test $? -eq 0
	present hunspell-sr
}

t2_unknown_code() {
	setup
	dpkg-query -W -f='${Package}\n' | sort >/tmp/before
	timeout 600 $TOOL --keep xx >/tmp/out 2>&1
	local rc=$?
	check "unknown code exits non-zero (got $rc)" test $rc -ne 0
	timeout 600 $TOOL --keep en,xx --dry-run >/tmp/out2 2>&1
	check "unknown code in a list exits non-zero in dry run" test $? -ne 0
	dpkg-query -W -f='${Package}\n' | sort >/tmp/after
	check "nothing removed" cmp -s /tmp/before /tmp/after
	check "no exclude file written" test ! -e /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
}

t2_bare_keep() {
	setup
	timeout 5 $TOOL --keep >/tmp/out 2>&1
	local rc=$?
	check "bare --keep does not hang (rc $rc)" test $rc -ne 124
	check "bare --keep is an error (rc $rc)" test $rc -ne 0
}

t2_english_always() {
	setup
	timeout 600 $TOOL --keep pl >/tmp/out 2>&1
	for p in hunspell-en-us hyphen-en-us mythes-en-us libreoffice-help-en-us firefox-esr-l10n-en-gb libreoffice-l10n-en-gb hunspell-pl; do present $p; done
	absent hunspell-de-de
	check "no exclude for en" not grep -Eq 'exclude=.*/en([_@*/]|$)' /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
}

t3_no_options() {
	setup
	echo 'LANG=pl_PL.UTF-8' >/etc/default/locale
	unset DISPLAY WAYLAND_DISPLAY
	dpkg-query -W -f='${Package}\n' | sort >/tmp/before
	timeout 20 $TOOL </dev/null >/tmp/out 2>&1
	local rc=$?
	check "no options and no display exits non-zero (got $rc)" test $rc -ne 0
	check "usage printed" grep -qi usage /tmp/out
	dpkg-query -W -f='${Package}\n' | sort >/tmp/after
	check "nothing changed" cmp -s /tmp/before /tmp/after
	timeout 600 $TOOL --dry-run >/tmp/out 2>&1
	rc=$?
	check "--dry-run alone exits 0 (got $rc)" test $rc -eq 0
	check "--dry-run alone prints a plan" grep -q 'hunspell-de-de' /tmp/out
	check "--dry-run alone keeps pl" not grep -qw hunspell-pl /tmp/out
	check "--dry-run alone keeps en" not grep -qw hunspell-en-us /tmp/out
	check "--dry-run alone changed nothing" installed hunspell-de-de
}

stub_yad() {
	mkdir -p /tmp/stub
	cat >/tmp/stub/yad <<'EOS'
#!/bin/bash
n=$((${COUNT:-0}))
{ echo "== yad call"; echo "argc=$#"; for a in "$@"; do printf '[%s]\n' "$a"; done; } >>/tmp/yad.args
case " $* " in
	*" --list "*) printf '%b' "${STUB_ANSWER-TRUE|pl|Polish|\\n}"; exit "${STUB_RC:-0}" ;;
	*) exit "${STUB_RC2:-0}" ;;
esac
EOS
	chmod +x /tmp/stub/yad
	: >/tmp/yad.args
}

t4_gui() {
	setup
	echo 'LANG=pl_PL.UTF-8' >/etc/default/locale
	stub_yad
	export PATH=/tmp/stub:$PATH DISPLAY=:99
	STUB_ANSWER='TRUE|pl|Polish|\nTRUE|pt_BR|Portuguese (Brazil)|\nFALSE|de|German|\n' timeout 600 $TOOL </dev/null >/tmp/out 2>&1
	echo "exit $?"; head -c 1500 /tmp/yad.args
	local n; n=$(sed -n 's/^argc=//p' /tmp/yad.args | head -1)
	check "yad got many arguments (argc=$n)" test "${n:-0}" -gt 40
	check "three --column arguments" test "$(grep -c '^\[--column=' /tmp/yad.args)" -ge 3
	check "no argument holds a whole row with pipes" not grep -q '^\[\(TRUE\|FALSE\)|' /tmp/yad.args
	check "separator is one argument" grep -q '^\[--separator=|\]' /tmp/yad.args
	check "pl row preselected from /etc/default/locale" awk '/^\[pl\]$/ && prev=="[TRUE]" {f=1} {prev=$0} END{exit !f}' /tmp/yad.args
	check "de row not preselected" awk '/^\[de\]$/ && prev=="[FALSE]" {f=1} {prev=$0} END{exit !f}' /tmp/yad.args
	check "a confirmation question was asked" grep -q '^\[--question\]' /tmp/yad.args
	check "Apply and Cancel buttons" bash -c "grep -q -- '--button' /tmp/yad.args"
	present hunspell-pl
	present hunspell-pt-br
	present hunspell-en-us
	absent hunspell-de-de
	absent hunspell-pt-pt
	# the answer No to the question changes nothing
	dpkg-query -W -f='${Package}\n' | sort >/tmp/before
	STUB_RC2=1 STUB_ANSWER='TRUE|en|English|\nTRUE|fr|French|\n' timeout 600 $TOOL </dev/null >/tmp/out 2>&1
	dpkg-query -W -f='${Package}\n' | sort >/tmp/after
	check "answering No changes nothing" cmp -s /tmp/before /tmp/after
	# cancel changes nothing
	dpkg-query -W -f='${Package}\n' | sort >/tmp/before
	STUB_RC=1 STUB_ANSWER='' timeout 600 $TOOL </dev/null >/tmp/out 2>&1
	dpkg-query -W -f='${Package}\n' | sort >/tmp/after
	check "Cancel changes nothing" cmp -s /tmp/before /tmp/after
}

t5_path_excludes() {
	setup
	fake_locale_files
	timeout 600 $TOOL --keep en,pt_BR >/tmp/out 2>&1
	check "no prefix patterns (name*) in the exclude file" not grep -Eq 'path-(exclude|include)=[^ ]*/[a-z]+\*$' /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
	dpkg -i /tmp/fake-loc.deb >/dev/null 2>&1
	f() { test -e /usr/share/locale/$1/LC_MESSAGES/fake.mo; }
	for n in fil frp kok jam csb pt_BR en_GB; do check "locale $n kept" f $n; done
	for n in fi fr ko ja cs pt_PT de_AT zh_CN zh_TW; do check "locale $n excluded" not f $n; done
}

t5_path_excludes_keep_sr() {
	setup
	fake_locale_files
	timeout 600 $TOOL --keep en,zh_CN,sr@latin >/tmp/out 2>&1
	dpkg -i /tmp/fake-loc.deb >/dev/null 2>&1
	f() { test -e /usr/share/locale/$1/LC_MESSAGES/fake.mo; }
	for n in zh_CN en_GB 'sr@latin'; do check "locale $n kept" f $n; done
	for n in zh_TW pt_BR pt_PT de_AT; do check "locale $n excluded" not f $n; done
}

t6_strings() {
	setup
	local d=/usr/share/sparky/sparky-stereo-locales
	for l in en pl pt_BR; do check "lang file $l installed" test -s $d/$l; done
	for l in pl pt_BR; do
		echo "LANG=$l.UTF-8" >/etc/default/locale
		[ $l = pl ] && echo 'LANG=pl_PL.UTF-8' >/etc/default/locale || echo 'LANG=pt_BR.UTF-8' >/etc/default/locale
		timeout 20 $TOOL --help >/tmp/out.$l 2>&1
		cat /tmp/out.$l | head -5
	done
	check "Polish help differs from English" not cmp -s /tmp/out.pl /tmp/out.pt_BR
	check "Polish help has Polish text" grep -q 'Użycie' /tmp/out.pl
	check "pt_BR help has Portuguese text" grep -q 'Uso' /tmp/out.pt_BR
	local k1 k2 k3
	k1=$(sed -n 's/^\(LOCAL[0-9]*\)=.*/\1/p' $d/en | sort | tr '\n' ' ')
	k2=$(sed -n 's/^\(LOCAL[0-9]*\)=.*/\1/p' $d/pl | sort | tr '\n' ' ')
	k3=$(sed -n 's/^\(LOCAL[0-9]*\)=.*/\1/p' $d/pt_BR | sort | tr '\n' ' ')
	check "same keys in en, pl, pt_BR" test "$k1" = "$k2" -a "$k1" = "$k3"
	check "desktop file has Version and Name[pl]" bash -c "grep -q '^Version=1.0' /usr/share/applications/sparky-stereo-locales.desktop && grep -q '^Name\[pl\]=' /usr/share/applications/sparky-stereo-locales.desktop"
	check "package depends on sparky-remsu" bash -c "dpkg-query -W -f='\${Depends}' $TOOL | grep -q sparky-remsu"
}

t6_tree() {
	local t=$TREE
	for f in LICENSE install.sh lang/en lang/pl lang/pt_BR README.md CHANGELOG copyright; do check "tree has $f" test -s $t/$f; done
	check "README has Install: and Uninstall:" bash -c "grep -q '^Install:' $t/README.md && grep -q '^Uninstall:' $t/README.md"
	check "install.sh installs and uninstalls" bash -c "cd $t && cp -r . /tmp/tree && cd /tmp/tree && sh install.sh >/dev/null 2>&1 && test -x /usr/bin/sparky-stereo-locales && test -s /usr/share/sparky/sparky-stereo-locales/pl && sh install.sh uninstall >/dev/null 2>&1 && test ! -e /usr/bin/sparky-stereo-locales"
}

for t in "$@"; do
	echo "== $t"
	"$t"
done
echo "== failures: $FAILS"
exit $((FAILS > 0))
