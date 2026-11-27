#!/bin/sh
# The recipe's tests; run them in a container (they run a program of the package). KNOB_OWNER=PATH tests an installed copy.
set -u
here=$(cd "$(dirname "$0")" && pwd)
status=0
for t in decide rule dropin tell catalogs; do
	echo "== $t"
	python3 "$here/$t.py" || status=1
done
exit $status
