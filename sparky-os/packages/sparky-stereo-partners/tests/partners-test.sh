#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The Partners page's command as a person meets it, run as root for the account USER in a container booted with systemd
# (a real user manager, a real system bus), with sparky-stereo-partners, sparky-stereo-graphics and the engine installed and
# no network: the engine on and off through systemctl --user, its address taken by another program, the card that cannot be
# used, the model list with sizes from a stand-in registry, a download held on a metered connection (a stand-in
# NetworkManager answers Metered on the system bus), a download from the stand-in registry (a few kilobytes, not a model),
# the registry gone, a provider and a program's own choice, and who answers. No model is pulled, loaded or run.
# Usage: partners-test.sh USER   (this folder holds standin-registry.py and fake-networkmanager.py)
set -u
user=$1
here=$(cd "$(dirname "$0")" && pwd)
uid=$(id -u "$user")
home=$(getent passwd "$user" | cut -d: -f6)
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
has() { if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 500 "$2")"; fi; }
systemctl start "user@$uid.service" || { echo "FAIL the user manager did not start"; exit 1; }
T=$(mktemp -d); chmod 755 "$T"
as() { runuser -u "$user" -- env XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus LANG=${LANG:-C.UTF-8} "$@"; }
cmd() { as sparky-stereo-partners "$@" >"$T/out" 2>"$T/err"; echo $?; }
json() { as sparky-stereo-partners status --json | python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
listeners() { ss -Htln | awk '{print $4}' | grep -cx '127.0.0.1:11434'; }

# the stand-in NetworkManager on the real system bus, and the stand-in registry
printf '<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">\n<busconfig><policy user="root"><allow own="org.freedesktop.NetworkManager"/></policy><policy context="default"><allow send_destination="org.freedesktop.NetworkManager"/></policy></busconfig>\n' >/etc/dbus-1/system.d/zz-standin-nm.conf
busctl call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null
echo 2 >/run/fake-nm-metered
python3 "$here/fake-networkmanager.py" & nm=$!
python3 "$here/standin-registry.py" 5005 >"$T/registry" 2>"$T/registry.log" & reg=$!
for _ in $(seq 1 40); do grep -q ready "$T/registry" && busctl --system get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager Metered >/dev/null 2>&1 && break; sleep 0.25; done
size=$(awk '/ready/{print $2}' "$T/registry")
as mkdir -p "$home/.config"
as sh -c "printf '[Models]\nRegistry=http://127.0.0.1:5005\nText=standin:tiny\n' > '$home/.config/sparky-stereo-partnersrc'"
trap 'kill $nm $reg 2>/dev/null; rm -f /etc/dbus-1/system.d/zz-standin-nm.conf; rm -rf "$T"' EXIT

echo "== before anything: the engine installed and off, nothing listens, no model chosen"
check "status: the engine is installed" "$(json "bool(d['engine']['installed'])")" True
check "status: the engine is off" "$(json "d['engine']['on']")" False
check "status: text is Ollama on this computer, with no model" "$(json "[(x['interface'], x['model']) for x in d['defaults'] if x['kind']=='text'][0]")" "('ollama-local', '')"
check "nothing listens" "$(listeners)" 0
check "resolve before a model is chosen: says so (exit 1)" "$(cmd resolve --kind text)" 1
has "resolve before a model is chosen: the words" "$T/err" "No model is chosen yet. Choose one in System Settings, Partners."

echo "== the engine on and off, through the user manager"
check "engine on: exit 0" "$(cmd engine on)" 0
check "engine on: enabled" "$(as systemctl --user is-enabled ollama.service)" enabled
check "engine on: active" "$(as systemctl --user is-active ollama.service)" active
check "engine on: it listens on 127.0.0.1:11434 only" "$(ss -Htln | awk '{print $4}' | grep -c ':11434$') $(listeners)" "1 1"
check "status: on" "$(json "d['engine']['on']")" True
check "engine off: exit 0" "$(cmd engine off)" 0
check "engine off: disabled" "$(as systemctl --user is-enabled ollama.service)" disabled
check "engine off: nothing listens" "$(listeners)" 0

echo "== its address taken by another program"
as python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 11434)); s.listen(); time.sleep(60)' & squat=$!
for _ in $(seq 1 20); do [ "$(listeners)" = 1 ] && break; sleep 0.25; done
check "engine on: exit 6" "$(cmd engine on)" 6
has "engine on: said, with the other program" "$T/err" "Another program already uses Ollama's address, 127.0.0.1:11434 (python3, pid"
check "engine on: the engine was not started" "$(as systemctl --user is-active ollama.service)" inactive
check "kept by the problems engine" "$(as sparky-stereo-problems list --json sparky-stereo-partners | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "['engine']"
kill $squat; wait $squat 2>/dev/null
check "the address free again: engine on, exit 0" "$(cmd engine on)" 0
check "the address free again: the problem goes" "$(as sparky-stereo-problems list --json sparky-stereo-partners | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "[]"

