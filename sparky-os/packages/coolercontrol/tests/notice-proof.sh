#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The notice of upstream's own copy through the problems engine (ORDER 108 milestone 14), on the packages as built. Inside a plain container as root (no systemd, so no
# service is ever started and nothing reaches a device); run like systemd-proof.sh: /new the folder of the 5.1.2-2 build output, /old the folder of the 5.1.2-1 debs
# (the red side), /engine the folder with sparky-stereo-problems_*.deb, /pkg this package's tests folder's parent (for notice-lang.py). The copy of upstream is a
# plain file where upstream's makefile puts its daemon.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
sh /run/https-only-apt.sh >/dev/null 2>&1 || true
apt-get -y -qq update >/dev/null 2>&1
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
apt-get -y -qq --no-install-recommends install /engine/sparky-stereo-problems_*_amd64.deb >/tmp/e.log 2>&1 || { tail -3 /tmp/e.log; echo "FAIL the engine did not install"; exit 1; }
POST=/var/lib/dpkg/info/coolercontrold.postinst
MARK=/var/lib/coolercontrold/local-copy-told
COPY=/usr/local/bin/coolercontrold
cfg() { LC_ALL=$1 LANGUAGE= LANG=$1 sh $POST configure 5.1.2-2+lc1 2>&1; }

echo '== red: 5.1.2-1 with the copy of upstream: one English line on the terminal and nothing through the engine'
apt-get -y -qq --no-install-recommends install /old/coolercontrold_*+lc1_amd64.deb >/tmp/o.log 2>&1 || { tail -5 /tmp/o.log; bad "5.1.2-1 did not install"; }
mkdir -p /usr/local/bin; : >$COPY
out=$(LC_ALL=de_DE.UTF-8 sh $POST configure 5.1.2-1+lc1 2>&1)
[[ $out == *"made by upstream's makefile (/usr/local)"* ]] && ok "5.1.2-1 says it in English on the terminal" || bad "5.1.2-1: $out"
[[ $out != *Kopie* && $out != *"(en)"* && ! -e $MARK ]] && ok "5.1.2-1 says nothing in German and keeps no mark: the person of the app center is told nothing" || bad "5.1.2-1 told more: $out"

