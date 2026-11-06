#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
# Proof of BleachBit's "System mail" cleaner (ORDER 415), in a throwaway Debian testing container only: it empties
# /var/mail, installs and removes mail programs and diverts a catalog, so it must never run on a real system.
# The mail is made up (cron, sudo and chkrootkit notices of an invented machine); every check can fail.
#   run-tests.sh postfix|dma DEB      postfix: postfix installed, exim4, nullmailer and dma absent, with their queues
#                                     left behind. dma: dma installed, the others absent; ends with a delivery.
# Needs the container's network for apt (start it with the https-only helper), the edition's published sparky-stereo-problems
# engine installed, and the package built by build.sh (the real, sealed one).
set -u
MODE=${1:?postfix or dma}
DEB=${2:?package file}
FAILS=0
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
export DEBIAN_FRONTEND=noninteractive
[ "$(id -u)" = 0 ] || { echo "run as root in a throwaway container" >&2; exit 2; }
[ -f /.dockerenv ] || { echo "not a container: refusing" >&2; exit 2; }
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d
echo 'postfix postfix/main_mailer_type select Local only' | debconf-set-selections
echo 'postfix postfix/mailname string testbox.invalid' | debconf-set-selections
echo 'dma dma/mailname string testbox.invalid' | debconf-set-selections
echo 'dma dma/relayhost string' | debconf-set-selections
apt-get update -qq >/dev/null && apt-get -y -qq --no-install-recommends install "$MODE" >/dev/null 2>&1 || { echo "FAIL could not install $MODE"; exit 1; }
groupadd -f mail
useradd -m -u 1001 -s /bin/bash alice 2>/dev/null || true
useradd -m -u 1002 -s /bin/bash bob 2>/dev/null || true

# --- the made-up mail
mkdir -p /var/mail
chown root:mail /var/mail && chmod 2775 /var/mail
notice() { printf 'From %s  Mon Mar  4 06:25:01 2019\nFrom: %s\nTo: %s\nSubject: %s\n\n%s\n\n' "$1" "$1" "$2" "$3" "$4"; }
{ notice root@testbox.invalid alice 'Cron <alice@testbox> rclone sync' 'rclone: 3 files copied'
  notice netdata@testbox.invalid alice 'netdata alarm: disk_space._ is WARNING' 'disk space used 91%'
  notice root@testbox.invalid alice 'Security information for testbox' 'alice : TTY=pts/0 ; PWD=/ ; COMMAND=/bin/ls'; } >/var/mail/alice
{ notice root@testbox.invalid root 'chkrootkit output' 'Checking for a rootkit: nothing found'; } >/var/mail/root
{ notice carol@example.invalid bob 'lunch on friday?' 'a message from a person to bob'; } >/var/mail/bob
printf 'alice.lock is not mail: a lock file stays as it is\n' >/var/mail/alice.lock
chown alice:mail /var/mail/alice /var/mail/alice.lock; chmod 0660 /var/mail/alice /var/mail/alice.lock
chown root:mail /var/mail/root; chmod 0660 /var/mail/root
chown bob:mail /var/mail/bob; chmod 0660 /var/mail/bob
printf 'saved by mailx\n' >/root/mbox
printf 'To: root\nSubject: chkrootkit alert\n\nthe alert could not be sent\n' >/root/dead.letter
printf 'To: root\nSubject: failed\n\nalice dead letter\n' >/home/alice/dead.letter; chown alice:alice /home/alice/dead.letter
mkdir -p /home/alice/.msmtp.queue; printf 'a queued message\n' >/home/alice/.msmtp.queue/2019-03-04-06.25.01.mail
printf -- '-a x\n' >/home/alice/.msmtp.queue/2019-03-04-06.25.01.msmtp; chown -R alice:alice /home/alice/.msmtp.queue
printf 'bob keeps this\n' >/home/bob/dead.letter; chown bob:bob /home/bob/dead.letter
# queues left by programs that are gone: exim4 (48 MB on the station), nullmailer, and dma or postfix, whichever is absent
mkdir -p /var/spool/exim4/input /var/spool/exim4/msglog /var/spool/exim4/db
echo H >/var/spool/exim4/input/1pPXyz-000abc-AB-H; echo D >/var/spool/exim4/input/1pPXyz-000abc-AB-D
echo log >/var/spool/exim4/msglog/1pPXyz-000abc-AB; echo db >/var/spool/exim4/db/retry
mkdir -p /var/spool/nullmailer/queue /var/spool/nullmailer/failed /var/spool/nullmailer/tmp
echo q >/var/spool/nullmailer/queue/1700000000.123; echo f >/var/spool/nullmailer/failed/1700000001.456
if [ "$MODE" = postfix ]; then
	mkdir -p /var/spool/dma; chown root:mail /var/spool/dma; chmod 2770 /var/spool/dma; echo M >/var/spool/dma/M1a2b3c; echo Q >/var/spool/dma/Q1a2b3c
	for d in deferred maildrop incoming active; do mkdir -p /var/spool/postfix/$d/0; echo "queued in $d" >/var/spool/postfix/$d/0/ABC123; done
	mkdir -p /var/spool/postfix/etc; echo chroot >/var/spool/postfix/etc/resolv.conf
