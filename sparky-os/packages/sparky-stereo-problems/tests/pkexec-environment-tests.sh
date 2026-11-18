#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# Root, disposable systemd/polkit container. Probes the real script path and trusted PAM environment additions.
set -eu
mkdir -p /opt/pe661-environment
cat >/opt/pe661-environment/probe <<'EOS'
#!/bin/sh
exec /usr/bin/python3 -c 'import os,json; keys="HOME USER LOGNAME PATH SHELL LANG LANGUAGE TERM PKEXEC_UID SUDO_UID SUDO_GID DISPLAY XAUTHORITY XDG_STATE_HOME SPARKY_STEREO_ROOT SPARKY_STEREO_PROBLEMS_CATALOG SPARKY_STEREO_PROBLEMS_JOURNAL PE661_CALLER PE661_PAM DBUS_SYSTEM_BUS_ADDRESS".split(); print(json.dumps({k:os.environ[k] for k in keys if k in os.environ},sort_keys=True))'
EOS
chmod 755 /opt/pe661-environment/probe
ln -sf /opt/pe661-environment/probe /opt/pe661-environment/alias
cat >/usr/share/polkit-1/actions/org.sparkylinux.test.pe661.policy <<'EOS'
<?xml version="1.0" encoding="UTF-8"?>
<policyconfig><action id="org.sparkylinux.test.pe661.probe"><description>Isolated environment probe</description><message>Isolated environment probe</message><defaults><allow_any>no</allow_any><allow_inactive>no</allow_inactive><allow_active>no</allow_active></defaults><annotate key="org.freedesktop.policykit.exec.path">/opt/pe661-environment/probe</annotate></action></policyconfig>
EOS
cat >/etc/polkit-1/rules.d/00-pe661.rules <<'EOS'
polkit.addRule(function(action, subject) {
    if (subject.user == "person") {
        if (action.id == "org.sparkylinux.test.pe661.probe" || action.id == "org.sparkylinux.sparkystereo.problems.repair") return polkit.Result.YES;
        if (action.id == "org.freedesktop.policykit.exec") return polkit.Result.NO;
    }
});
EOS
cat >/opt/pe661-environment/pam.env <<'EOS'
PE661_PAM=from-pam
SPARKY_STEREO_ROOT=/opt/pe661-auth/decoy
SPARKY_STEREO_PROBLEMS_CATALOG=/opt/pe661-auth/decoy
SPARKY_STEREO_PROBLEMS_JOURNAL=/opt/pe661-auth/decoy
XDG_STATE_HOME=/opt/pe661-auth/decoy
EOS
printf 'auth required pam_permit.so\naccount required pam_permit.so\nsession required pam_env.so envfile=/opt/pe661-environment/pam.env readenv=1 user_readenv=0\n' >/etc/pam.d/polkit-1
systemctl restart polkit
for name in probe alias; do
    runuser -u person -- env LANG=C.UTF-8 LANGUAGE=de SHELL=/bin/bash TERM=vt100 HOME=/caller XDG_STATE_HOME=/caller SPARKY_STEREO_ROOT=/caller SPARKY_STEREO_PROBLEMS_CATALOG=/caller SPARKY_STEREO_PROBLEMS_JOURNAL=/caller PE661_CALLER=must-not-survive DISPLAY=:661 XAUTHORITY=/caller/auth DBUS_SYSTEM_BUS_ADDRESS=unix:path=/caller/bus pkexec --disable-internal-agent /opt/pe661-environment/$name > /opt/pe661-environment/$name.json
    python3 - "$name" <<'PY'
import json,sys
p='/opt/pe661-environment/'+sys.argv[1]+'.json'
d=json.load(open(p)); print(json.dumps(d,sort_keys=True))
assert d['HOME']=='/root' and d['USER']=='root' and d['LOGNAME']=='root'
assert d['LANG']=='C.UTF-8' and d['LANGUAGE']=='de' and d['TERM']=='vt100'
assert all(k not in d for k in ['DISPLAY','XAUTHORITY','PE661_CALLER','DBUS_SYSTEM_BUS_ADDRESS'])
assert d['PE661_PAM']=='from-pam'
assert all(d[k]=='/opt/pe661-auth/decoy' for k in ['SPARKY_STEREO_ROOT','SPARKY_STEREO_PROBLEMS_CATALOG','SPARKY_STEREO_PROBLEMS_JOURNAL','XDG_STATE_HOME'])
print('PASS  canonical script action matches '+sys.argv[1]+'; caller overrides stripped, trusted PAM additions present')
PY
done
# The decoy's root-kept repair exists only under the PAM-supplied override, not in the real machine store.
rm -f /run/pe661-decoy-ran
set +e
runuser -u person -- pkexec --disable-internal-agent /usr/libexec/sparky-stereo-problems/pkexec-repair repair --machine sparky-stereo-problems decoy
r=$?
set -e
[ "$r" = 1 ] && [ ! -e /run/pe661-decoy-ran ]
echo 'PASS  even PAM-added store overrides cannot supply the helper a repair'
# Restore the synthetic authentication-only stack for the other isolated tests.
printf 'auth required pam_permit.so\naccount required pam_permit.so\nsession required pam_permit.so\n' >/etc/pam.d/polkit-1
