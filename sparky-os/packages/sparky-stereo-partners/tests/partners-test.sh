#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The Partners page's command as a person meets it, run as root for the account USER in a container booted with systemd
# (a real user manager, a real system bus), with sparky-stereo-partners, sparky-stereo-graphics and the engine installed and
# no network: the engine on and off through systemctl --user, its address taken by another program, the card that cannot be
# used, the model list with sizes from a stand-in registry, a download held on a metered connection (a stand-in
# NetworkManager answers Metered on the system bus), a download from the stand-in registry (a few kilobytes, not a model),
# the registry gone, a provider and a program's own choice, and who answers; llama.cpp, the other local engine (Debian's
# llama-server installed in the rig, started empty); signing in to Ollama's service through the real engine against a
# stand-in of ollama.com over TLS with its own certificate authority. No model is pulled, loaded or run.
# Usage: partners-test.sh USER   (this folder holds standin-registry.py, fake-networkmanager.py and standin-ollama-com.py)
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
as() { runuser -u "$user" -- env PIDFILE=/tmp/partners-squat.pid XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus LANG=${LANG:-C.UTF-8} "$@"; }
cmd() { as sparky-stereo-partners "$@" >"$T/out" 2>"$T/err"; echo $?; }
json() { as sparky-stereo-partners status --json | python3 -I -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
listeners() { ss -Htln | awk '{print $4}' | grep -cx '127.0.0.1:11434'; }
llisteners() { ss -Htln | awk '{print $4}' | grep -c ':8080$'; }

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
# ollama.com, as the engine reaches it: a name in /etc/hosts, a certificate from a certificate authority of the test's own
# (trusted before the engine starts), the stand-in on 127.0.0.4:443; and a browser that only writes down what it was asked
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=Partners test authority" -keyout "$T/ca.key" -out "$T/ca.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=ollama.com" -keyout "$T/com.key" -out "$T/com.csr" 2>/dev/null
printf 'subjectAltName=DNS:ollama.com\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' >"$T/ext"
openssl x509 -req -in "$T/com.csr" -CA "$T/ca.crt" -CAkey "$T/ca.key" -CAcreateserial -days 2 -extfile "$T/ext" -out "$T/com.crt" 2>/dev/null
cp "$T/ca.crt" /usr/local/share/ca-certificates/partners-test-authority.crt && update-ca-certificates >/dev/null 2>&1
cp /etc/hosts "$T/hosts" && echo '127.0.0.4 ollama.com' >>/etc/hosts
python3 "$here/standin-ollama-com.py" "$T/com.crt" "$T/com.key" "$T/account" "$T/com.log" >"$T/com.out" 2>"$T/com.err" & com=$!
printf '#!/bin/sh\necho "$1" >> /tmp/partners-browser.log\n' >/usr/local/bin/xdg-open && chmod 755 /usr/local/bin/xdg-open
rm -f /tmp/partners-browser.log
for _ in $(seq 1 40); do grep -q ready "$T/com.out" && break; sleep 0.25; done
trap 'kill $nm $reg $com 2>/dev/null; rm -f /etc/dbus-1/system.d/zz-standin-nm.conf /usr/local/bin/xdg-open /usr/local/share/ca-certificates/partners-test-authority.crt; update-ca-certificates --fresh >/dev/null 2>&1; cp "$T/hosts" /etc/hosts; rm -rf "$T"' EXIT

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
as python3 -c 'import os,socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 11434)); s.listen(); open(os.environ["PIDFILE"], "w").write(str(os.getpid())); time.sleep(120)' & squat=$!
for _ in $(seq 1 20); do [ "$(listeners)" = 1 ] && break; sleep 0.25; done
check "engine on: exit 6" "$(cmd engine on)" 6
has "engine on: said, with the other program" "$T/err" "Another program already uses Ollama's address, 127.0.0.1:11434 (python3, pid"
check "engine on: the engine was not started" "$(as systemctl --user is-active ollama.service)" inactive
check "kept by the problems engine" "$(as sparky-stereo-problems list --json sparky-stereo-partners | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "['engine']"
kill "$(cat /tmp/partners-squat.pid)"; wait $squat 2>/dev/null   # the program itself, not runuser in front of it
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
check "not known, Download anyway: exit 0" "$(cmd download standin:tiny --even-if-metered)" 0; cat "$T/err" | head -3
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
check "resolve text: the interface's protocol, for KDE's text add-ons" "$(grep '^PARTNER_KIND=' "$T/out")" "PARTNER_KIND=ollama"
check "resolve text: the interface's name" "$(grep '^PARTNER_NAME=' "$T/out")" "PARTNER_NAME=Ollama on this computer"

check "resolve text: the card's variables" "$(grep -c -E '^(CUDA_VISIBLE_DEVICES|HIP_VISIBLE_DEVICES)=' "$T/out")" 2

echo "== a provider, and a program's own choice"
check "a provider with an http address: refused (exit 2)" "$(cmd provider add acme --name Acme --url http://api.example.invalid)" 2
check "a provider without a key: exit 0" "$(as sparky-stereo-partners provider add acme --name Acme --url https://api.example.invalid </dev/null >/dev/null 2>&1; echo $?)" 0
check "providers: listed" "$(as sparky-stereo-partners provider list)" "provider-acme	Acme	https://api.example.invalid"
check "KMail's own choice: exit 0" "$(cmd program org.kde.kmail2 text own --interface provider-acme)" 0
check "KMail resolves to the provider" "$(cmd resolve --kind text --program org.kde.kmail2; grep -E '^PARTNER_(URL|RUNS)=' "$T/out" | tr '\n' ' ')" "0
PARTNER_URL=https://api.example.invalid PARTNER_RUNS=provider "
check "Kontact and the Sieve editor take KMail's choice" "$(as sparky-stereo-partners resolve --kind text --program org.kde.kontact 2>/dev/null | grep '^PARTNER_URL='; as sparky-stereo-partners resolve --kind text --program org.kde.sieveeditor 2>/dev/null | grep '^PARTNER_URL=')" "PARTNER_URL=https://api.example.invalid
PARTNER_URL=https://api.example.invalid"
check "the page's KMail row knows the add-ons cannot follow a provider" "$(json "[c['protocol'] for p in d['programs'] if p['id']=='org.kde.kmail2' for c in p['choices']]")" "['openai-compatible']"
check "the default is untouched" "$(as sparky-stereo-partners resolve --kind text 2>/dev/null | grep '^PARTNER_URL=')" "PARTNER_URL=http://127.0.0.1:11434"
check "KMail follows the default again" "$(cmd program org.kde.kmail2 text follow; as sparky-stereo-partners resolve --kind text --program org.kde.kmail2 2>/dev/null | grep '^PARTNER_URL=')" "0
PARTNER_URL=http://127.0.0.1:11434"

echo "== Betterbird's ThunderAI: the person's managed-storage manifest follows the text choice"
manifest="$home/.mozilla/managed-storage/thunderai@micz.it.json"
check "Betterbird not installed: sync writes nothing" "$(cmd sync; [ -e "$manifest" ] && echo there || echo absent)" "0
absent"
mkdir -p /opt/betterbird && printf '#!/bin/sh\n' >/opt/betterbird/betterbird && chmod 755 /opt/betterbird/betterbird
check "Betterbird installed: sync writes the manifest" "$(cmd sync; [ -e "$manifest" ] && echo there || echo absent)" "0
there"
check "the manifest: ThunderAI's own keys for Ollama, unlocked, no key" "$(python3 -I -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["name"], m["type"], json.dumps(m["data"], sort_keys=True))' "$manifest")" 'thunderai@micz.it storage {"connection_type": "ollama_api", "ollama_host": "http://127.0.0.1:11434", "ollama_model": "standin:tiny"}'
check "text on llama.cpp: the manifest follows at once" "$(cmd set-default text --interface llamacpp-local; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"]; print(d["connection_type"], d["openai_comp_host"], d["openai_comp_use_v1"])' "$manifest")" "0
openai_comp_api http://127.0.0.1:8080 True"
check "Betterbird's own choice, a provider: no key in the file" "$(cmd program eu.betterbird.Betterbird text own --interface provider-acme; python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1]))["data"]; print(d["openai_comp_host"], [k for k in d if "key" in k])' "$manifest")" "0
https://api.example.invalid []"
cmd program eu.betterbird.Betterbird text follow >/dev/null; cmd set-default text --interface ollama-local >/dev/null
rm -rf /opt/betterbird
check "Betterbird removed: sync takes our manifest away" "$(cmd sync; [ -e "$manifest" ] && echo there || echo absent)" "0
absent"
check "the plain status is for people, in their language" "$(LANGUAGE=pt_BR as sparky-stereo-partners status | grep -c '^Placa: ')" 1