else
	mkdir -p /var/spool/dma; chown root:mail /var/spool/dma; chmod 2770 /var/spool/dma; echo M >/var/spool/dma/M1a2b3c; echo Q >/var/spool/dma/Q1a2b3c
	mkdir -p /var/spool/postfix/deferred/0 /var/spool/postfix/maildrop; echo old >/var/spool/postfix/deferred/0/OLD1; echo old >/var/spool/postfix/maildrop/OLD2
fi
chmod 750 /var/spool/exim4 /var/spool/nullmailer
[ "$MODE" = dma ] && chmod 700 /var/spool/postfix/deferred /var/spool/postfix/maildrop
stat_of() { stat -c '%U:%G %a %s' "$1"; }
bb() { # bb USER bleachbit args: a person's (or root's) own session, in a home of its own
	local u=$1; shift
	if [ "$u" = root ]; then env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root USER=root LANG=C.UTF-8 bleachbit "$@" 2>&1
	else setpriv --reuid="$u" --regid="$u" --init-groups env -i PATH=/usr/bin:/bin HOME="/home/$(id -nu "$u")" USER="$(id -nu "$u")" LANG=C.UTF-8 bleachbit "$@" 2>&1; fi
}
listed() { grep -oE '(/[A-Za-z0-9._@~+-]+)+' | sort -u; }

# --- red: without the package there is no such cleaner
ok "red: bleachbit has no system_mail cleaner yet" '! bb root --list-cleaners | grep -q "^system_mail\."'
ok "red: --preview system_mail.mailbox lists nothing" '! bb root --preview system_mail.mailbox | grep -q "Truncate"'

# --- presets: what exists before the package (an existing person with an edited file, root with or without one)
mkdir -p /home/alice/.config/bleachbit
printf '[tree]\nsystem.tmp = False\nfirefox.cache = True\n\n[list/whitelist/paths]\n0 = file\n1 = /home/alice/keep-this\n' >/home/alice/.config/bleachbit/bleachbit.ini
chown -R alice:alice /home/alice/.config
sha_alice=$(sha256sum /home/alice/.config/bleachbit/bleachbit.ini | cut -d' ' -f1)
if [ "$MODE" = postfix ]; then
	mkdir -p /root/.config/bleachbit; printf '[tree]\nsystem.tmp = True\n' >/root/.config/bleachbit/bleachbit.ini
	sha_root=$(sha256sum /root/.config/bleachbit/bleachbit.ini | cut -d' ' -f1)
fi

