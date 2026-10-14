#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/14
# Runs as root inside a throwaway container that has accountsservice, adduser, sshd and the
# calamares package; DEB is the built package. Nothing here touches a host.
set -uo pipefail
DEB=${DEB:?Set DEB to the built .deb}
FAIL=0
ok() { echo "PASS  $*"; }
bad() { echo "FAIL  $*"; FAIL=$((FAIL + 1)); }
eq() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

FORBIDDEN='root adm admin disk docker input kmem lxd operator podman shadow staff sys systemd-journal tty'
WANTED='games dialout plugdev audio video bluetooth netdev lpadmin scanner kvm libvirt render sambashare'
admin_groups() { echo 'sudo'; }

groups_of() { id -nG "$1" | tr ' ' '\n' | sort | paste -sd' '; }
set_of() { tr ' ' '\n' <<<"$*" | awk 'NF' | sort -u | paste -sd' '; }

# what a user must have: own group, users, the wanted groups that exist here, plus extras
expect() {
	local u=$1; shift
	local g all="$u users $*"
	for g in $WANTED; do getent group "$g" >/dev/null && all="$all $g"; done
	set_of "$all"
}

no_forbidden() {
	local u=$1 g
	for g in $FORBIDDEN; do
		if id -nG "$u" | tr ' ' '\n' | grep -qx "$g"; then
			echo "$u is in $g"
			return 1
		fi
	done
	return 0
}

busctl_call() { busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts "$@"; }

start_services() {
	mkdir -p /run/dbus /run/polkit-1 /run/sshd
	dbus-uuidgen --ensure
	dbus-daemon --system --fork
	(/usr/lib/polkit-1/polkitd --no-debug >/var/log/polkitd.log 2>&1 &)
	(/usr/libexec/accounts-daemon >/var/log/accounts-daemon.log 2>&1 &)
	ssh-keygen -A >/dev/null
	/usr/sbin/sshd -o UsePAM=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes
	sleep 2
}

echo "== groups on this system"
for g in $WANTED; do getent group "$g" >/dev/null && echo "present $g" || echo "ABSENT  $g"; done

echo "== before the package: one user exists already"
adduser --quiet --disabled-password --comment 'Zed Before' zed
ZED_BEFORE=$(groups_of zed)
ADDUSER_SUM_BEFORE=$(sha256sum /etc/adduser.conf | cut -d' ' -f1)
ADDUSER_BEFORE=$(cat /etc/adduser.conf | md5sum)
CAL_SHIPPED_SUM=$(sha256sum /usr/share/calamares/modules/users.conf | cut -d' ' -f1)

echo "== install"
dpkg -i "$DEB" >/tmp/dpkg.log 2>&1 && ok "package installs" || { cat /tmp/dpkg.log; bad "package installs"; }
sparky-stereo-user-groups check && ok "check passes on the shipped list" || bad "check on the shipped list"
sparky-stereo-user-groups status
eq "existing user is not changed by the install" "$(groups_of zed)" "$ZED_BEFORE"
sparky-stereo-user-groups propose | tee /tmp/propose.txt
grep -q '^usermod -aG .* zed$' /tmp/propose.txt && ok "propose names the existing user" || bad "propose names the existing user"
eq "propose did not change the user" "$(groups_of zed)" "$ZED_BEFORE"

if [[ -n ${PLANT:-} ]]; then
	echo "== PLANT=$PLANT: this run must fail"
	groupadd "$PLANT" 2>/dev/null || true
	echo "$PLANT" >>/etc/sparky-stereo/user-groups
	sparky-stereo-user-groups apply 2>&1 | sed 's/^/helper: /' || true
	sed -i "s/^EXTRA_GROUPS=\"/EXTRA_GROUPS=\"$PLANT /" /etc/adduser.conf
fi

start_services

echo "== way 1: adduser"
adduser --quiet --disabled-password --comment 'Alice Adduser' alice
eq "adduser: exactly the desktop groups" "$(groups_of alice)" "$(expect alice)"
no_forbidden alice && ok "adduser: no root-equivalent group" || bad "adduser: no root-equivalent group"

echo "== way 2: System Settings (AccountsService) standard account"
busctl_call CreateUser ssi bob 'Bob Settings' 0 >/dev/null
eq "AccountsService standard: exactly the desktop groups" "$(groups_of bob)" "$(expect bob)"
no_forbidden bob && ok "AccountsService standard: no root-equivalent group" || bad "AccountsService standard: no root-equivalent group"

