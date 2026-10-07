cd /work/tbuild
T=$(ninja -t targets all | grep -E '^plugins/(wayland|platforminputcontexts|generic|imageformats|platformthemes|platforms)[^ ]*\.so:' | cut -d: -f1 | tr '\n' ' ')
ninja -j4 $T > /work/tplug.log 2>&1; echo rc=$? >> /work/tplug.log