# --- the package, with the real engine
# (the red checks above ran BleachBit as root, which wrote a file of its own defaults: root has none, as on a new machine)
[ "$MODE" != dma ] || rm -rf /root/.config/bleachbit
dpkg -i "$DEB" >/tmp/dpkg.log 2>&1 || { cat /tmp/dpkg.log; echo "FAIL dpkg -i"; exit 1; }
sed "s/^/    dpkg: /" /tmp/dpkg.log | tail -5
# read before BleachBit has run, because BleachBit itself writes defaults into a file it reads
ok "an existing person's edited bleachbit.ini is the same bytes after the install" '[ "$(sha256sum /home/alice/.config/bleachbit/bleachbit.ini | cut -d" " -f1)" = "$sha_alice" ]'
[ "$MODE" != dma ] || ok "root had none: it starts with the root preset, mode 600, in a 700 folder" 'cmp -s /root/.config/bleachbit/bleachbit.ini /usr/share/sparky-stereo-housekeeping/bleachbit-root.ini && [ "$(stat -c %a /root/.config/bleachbit/bleachbit.ini)" = 600 ] && [ "$(stat -c %a /root/.config/bleachbit)" = 700 ]'
[ "$MODE" != postfix ] || ok "root had its own file: the same bytes after the install" '[ "$(sha256sum /root/.config/bleachbit/bleachbit.ini | cut -d" " -f1)" = "$sha_root" ]'
ok "the cleaner is installed by the package's own postinst" 'bb root --list-cleaners | grep -q "^system_mail\."'
ok "nothing was kept as a problem" 'sparky-stereo-housekeeping status >/dev/null'
ok "the cleaner file is not world writable" '[ "$(stat -c %a /usr/share/bleachbit/cleaners/system_mail.xml)" = 644 ]'

# --- the queues the cleaner offers follow dpkg
XML=/usr/share/bleachbit/cleaners/system_mail.xml
ok "exim4 absent: its spool is listed" 'grep -q "path=\"/var/spool/exim4\"" $XML'
ok "nullmailer absent: its queues are listed" 'grep -q "path=\"/var/spool/nullmailer/queue\"" $XML'
ok "msmtp absent: its queue is listed" 'grep -q "path=\"~/.msmtp.queue\"" $XML'
if [ "$MODE" = postfix ]; then
	ok "postfix installed: no postfix queue is listed" '! grep -q "/var/spool/postfix" $XML'
	ok "dma absent: its spool is listed" 'grep -q "path=\"/var/spool/dma\"" $XML'
else
	ok "dma installed: its spool is not listed" '! grep -q "/var/spool/dma" $XML'
	ok "postfix absent: its queue folders are listed" 'grep -q "path=\"/var/spool/postfix/deferred\"" $XML'
fi
ok "ssmtp has no queue: nothing is written for it" '! grep -qi ssmtp $XML'

# --- unticked: a fresh configuration cleans none of it
FRESH=$(mktemp -d); chmod 755 "$FRESH"
out=$(env -i PATH=/usr/bin:/bin HOME="$FRESH" USER=root bleachbit --preset --preview 2>&1)
ok "unticked: --preset with a fresh configuration touches no mail" '! echo "$out" | grep -q "/var/mail\|dead.letter\|/var/spool"'

# --- as the person
b_alice=$(stat_of /var/mail/alice); b_lock=$(stat_of /var/mail/alice.lock)
out=$(bb 1001 --preview system_mail.mailbox system_mail.dead_letter system_mail.queues)
echo "$out" | sed 's/^/    alice preview: /'
exp=$(printf '%s\n' /var/mail/alice /home/alice/dead.letter /home/alice/.msmtp.queue/2019-03-04-06.25.01.mail /home/alice/.msmtp.queue/2019-03-04-06.25.01.msmtp | sort -u)
ok "alice: --preview lists exactly her mailbox, dead.letter and msmtp queue" '[ "$(echo "$out" | listed | grep -E "^/(var|home)/" )" = "$exp" ]'
ok "alice: the preview changed nothing" '[ "$(stat_of /var/mail/alice)" = "$b_alice" ]'
ok "alice: bob is not listed" '! echo "$out" | grep -q "/var/mail/bob\|/home/bob"'
out=$(bb 1001 --clean system_mail.mailbox system_mail.dead_letter system_mail.queues)
echo "$out" | sed 's/^/    alice clean: /'
ok "alice: her mailbox is empty, in place" '[ ! -s /var/mail/alice ] && [ -e /var/mail/alice ]'
ok "alice: her mailbox keeps owner and mode" '[ "$(stat -c %U:%G\ %a /var/mail/alice)" = "alice:mail 660" ]'
ok "alice: her lock file is as it was" '[ "$(stat_of /var/mail/alice.lock)" = "$b_lock" ]'
ok "alice: her dead.letter is gone" '[ ! -e /home/alice/dead.letter ]'
ok "alice: her msmtp queue is empty" '[ -z "$(ls -A /home/alice/.msmtp.queue)" ]'
ok "alice: bob's mail, root's mail and bob's dead.letter are untouched" '[ -s /var/mail/bob ] && [ -s /var/mail/root ] && [ -s /home/bob/dead.letter ]'
ok "alice: no queue of the system was touched" '[ -e /var/spool/exim4/input/1pPXyz-000abc-AB-H ] && [ -e /var/spool/nullmailer/queue/1700000000.123 ]'

