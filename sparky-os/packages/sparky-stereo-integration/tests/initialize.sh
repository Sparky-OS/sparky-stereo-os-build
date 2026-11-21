#!/bin/bash
set -euo pipefail
runner=${1:?runner path}
recipe=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT
export HOME=$tmp/home XDG_DATA_HOME=$tmp/data XDG_STATE_HOME=$tmp/state
export SPARKY_STEREO_INTEGRATIONS_D=$tmp/packs SPARKY_STEREO_SERVICEMENUS=$tmp/menus
export SPARKY_STEREO_INTEGRATION_LANGDIR=$recipe/lang SPARKY_STEREO_INTEGRATION_UI=none
mkdir -p "$HOME" "$tmp/packs" "$tmp/bin" "$tmp/menus"
export PATH=$tmp/bin:$PATH
cat > "$tmp/init" <<'X'
#!/bin/bash
set -e
[ ! -e "$HOME/fail" ]
( set -o noclobber; echo seed > "$HOME/settings" ) 2>/dev/null || test -f "$HOME/settings"
X
chmod +x "$tmp/init"
printf 'program=order69-fixture\nworker=/bin/true\ninitialize=%s/init\nmenus=\n' "$tmp" > "$tmp/packs/fixture.conf"
"$runner" initialize
[ ! -e "$HOME/settings" ]
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/order69-fixture"
chmod +x "$tmp/bin/order69-fixture"
"$runner" sync
[ "$(cat "$HOME/settings")" = seed ]
printf 'person settings' > "$HOME/settings"
"$runner" initialize
[ "$(cat "$HOME/settings")" = 'person settings' ]
rm "$HOME/settings" "$tmp/packs/fixture.conf"
"$runner" initialize
[ ! -e "$HOME/settings" ]
printf 'program=order69-fixture\nworker=/bin/true\ninitialize=%s/init\nmenus=\n' "$tmp" > "$tmp/packs/fixture.conf"
touch "$HOME/fail"
if "$runner" initialize; then echo 'FAIL: initializer error was swallowed'; exit 1; fi
rm "$HOME/fail"
"$runner" initialize
[ "$(cat "$HOME/settings")" = seed ]
echo 'PASS: absent, later program, existing settings, removed pack, later pack, error and retry'