echo "== way 2b: System Settings administrator account, and switching type"
busctl_call CreateUser ssi carol 'Carol Admin' 1 >/dev/null
eq "AccountsService administrator: desktop groups plus sudo" "$(groups_of carol)" "$(expect carol sudo)"
CAROL_PATH=$(busctl_call FindUserByName s carol | awk '{print $2}' | tr -d '"')
busctl --system call org.freedesktop.Accounts "$CAROL_PATH" org.freedesktop.Accounts.User SetAccountType i 0 >/dev/null
eq "administrator turned standard keeps the desktop groups" "$(groups_of carol)" "$(expect carol)"
busctl --system call org.freedesktop.Accounts "$CAROL_PATH" org.freedesktop.Accounts.User SetAccountType i 1 >/dev/null
eq "standard turned administrator keeps the desktop groups" "$(groups_of carol)" "$(expect carol sudo)"

echo "== way 3: the installer (Calamares users module)"
CAL=/etc/calamares/modules/users.conf
[[ -f $CAL ]] && ok "installer file written" || bad "installer file written"
head -1 "$CAL"
eq "the shipped Calamares file is untouched" "$(sha256sum /usr/share/calamares/modules/users.conf | cut -d' ' -f1)" "$CAL_SHIPPED_SUM"
python3 -c 'import yaml;yaml.safe_load(open("'"$CAL"'"))' && ok "installer file is valid YAML" || bad "installer file is valid YAML"
# Calamares' own steps (users/MiscJobs.cpp ensureGroupsExistInTarget, CreateUserJob.cpp):
#   groupadd [--system] for each missing group; useradd -m -U -s SHELL -c NAME LOGIN; usermod -aG GROUPS LOGIN
cal_install_user() {
	local conf=$1 login=$2 groups="" g
	while IFS=$'\t' read -r name system must; do
		if ! getent group "$name" >/dev/null; then
			[[ $must == True ]] && { echo "must_exist group missing: $name"; return 1; }
			if [[ $system == True ]]; then groupadd --system "$name"; else groupadd "$name"; fi
		fi
		groups="$groups,$name"
	done < <(python3 - "$conf" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for g in d["defaultGroups"]:
    if isinstance(g, str):
        print(g, False, False, sep="\t")
    else:
        print(g["name"], g.get("system", False), g.get("must_exist", False), sep="\t")
PY
)
	useradd -m -U -s /bin/bash -c "Dave Installer" "$login"
	usermod -aG "${groups#,}" "$login"
}
PAWEL=$(python3 - /usr/share/calamares/modules/users.conf <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print(" ".join(g if isinstance(g, str) else g["name"] for g in d["defaultGroups"]))
PY
)
cal_install_user "$CAL" dave && ok "installer steps run" || bad "installer steps run"
eq "installer: Paweł's groups plus the desktop groups, exactly" "$(groups_of dave)" "$(expect dave $PAWEL)"
cal_install_user /usr/share/calamares/modules/users.conf olddave
eq "control: without the package the installer user lacks games" "$(groups_of olddave | tr ' ' '\n' | grep -cx games)" "0"
userdel -r olddave 2>/dev/null

echo "== Calamares itself reads the file"
su zed -s /bin/bash -c 'export HOME=/tmp QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=/tmp; timeout 20 calamares -d 2>&1' >/tmp/cal-good.log
cp "$CAL" /tmp/cal.keep; printf 'defaultGroups: [ unclosed\n  - : :\n' >"$CAL"
su zed -s /bin/bash -c 'export HOME=/tmp QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR=/tmp; timeout 20 calamares -d 2>&1' >/tmp/cal-broken.log
cp /tmp/cal.keep "$CAL"
GOOD=$(grep -c -i -E 'yaml|users.conf.*(error|invalid)|bad file|Parse' /tmp/cal-good.log)
BROKEN=$(grep -c -i -E 'yaml|users.conf.*(error|invalid)|bad file|Parse' /tmp/cal-broken.log)
echo "log lines naming a YAML/parse problem: good=$GOOD broken=$BROKEN"
(( BROKEN > GOOD )) && ok "Calamares reads /etc/calamares/modules/users.conf (a broken one is noticed)" || bad "Calamares reads /etc/calamares/modules/users.conf"

