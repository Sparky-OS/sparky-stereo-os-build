#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=8f4a55a2bba72f3dcecb03f22235947a78e33b52
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0019-edition-stereo-declare-soname.patch debian/patches/0020-edition-window-depth-limits.patch debian/lang | tar -x -C "$overlay"
# Preserve the held source's Lean hooks and dependencies; extend only our catalog subject.
python3 - "$input/displayxr-runtime_2.66.3-1+stereo3d8+lc1.debian.tar.xz" "$overlay/debian" <<'PYCODE'
import pathlib,sys,tarfile
with tarfile.open(sys.argv[1]) as archive:
    changes = {
        'rules': ('--subject LOCAL7=LOCAL7,LOCAL8,LOCAL9\n', '--subject LOCAL7=LOCAL7,LOCAL8,LOCAL9 --subject LOCAL10=LOCAL10,LOCAL11\n', 1),
    }
    text = archive.extractfile('debian/control').read().decode()
    assert text.count(' libeigen3-dev,') == 1
    text = text.replace(' libeigen3-dev,', ' libeigen3-dev,\n libstereo-declare-dev (>= 1.12.1),')
    before = ' ${shlibs:Depends},\n sparky-stereo-problems'
    assert text.count(before) == 1
    text = text.replace(before, ' ${shlibs:Depends},\n libstereo-declare1 (>= 1.12.1),\n sparky-stereo-problems')
    (pathlib.Path(sys.argv[2])/'control').write_text(text)
    for name,(before,after,count) in changes.items():
        text = archive.extractfile('debian/'+name).read().decode()
        assert text.count(before) == count, name
        target = pathlib.Path(sys.argv[2])/name
        target.write_text(text.replace(before,after))
        if name == 'rules': target.chmod(0o755)
PYCODE
printf '%s  %s\n' 16b5a4a8d9b943f1a16f9bd8e985f12e81b64ac60ec88d8dac0b30a698e5e554 "$input/displayxr-runtime_2.66.3-1+stereo3d8+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d9 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Use final per-window KWin limits from libstereo-declare; remove edition depth overrides and integrate reviewed runtime translations.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d8+lc1.dsc" "$out"
