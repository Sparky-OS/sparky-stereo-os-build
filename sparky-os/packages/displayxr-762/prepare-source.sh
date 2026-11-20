#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=f310f8f7b8f98b47f2d57c070c49fa379dc91c48
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0018-paired-headset-owner-name.patch debian/lang | tar -x -C "$overlay"
# Preserve the held source's Lean hooks and dependencies; extend only our catalog subject.
python3 - "$input/displayxr-runtime_2.66.3-1+stereo3d7+lc1.debian.tar.xz" "$overlay/debian" <<'PYCODE'
import pathlib,sys,tarfile
with tarfile.open(sys.argv[1]) as archive:
    changes = {
        'rules': ('--subject LOCAL1 --subject LOCAL7=LOCAL7,LOCAL8\n', '--subject LOCAL1 --subject LOCAL7=LOCAL7,LOCAL8,LOCAL9\n', 1),
    }
    for name,(before,after,count) in changes.items():
        text = archive.extractfile('debian/'+name).read().decode()
        assert text.count(before) == count, name
        target = pathlib.Path(sys.argv[2])/name
        target.write_text(text.replace(before,after))
        if name == 'rules': target.chmod(0o755)
PYCODE
printf '%s  %s\n' e6d54a6b048bbac3318a1f9414b23eb73f7e95d9a76b75e91900696b14a98204 "$input/displayxr-runtime_2.66.3-1+stereo3d7+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d8 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Name the live program holding the paired headset, retaining its PID and the PID-only explanation when its name cannot be read.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d7+lc1.dsc" "$out"