echo "== the card that cannot be used"
check "card: a card that is not here (exit 0: the choice is saved, as on the Graphics page)" "$(cmd card pci-0000:42:00.0)" 0
check "the engine restarted on it: exit 4" "$(cmd engine off; cmd engine on)" "0
4"
has "said" "$T/err" "the card chosen for partners cannot be used now"
check "the Graphics package keeps it" "$(as sparky-stereo-problems list --json sparky-stereo-graphics | python3 -I -c 'import json,sys; print([p["key"] for p in json.load(sys.stdin)])')" "['partners']"
check "card: Automatic again, the engine starts" "$(cmd card auto; cmd engine on)" "0
0"

echo "== Ollama's service: signing in, through the engine, to the stand-in of ollama.com"
check "the engine on" "$(cmd engine on)" 0
check "account: not signed in (exit 7)" "$(cmd account --json)" 7
check "account: the connect page for this computer's name" "$(python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1])); print(a["state"], a["url"].split("&")[0])' "$T/out")" "signed-out https://ollama.com/connect?name=$(hostname)"
check "account: the key in it is Ollama's public key for this computer" "$(python3 -I -c 'import base64,json,sys,urllib.parse; a=json.load(open(sys.argv[1])); k=urllib.parse.parse_qs(urllib.parse.urlsplit(a["url"]).query)["key"][0]; print(base64.urlsafe_b64decode(k + "=" * (-len(k) % 4)).decode() == " ".join(open(sys.argv[2]).read().split()[:2]))' "$T/out" "$home/.ollama/id_ed25519.pub")" True
has "account: the engine asked ollama.com with its signature" "$T/com.log" "POST /api/me auth=yes"
check "sign in: exit 7, the next step said" "$(cmd signin)" 7
has "sign in: the words" "$T/out" "Finish signing in on ollama.com in your browser, then choose Check."
sleep 1
check "sign in: the browser was asked for the connect page" "$(cut -d'&' -f1 /tmp/partners-browser.log)" "https://ollama.com/connect?name=$(hostname)"
echo linked >"$T/account"
check "after the person linked it: signed in (exit 0)" "$(cmd account)" 0
check "after the person linked it: the account" "$(cat "$T/out")" "signed-in	tester"
check "sign out: exit 0" "$(cmd signout)" 0
has "sign out: the engine unlinked its key at ollama.com" "$T/com.log" "DELETE /api/user/keys/"
check "after signing out: not signed in" "$(cmd account)" 7
kill $com; wait $com 2>/dev/null
check "the service unreachable: exit 3" "$(cmd account --json)" 3
check "the service unreachable: said" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$T/out")" unavailable
has "the service unreachable: the words" "$T/err" "Ollama's service could not be reached:"
cmd engine off >/dev/null
check "the engine off: exit 3" "$(cmd account --json)" 3
check "the engine off: said" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$T/out")" off