echo "== SSH login of the adduser user"
mkdir -p /home/alice/.ssh; ssh-keygen -q -t ed25519 -N '' -f /tmp/id_test; cp /tmp/id_test.pub /home/alice/.ssh/authorized_keys
chown -R alice:alice /home/alice/.ssh; chmod 700 /home/alice/.ssh; chmod 600 /home/alice/.ssh/authorized_keys
SSHG=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -i /tmp/id_test alice@127.0.0.1 'id -nG' 2>/dev/null | tr ' ' '\n' | sort | paste -sd' ')
eq "SSH login has the account's groups (membership is the account's, not the seat's)" "$SSHG" "$(expect alice)"

echo "== apply is idempotent, the list is the single source"
sparky-stereo-user-groups apply
S1=$(sha256sum /etc/adduser.conf "$CAL" | md5sum)
sparky-stereo-user-groups apply
S2=$(sha256sum /etc/adduser.conf "$CAL" | md5sum)
eq "second apply changes nothing" "$S1" "$S2"
eq "one managed block in adduser.conf" "$(grep -c 'BEGIN sparky-stereo-user-groups' /etc/adduser.conf)" "1"

echo "== trigger: a new shipped Calamares file is picked up"
sed -i 's/^    - lp$/    - lp\n    - sparkycanary/' /usr/share/calamares/modules/users.conf
dpkg-trigger --by-package=calamares /usr/share/calamares/modules >/dev/null 2>&1
dpkg --configure --pending >/dev/null 2>&1
grep -q sparkycanary "$CAL" && ok "trigger regenerates the installer file" || bad "trigger regenerates the installer file"
grep -q 'name: games' "$CAL" && ok "and keeps the desktop groups" || bad "and keeps the desktop groups"

echo "== a users.conf of the administrator's own is left alone"
cp "$CAL" /tmp/cal.generated; echo '# mine' >"$CAL"
sparky-stereo-user-groups apply 2>&1 | grep -q 'is yours' && ok "own installer file reported" || bad "own installer file reported"
eq "own installer file untouched" "$(cat "$CAL")" "# mine"
cp /tmp/cal.generated "$CAL"

echo "== control: docker planted in the list"
cp /etc/sparky-stereo/user-groups /tmp/list.keep
SUM=$(sha256sum /etc/adduser.conf "$CAL" | md5sum)
echo docker >>/etc/sparky-stereo/user-groups
if sparky-stereo-user-groups apply 2>/tmp/refuse.txt; then bad "control: apply refuses docker"; else ok "control: apply refuses docker ($(cat /tmp/refuse.txt))"; fi
if sparky-stereo-user-groups check 2>/dev/null; then bad "control: check refuses docker"; else ok "control: check refuses docker"; fi
eq "control: nothing was written" "$(sha256sum /etc/adduser.conf "$CAL" | md5sum)" "$SUM"
for g in disk input shadow sudo wheel staff adm; do
	cp /tmp/list.keep /etc/sparky-stereo/user-groups; echo "$g" >>/etc/sparky-stereo/user-groups
	sparky-stereo-user-groups check 2>/dev/null && bad "control: $g refused" || ok "control: $g refused"
done
cp /tmp/list.keep /etc/sparky-stereo/user-groups

echo "== control: docker planted straight into adduser.conf (bypassing the helper) must be caught by the checks"
cp /etc/adduser.conf /tmp/adduser.keep
groupadd docker
sed -i 's/^EXTRA_GROUPS="/EXTRA_GROUPS="docker /' /etc/adduser.conf
adduser --quiet --disabled-password --comment 'Eve Planted' eve
IN_DOCKER=$(groups_of eve | tr ' ' '\n' | grep -cx docker)
eq "control: the planted group did reach the new user" "$IN_DOCKER" "1"
no_forbidden eve >/dev/null && bad "control: the root-equivalent check catches docker" || ok "control: the root-equivalent check catches docker"
[[ $(groups_of eve) == "$(expect eve)" ]] && bad "control: the exactness check catches docker" || ok "control: the exactness check catches docker"
cp /tmp/adduser.keep /etc/adduser.conf

echo "== remove puts everything back"
dpkg -r sparky-stereo-user-groups >/dev/null 2>&1
eq "adduser.conf as before the package" "$(sha256sum /etc/adduser.conf | cut -d' ' -f1)" "$ADDUSER_SUM_BEFORE"
[[ -e $CAL ]] && bad "installer file removed" || ok "installer file removed"
adduser --quiet --disabled-password --comment 'Fay After' fay
eq "after removal a new user is back to adduser's default" "$(groups_of fay)" "$(set_of fay users)"

echo
if ((FAIL)); then echo "RESULT: $FAIL failed"; exit 1; fi
echo "RESULT: all passed"