echo '== green: 5.1.2-2'
apt-get -y -qq --no-install-recommends install /new/coolercontrold_*+lc1_amd64.deb >/tmp/n.log 2>&1 || { tail -5 /tmp/n.log; bad "5.1.2-2 did not install"; }
grep -q "$COPY" /tmp/n.log && echo "(apt output: $(grep -c 'made by upstream' /tmp/n.log) terminal line)"
dpkg -s coolercontrold | grep -q '^Version: 5.1.2-2' && ok "installed: $(dpkg -s coolercontrold | grep ^Version)" || bad "wrong version installed"
dpkg -s coolercontrold | grep -q '^Depends:.*sparky-stereo-problems (>= 0.2.1)' && ok "Depends on the engine" || bad "no Depends on the engine"
[[ -e $MARK ]] && ok "the install with the copy there told it (mark $MARK)" || bad "no mark after the install: the notice was not said"
[[ -f /usr/lib/systemd/catalog/sparky-stereo-problems-coolercontrold.catalog || -n $(ls /usr/lib/systemd/catalog/*coolercontrold* 2>/dev/null) ]] && ok "the journal catalogue is installed: $(ls /usr/lib/systemd/catalog/ | grep -i cooler)" || bad "no catalogue file"
declare -A WORD=( [en]="A copy of CoolerControl made by upstream" [de]="Eine mit dem Makefile des Entwicklers erstellte Kopie von CoolerControl" [es]="Una copia de CoolerControl hecha con el makefile" [fr]="Une copie de CoolerControl faite avec le makefile"
	[pl]="Kopia CoolerControl zrobiona makefile autora" [pt_BR]="Uma cópia do CoolerControl feita com o makefile" [ja]="開発元の makefile で作った CoolerControl のコピー" [ko]="개발자의 makefile로 만든 CoolerControl 사본"
	[zh_CN]="这台电脑上有用开发者自带 makefile 编译安装的 CoolerControl" [zh_TW]="這台電腦上有用開發者自帶 makefile 編譯安裝的 CoolerControl" )
for l in en de es fr pl pt_BR ja ko zh_CN zh_TW; do
	rm -f $MARK
	loc=$l.UTF-8; [[ $l == en ]] && loc=C.UTF-8; [[ $l == pt_BR ]] && loc=pt_BR.UTF-8
	out=$(cfg $loc)
	[[ $out == *"${WORD[$l]}"* && $out == *"$COPY"* && $out == *"sudo rm $COPY"* ]] && ok "$l: told in the language, with the file of the copy named ($COPY) and the steps" || bad "$l: $out"
	[[ -e $MARK ]] || bad "$l: no mark"
done
echo '== once'
out=$(cfg de_DE.UTF-8); [[ $out == *"made by upstream's makefile (/usr/local)"* && $out != *Kopie* ]] && ok "a second configuration: the terminal line again, the engine's notice not again" || bad "second: $out"
echo '== told again when the copy goes and comes back'
rm -f $COPY; out=$(cfg C.UTF-8); [[ ! -e $MARK && $out != *"A copy of CoolerControl"* ]] && ok "copy gone: no notice, the mark is gone" || bad "copy gone: $out ($(ls $MARK 2>&1))"
: >$COPY; out=$(cfg C.UTF-8); [[ -e $MARK && $out == *"A copy of CoolerControl made by upstream"* ]] && ok "copy back: told again" || bad "copy back: $out"
echo '== two files of the copy are both named'
mkdir -p /etc/systemd/system; : >/etc/systemd/system/coolercontrold.service; rm -f $MARK
out=$(cfg C.UTF-8); [[ $out == *"sudo rm /usr/local/bin/coolercontrold /etc/systemd/system/coolercontrold.service;"* ]] && ok "the steps name both files" || bad "files: $out"
rm -f /etc/systemd/system/coolercontrold.service
echo '== the engine cannot be reached: the terminal says so, no mark, exit 0, tried again later'
rm -f $MARK; mv /usr/bin/sparky-stereo-problems /usr/bin/ssp.off
out=$(cfg C.UTF-8); rc=$?
mv /usr/bin/ssp.off /usr/bin/sparky-stereo-problems
[[ $out == *"could not be said through sparky-stereo-problems"* && ! -e $MARK ]] && ok "said on the terminal, no mark" || bad "engine missing: $out"
out=$(cfg C.UTF-8); [[ -e $MARK ]] && ok "the next configuration says it" || bad "not retried: $out"
echo '== removal and purge take the mark; no copy, no notice'
dpkg --remove coolercontrold >/dev/null 2>&1; [[ ! -e $MARK ]] && ok "remove takes the mark" || bad "mark after remove"
: >$COPY; dpkg --configure -a >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install /new/coolercontrold_*+lc1_amd64.deb >/dev/null 2>&1; [[ -e $MARK ]] && ok "reinstalled with the copy still there: told" || bad "not told after reinstall"
dpkg --purge coolercontrold >/dev/null 2>&1; [[ ! -e $MARK && ! -d /var/lib/coolercontrold ]] && ok "purge takes the mark and its folder" || bad "mark or folder after purge"
rm -f $COPY; apt-get -y -qq --no-install-recommends install /new/coolercontrold_*+lc1_amd64.deb >/tmp/c.log 2>&1
[[ ! -e $MARK ]] && ! grep -q 'made by upstream' /tmp/c.log && ok "no copy: no notice, no mark (control)" || bad "control told"
python3 /pkg/tests/notice-lang.py >/tmp/l.log 2>&1; n=$(grep -c '^PASS' /tmp/l.log); [[ $n == 10 ]] && ok "the notice is in problems-lang in all ten languages" || { cat /tmp/l.log; bad "ten languages: $n"; }
exit $failed
