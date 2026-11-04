#!/bin/sh
# ORDER 400b: the check on this repository, then the check's own tests. Exit 0 only when both pass.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
python3 -I "$here/check.py"
python3 -I "$here/test_check.py"