# --- a person asking for what needs administrator rights: said, not skipped
out=$(bb 1001 --clean system_mail.mailboxes)
echo "$out" | sed 's/^/    alice mailboxes: /'
ok "alice: --clean system_mail.mailboxes names bob's mailbox as Access denied" 'echo "$out" | grep -q "Access denied: /var/mail/bob"'
ok "alice: bob's mailbox is still there" '[ -s /var/mail/bob ]'

# --- as root
b_root=$(stat_of /var/mail/root); b_bob=$(stat_of /var/mail/bob)
out=$(bb root --preview system_mail.mailboxes system_mail.dead_letter system_mail.queues)
echo "$out" | sed 's/^/    root preview: /'
want="/var/mail/alice /var/mail/root /var/mail/bob /root/mbox /root/dead.letter /var/spool/exim4/input/1pPXyz-000abc-AB-H /var/spool/exim4/input/1pPXyz-000abc-AB-D /var/spool/exim4/msglog/1pPXyz-000abc-AB /var/spool/exim4/db/retry /var/spool/nullmailer/queue/1700000000.123 /var/spool/nullmailer/failed/1700000001.456"
if [ "$MODE" = postfix ]; then want="$want /var/spool/dma/M1a2b3c /var/spool/dma/Q1a2b3c"
else want="$want /var/spool/postfix/deferred/0/OLD1 /var/spool/postfix/maildrop/OLD2"; fi
want=$(printf '%s\n' $want | sort -u)
got=$(echo "$out" | listed | grep -E '^/(var/mail|var/spool|root)/' )
ok "root: --preview lists exactly the expected files" '[ "$got" = "$want" ]'
[ "$got" = "$want" ] || { echo "--- expected"; echo "$want"; echo "--- got"; echo "$got"; }
ok "root: the preview changed nothing" '[ "$(stat_of /var/mail/root)" = "$b_root" ] && [ -e /var/spool/exim4/db/retry ]'
ok "root: the alice lock file is not listed" '! echo "$out" | grep -q "alice.lock"'
ok "root: the installed program's queue is not listed" 'if [ $MODE = postfix ]; then ! echo "$out" | grep -q "/var/spool/postfix"; else ! echo "$out" | grep -q "/var/spool/dma"; fi'
out=$(bb root --clean system_mail.mailboxes system_mail.dead_letter system_mail.queues)
echo "$out" | sed 's/^/    root clean: /'
ok "root: every mailbox is empty and still there" '[ ! -s /var/mail/root ] && [ ! -s /var/mail/bob ] && [ -e /var/mail/root ] && [ -e /var/mail/bob ]'
ok "root: mailboxes keep owner and mode" '[ "$(stat -c %U:%G\ %a /var/mail/bob)" = "bob:mail 660" ] && [ "$(stat -c %U:%G\ %a /var/mail/root)" = "root:mail 660" ]'
ok "root: /var/mail keeps its owner and mode" '[ "$(stat -c %U:%G\ %a /var/mail)" = "root:mail 2775" ]'
ok "root: the lock file is as it was" '[ "$(stat_of /var/mail/alice.lock)" = "$b_lock" ]'
ok "root: /root/mbox is empty and /root/dead.letter is gone" '[ ! -s /root/mbox ] && [ ! -e /root/dead.letter ]'
ok "root: bob's dead.letter (his own home) is untouched" '[ -s /home/bob/dead.letter ]'
ok "root: the spools of exim4 and nullmailer hold no file" '[ -z "$(find /var/spool/exim4 /var/spool/nullmailer -type f)" ]'
if [ "$MODE" = postfix ]; then
	ok "root: postfix is installed, so every file of its queue stays" '[ "$(find /var/spool/postfix/deferred /var/spool/postfix/maildrop /var/spool/postfix/incoming /var/spool/postfix/active -type f | wc -l)" = 4 ] && [ -s /var/spool/postfix/etc/resolv.conf ]'
	ok "root: dma's removed spool holds no file" '[ -z "$(find /var/spool/dma -type f)" ]'