echo "== the models the page offers, with sizes read from the registry before anything is fetched"
check "models: exit 0" "$(cmd models --json)" 0
check "models: the stand-in's size, as its manifest says" "$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1]))[0]; print(m["name"], m["size"])' "$T/out")" "standin:tiny $size"

echo "== a download on a metered connection, and when the state cannot be read"
echo 1 >/run/fake-nm-metered
check "metered: held (exit 5)" "$(cmd download standin:tiny)" 5
has "metered: said" "$T/err" "This connection is metered, so the download waits. It starts when you choose Download again on a connection that is not metered."
check "metered: nothing downloaded" "$(json "len(d['engine']['models'])")" 0
echo 0 >/run/fake-nm-metered
check "not known: held (exit 5)" "$(cmd download standin:tiny)" 5
has "not known: said, with why" "$T/err" "Whether this connection is metered could not be read (NetworkManager does not know (unknown)), so the download waits."
check "not known, Download anyway: exit 0" "$(cmd download standin:tiny --even-if-metered)" 0
check "the model is on this computer" "$(json "[m['name'] for m in d['engine']['models']]")" "['127.0.0.1:5005/library/standin:tiny']"
check "the default's model is written in the person's file only" "$(grep -c '^Model=standin:tiny$' "$home/.config/sparky-stereo-partnersrc") $(grep -c '^Model=' /etc/xdg/sparky-stereo-partnersrc)" "1 0"
echo 2 >/run/fake-nm-metered

echo "== the registry gone"
kill $reg; wait $reg 2>/dev/null
check "registry gone: exit 3" "$(cmd download standin:tiny)" 3
has "registry gone: said with its cause" "$T/err" "The model standin:tiny could not be downloaded:"
check "registry gone: kept" "$(as sparky-stereo-problems list --json sparky-stereo-partners | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "['download']"
check "registry gone: the page's model list says it" "$(cmd models --json; python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1]))[0]; print(bool(m["error"]), m["size"])' "$T/out")" "3
True 0"

echo "== who answers"
check "resolve text: exit 0" "$(cmd resolve --kind text)" 0
check "resolve text: the engine's address and the model" "$(grep -E '^PARTNER_(URL|MODEL|RUNS)=' "$T/out" | tr '\n' ' ')" "PARTNER_URL=http://127.0.0.1:11434 PARTNER_MODEL=standin:tiny PARTNER_RUNS=here "
check "resolve text: the card's variables" "$(grep -c -E '^(CUDA_VISIBLE_DEVICES|HIP_VISIBLE_DEVICES)=' "$T/out")" 2

echo "== a provider, and a program's own choice"
check "a provider with an http address: refused (exit 2)" "$(cmd provider add acme --name Acme --url http://api.example.invalid)" 2
check "a provider without a key: exit 0" "$(as sparky-stereo-partners provider add acme --name Acme --url https://api.example.invalid </dev/null >/dev/null 2>&1; echo $?)" 0
check "providers: listed" "$(as sparky-stereo-partners provider list)" "provider-acme	Acme	https://api.example.invalid"
check "KMail's own choice: exit 0" "$(cmd program org.kde.kmail2 text own --interface provider-acme)" 0
check "KMail resolves to the provider" "$(cmd resolve --kind text --program org.kde.kmail2; grep -E '^PARTNER_(URL|RUNS)=' "$T/out" | tr '\n' ' ')" "0
PARTNER_URL=https://api.example.invalid PARTNER_RUNS=provider "
check "the default is untouched" "$(as sparky-stereo-partners resolve --kind text 2>/dev/null | grep '^PARTNER_URL=')" "PARTNER_URL=http://127.0.0.1:11434"
check "KMail follows the default again" "$(cmd program org.kde.kmail2 text follow; as sparky-stereo-partners resolve --kind text --program org.kde.kmail2 2>/dev/null | grep '^PARTNER_URL=')" "0
PARTNER_URL=http://127.0.0.1:11434"

echo "== the card that cannot be used"
check "card: a card that is not here (exit 0: the choice is saved, as on the Graphics page)" "$(cmd card pci-0000:42:00.0)" 0
check "the engine restarted on it: exit 4" "$(cmd engine off; cmd engine on)" "0
4"
has "said" "$T/err" "the card chosen for partners cannot be used now"
check "the Graphics package keeps it" "$(as sparky-stereo-problems list --json sparky-stereo-graphics | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "['partners']"
check "card: Automatic again, the engine starts" "$(cmd card auto; cmd engine on)" "0
0"
cmd engine off >/dev/null
echo "partners: $pass passed, $fail failed"
[ "$fail" = 0 ]