echo "== llama.cpp, the other local engine (Debian's llama-server, started empty)"
check "status: installed, off" "$(json "(bool(d['llamacpp']['installed']), d['llamacpp']['on'])")" "(True, False)"
check "its service is installed off" "$(as systemctl --user is-enabled sparky-stereo-llama-server.service) $(systemctl --global is-enabled sparky-stereo-llama-server.service)" "disabled disabled"
check "nothing listens on its address" "$(llisteners)" 0
as mkdir -p "$home/.local/share/llama.cpp/models"
as sh -c "head -c 4096 /dev/zero > '$home/.local/share/llama.cpp/models/tiny-file.gguf'"
check "off: the folder's model files are listed, with their size" "$(json "[(m['name'], m['size']) for m in d['llamacpp']['models']]")" "[('tiny-file', 4096)]"
as rm "$home/.local/share/llama.cpp/models/tiny-file.gguf"
check "on: exit 0" "$(cmd engine on --engine llamacpp)" 0
check "on: active" "$(as systemctl --user is-active sparky-stereo-llama-server.service)" active
check "on: it listens on 127.0.0.1:8080 only" "$(llisteners) $(ss -Htln | awk '{print $4}' | grep -cx '127.0.0.1:8080')" "1 1"
check "on: its own health and model list answer" "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health) $(curl -s http://127.0.0.1:8080/v1/models | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["data"])')" "200 []"
check "on: a web page of another origin gets no permission to read it" "$(curl -s -D - -o /dev/null -H 'Origin: https://example.com' http://127.0.0.1:8080/v1/models | grep -ci '^access-control-allow-origin: https://example.com')" 0
check "on: a page of this computer does" "$(curl -s -D - -o /dev/null -H 'Origin: http://localhost:3000' http://127.0.0.1:8080/v1/models | grep -ci '^access-control-allow-origin: http://localhost:3000')" 1
check "on: offline, as its unit says" "$(as systemctl --user show -p ExecStart sparky-stereo-llama-server.service | grep -c -- '--offline')" 1
check "status: on" "$(json "d['llamacpp']['on']")" True
check "text on llama.cpp: exit 0" "$(cmd set-default text --interface llamacpp-local)" 0
check "text on llama.cpp: who answers" "$(cmd resolve --kind text; grep -E '^PARTNER_(KIND|URL|RUNS)=' "$T/out" | tr '\n' ' ')" "0
PARTNER_KIND=openai-compatible PARTNER_URL=http://127.0.0.1:8080/v1 PARTNER_RUNS=here "
check "text back on Ollama" "$(cmd set-default text --interface ollama-local)" 0
check "off: exit 0" "$(cmd engine off --engine llamacpp)" 0
check "off: nothing listens on its address" "$(llisteners)" 0
check "its install plan names Debian's llama-server and the Vulkan back end" "$(/usr/libexec/sparky-stereo-partners/install-engine plan llamacpp | grep '^packages')" "packages	llama.cpp-tools libggml0-backend-vulkan"
check "an engine the command does not know: refused (exit 2)" "$(cmd engine on --engine other)" 2
echo "partners: $pass passed, $fail failed"
[ "$fail" = 0 ]
