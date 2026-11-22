#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
toolkit=$(cd "$here/../.." && pwd)
python3 - "$here/successor.json" "${1:?published source folder}" <<'CHECK'
import hashlib,json,sys
from pathlib import Path
m=json.loads(Path(sys.argv[1]).read_text())
p=Path(sys.argv[2])/m['published_descriptor']
assert hashlib.sha256(p.read_bytes()).hexdigest()==m['published_descriptor_sha256']
CHECK
exec python3 "$toolkit/repo/lc-successor.py" --in-place --next 5.0.1+dfsg-6+stereo3d4 --item 'Rebuild unchanged stereo source against current Debian testing library ABIs; the Blender 5.2 port remains separate.' --work "${3:?work folder}" "$1/blender_5.0.1+dfsg-6+stereo3d3+lc1.dsc" "${2:?output folder}"