else
	ok "root: dma is installed, so its spool stays" '[ -s /var/spool/dma/M1a2b3c ] && [ -s /var/spool/dma/Q1a2b3c ]'
	ok "root: postfix's removed queue holds no file" '[ -z "$(find /var/spool/postfix -type f)" ]'
fi

# --- dpkg decides: installing and removing programs rewrites the offer
if [ "$MODE" = postfix ]; then
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq remove postfix >/dev/null 2>&1
	ok "postfix removed: dpkg's trigger lists its queue folders" 'grep -q "path=\"/var/spool/postfix/deferred\"" $XML'
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install postfix >/dev/null 2>&1
	ok "postfix installed again: its queue is no longer listed" '! grep -q "/var/spool/postfix" $XML'
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install msmtp >/dev/null 2>&1
	ok "msmtp installed: its queue is no longer listed" '! grep -q ".msmtp.queue" $XML'
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq purge msmtp >/dev/null 2>&1
	ok "msmtp purged: its queue is listed again" 'grep -q ".msmtp.queue" $XML'
	ok "no trigger left a problem behind" 'sparky-stereo-housekeeping status >/dev/null'
else
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq remove dma >/dev/null 2>&1
	ok "dma removed: dpkg's trigger lists its spool" 'grep -q "path=\"/var/spool/dma\"" $XML'
	DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install dma >/dev/null 2>&1
	ok "dma installed again: its spool is no longer listed" '! grep -q "/var/spool/dma" $XML'
fi

# --- a program built by hand has no package: its binary keeps its queue
printf '#!/bin/sh\n' >/usr/sbin/exim4 && chmod 755 /usr/sbin/exim4
python3 /usr/lib/sparky-stereo-housekeeping/system_mail.py refresh
ok "an exim4 program on the system keeps its spool out of the offer" '! grep -q "/var/spool/exim4" $XML'
rm -f /usr/sbin/exim4
python3 /usr/lib/sparky-stereo-housekeeping/system_mail.py refresh
ok "the program gone, the spool is offered again" 'grep -q "path=\"/var/spool/exim4\"" $XML'

# --- the words: English by default, the nine languages through bleachbit's own catalog, Debian's wording kept
cat >/tmp/words.py <<'EOS'
import sys
sys.path.insert(0, '/usr/share')
from bleachbit import CleanerML
from bleachbit.Language import get_text
import bleachbit.Language as L
x = CleanerML.CleanerML('/usr/share/bleachbit/cleaners/system_mail.xml')
c = x.get_cleaner()
print(c.name)
print(c.get_option_descriptions()[0] if hasattr(c, 'get_option_descriptions') else '')
print(c.get_warning('mailbox') if hasattr(c, 'get_warning') else '')
print(get_text('Delete'))
EOS
# glibc's gettext translates nothing in a locale that does not exist: they are made first
for l in en_US de_DE fr_FR ja_JP ko_KR pl_PL pt_BR zh_CN zh_TW; do localedef -i $l -f UTF-8 $l.UTF-8 2>/dev/null; done
for l in en_US de_DE fr_FR ja_JP ko_KR pl_PL pt_BR zh_CN zh_TW; do
	w=$(env -i PATH=/usr/bin:/bin HOME=/root LANG=$l.UTF-8 LANGUAGE=$l python3 -I /tmp/words.py 2>&1 | head -1)
	echo "    $l: $w"
	case $l in en_US) exp="System mail";; de_DE) exp=Systemmail;; fr_FR) exp="Courrier système";; ja_JP) exp=システムメール;; ko_KR) exp="시스템 메일";; pl_PL) exp="Poczta systemowa";; pt_BR) exp="Correio do sistema";; zh_CN) exp=系统邮件;; zh_TW) exp=系統郵件;; esac
	ok "$l: the cleaner's name is $exp" '[ "$w" = "$exp" ]'
