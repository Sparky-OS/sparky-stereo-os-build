#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# In a container where the ollama package was just installed (root): nothing is enabled and nothing listens.
# Exit 0 when every check passes. The red control is unit-default-red.sh: the same unit with debhelper's default.
set -u
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
state=$(systemctl --global is-enabled ollama.service 2>&1)
echo "systemctl --global is-enabled ollama.service: $state"
check 'the user service is installed' '[ -f /usr/lib/systemd/user/ollama.service ]'
check 'the user service is not enabled for anyone' '[ "$state" = disabled ]'
check 'no enablement link under /etc/systemd/user' '! find /etc/systemd/user -name ollama.service 2>/dev/null | grep -q .'
check 'the maintainer scripts enable no user unit' '! grep -q "deb-systemd-helper --user enable" /var/lib/dpkg/info/ollama.postinst 2>/dev/null'
listeners=$(ss -Htlnp 2>/dev/null)
echo "ss -tlnp: ${listeners:-(nothing listens)}"
check 'nothing listens' '[ -z "$listeners" ]'
check 'no ollama process' '! ps -eo comm | grep -qx ollama'
exit $fail