done
de_before=$(env -i PATH=/usr/bin:/bin HOME=/root LANG=de_DE.UTF-8 LANGUAGE=de_DE python3 -I - <<'EOS'
import sys
sys.path.insert(0, '/usr/share')
from bleachbit.Language import get_text
print(get_text('Delete'), get_text('Delete the cache'))
EOS
)
ok "German: Debian's own translations are still there ($de_before)" '[ -n "$de_before" ] && [ "$de_before" != "Delete Delete the cache" ]'
ok "the diverted catalogs are Debian's, kept beside" '[ -s /usr/share/locale/de/LC_MESSAGES/bleachbit.mo.debian ] && dpkg-divert --list | grep -q "sparky-stereo-housekeeping"'

# --- bleachbit upgraded (its files unpack to the diverted name): the trigger writes the merged catalog again
rm -f /usr/share/locale/de/LC_MESSAGES/bleachbit.mo
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --reinstall install bleachbit >/dev/null 2>&1
w=$(env -i PATH=/usr/bin:/bin HOME=/root LANG=de_DE.UTF-8 LANGUAGE=de_DE python3 -I /tmp/words.py 2>&1 | head -1)
ok "bleachbit reinstalled: the German name is back after dpkg's trigger" '[ "$w" = Systemmail ] && [ -s /usr/share/locale/de/LC_MESSAGES/bleachbit.mo.debian ]'

# --- the presets: new people and root start with them, an existing file is never written
ini_has() { # ini_has HOME-DIR section.key value: BleachBit's own reading of the file
	env -i PATH=/usr/bin:/bin HOME="$1" python3 -I -c "
import sys
sys.path.insert(0, '/usr/share')
from bleachbit.Options import options
c, o = sys.argv[1].split('.', 1)
sys.exit(0 if str(options.get_tree(c, o)) == sys.argv[2] else 1)" "$2" "$3"
}
ok "an existing person with no file still has none" '[ ! -e /home/bob/.config/bleachbit/bleachbit.ini ]'
useradd -m -u 1003 -s /bin/bash carol
ok "a new person starts with the user preset (/etc/skel)" 'cmp -s /home/carol/.config/bleachbit/bleachbit.ini /etc/skel/.config/bleachbit/bleachbit.ini && [ "$(stat -c %U /home/carol/.config/bleachbit/bleachbit.ini)" = carol ]'
ok "BleachBit reads it: system.tmp, journald.clean, firefox.cache on" 'ini_has /home/carol system.tmp True && ini_has /home/carol journald.clean True && ini_has /home/carol firefox.cache True'
ok "the user preset ticks no localizations, no free-space wipe, no autoremove; system_mail's own options ticked (Daniel 2026-11-06)" '! ini_has /home/carol system.localizations True && ! ini_has /home/carol system.free_disk_space True && ! ini_has /home/carol apt.autoremove True && ini_has /home/carol system_mail.dead_letter True && ini_has /home/carol system_mail.mailbox True && ! ini_has /home/carol system_mail.mailboxes True && ! ini_has /home/carol system_mail.queues True'
printf 'From cron\n\nnotice\n' > /var/mail/carol; chown carol:mail /var/mail/carol; chmod 660 /var/mail/carol
out=$(setpriv --reuid=1003 --regid=1003 --init-groups env -i PATH=/usr/bin:/bin HOME=/home/carol USER=carol LANG=C.UTF-8 bleachbit --preset --preview 2>&1)
ok "carol: --preset --preview lists her own mailbox and no one else's mail or queue" 'echo "$out" | grep -q "/var/mail/carol" && ! echo "$out" | grep -v "/var/mail/carol" | grep -q "/var/mail/\|/var/spool"'
if [ "$MODE" = postfix ]; then
	:
else
	ok "BleachBit reads root's: apt.clean, deepscan.tmp, system.memory, x11.debug_logs and system_mail (dead letters, mailboxes, queues) on, apt.autoremove and localizations off" 'ini_has /root apt.clean True && ini_has /root deepscan.tmp True && ini_has /root system.memory True && ini_has /root x11.debug_logs True && ini_has /root system_mail.dead_letter True && ini_has /root system_mail.mailboxes True && ini_has /root system_mail.queues True && ! ini_has /root apt.autoremove True && ! ini_has /root system.localizations True'
	mkdir -p /var/lib/apt/lists; echo x >/var/lib/apt/lists/fixture_Packages
	out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME=/root USER=root LANG=C.UTF-8 bleachbit --preset --preview 2>&1)
	ok "root: --preset --preview lists the preset's work (apt lists, the mailboxes) and never the installed program's queue" 'echo "$out" | grep -q "/var/lib/apt/lists/fixture_Packages" && echo "$out" | grep -q "/var/mail/" && ! echo "$out" | grep -q "/var/spool/dma"'
fi
# the same package again (an upgrade): nothing of anyone's is written
sha_alice=$(sha256sum /home/alice/.config/bleachbit/bleachbit.ini | cut -d' ' -f1); sha_root=$(sha256sum /root/.config/bleachbit/bleachbit.ini | cut -d' ' -f1)
dpkg -i "$DEB" >/dev/null 2>&1
rm -f /home/carol/.config/bleachbit/bleachbit.ini
ok "reinstall: alice's and root's files are the same bytes" '[ "$(sha256sum /home/alice/.config/bleachbit/bleachbit.ini | cut -d" " -f1)" = "$sha_alice" ] && [ "$(sha256sum /root/.config/bleachbit/bleachbit.ini | cut -d" " -f1)" = "$sha_root" ]'
ok "reinstall: a file a person deleted does not come back" '[ ! -e /home/carol/.config/bleachbit/bleachbit.ini ]'
rm -f /root/.config/bleachbit/bleachbit.ini; dpkg -i "$DEB" >/dev/null 2>&1
ok "upgrade: root's deleted file is not written again" '[ ! -e /root/.config/bleachbit/bleachbit.ini ]'

# --- the real engine keeps a failure and its repair clears it
CL=/usr/share/bleachbit/cleaners/system_mail.xml
rm -f $CL; mkdir $CL
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --reinstall install bleachbit >/tmp/apt-fail.log 2>&1
ok "the cleaner could not be written: the package still configures" 'dpkg -s sparky-stereo-housekeeping | grep -q "^Status: install ok installed"'
sparky-stereo-housekeeping status 2>&1 | sed 's/^/    status: /'
ok "the engine keeps the problem (status exits 1 and names the repair)" '! sparky-stereo-housekeeping status >/dev/null 2>&1'
ok "the engine's list holds a problem of sparky-stereo-housekeeping" 'sparky-stereo-problems list 2>/dev/null | grep -q "sparky-stereo-housekeeping" || ls /var/lib/sparky-stereo-problems | grep -q housekeeping'
rmdir $CL
sparky-stereo-housekeeping repair 2>&1 | sed 's/^/    repair: /'
ok "repair wrote the cleaner again" '[ -f $CL ] && bb root --list-cleaners | grep -q "^system_mail\."'
ok "repair cleared the problem" 'sparky-stereo-housekeeping status >/dev/null 2>&1'

# --- removal gives everything back
before_debian=$(md5sum /usr/share/locale/de/LC_MESSAGES/bleachbit.mo.debian | cut -d' ' -f1)
dpkg -r sparky-stereo-housekeeping >/tmp/rm.log 2>&1
ok "removed: the cleaner is gone" '[ ! -e $XML ] && ! bb root --list-cleaners | grep -q "^system_mail"'
ok "removed: Debian's catalog is back under its own name, byte for byte" '[ "$(md5sum /usr/share/locale/de/LC_MESSAGES/bleachbit.mo | cut -d" " -f1)" = "$before_debian" ] && [ ! -e /usr/share/locale/de/LC_MESSAGES/bleachbit.mo.debian ]'
ok "removed: no diversion is left" '! dpkg-divert --list | grep -q "sparky-stereo-housekeeping"'

# --- dma still delivers after its mailbox was emptied in place
if [ "$MODE" = dma ]; then
	printf 'delivery test\n' | setpriv --reuid=1002 --regid=1002 --init-groups env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/home/bob USER=bob sendmail -f bob@testbox.invalid alice 2>&1 | sed 's/^/    sendmail: /'
	sleep 3
	ok "dma delivered a new local message to the emptied mailbox" 'grep -q "delivery test" /var/mail/alice'
	ok "the mailbox kept its owner and mode through the delivery" '[ "$(stat -c %U:%G\ %a /var/mail/alice)" = "alice:mail 660" ]'
fi
echo "failures: $FAILS"
exit $((FAILS > 0))
