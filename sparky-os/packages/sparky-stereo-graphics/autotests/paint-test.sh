#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ORDER 518, Paint windows: how a program made with Qt Widgets paints (the processor, the graphics card batched, the
# graphics card by Qt's OpenGL engine) by program, by kind and by the machine's measurement; what the launcher is handed
# (QT_WIDGETS_GPU_PAINT with the GPU's variables); what is said and kept when the way cannot be had, and what ends it.
# The three ways stay the person's choice (Daniel, 2026-11-12: "keep as a option"); nothing fails silently (Daniel,
# 2026-11-01). Black box against the built commands, so the same checks fail on the build before this (red).
# BIN: folder with sparky-stereo-gpu-env, sparky-stereo-gpu-record and makefixture. SRC: the package source.
set -u
BIN=${BIN:?}
SRC=${SRC:?}
T=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$T"; [ -z "${KEEP:-}" ] || echo "kept $T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
has() { if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 700 "$2")"; fi; }
for m in one a10 host; do "$BIN/makefixture" $m "$T/$m" || { echo "makefixture $m failed"; exit 1; }; done
mkdir -p "$T/empty"
export XDG_CONFIG_HOME=$T/config XDG_CONFIG_DIRS=$T/etc XDG_DATA_HOME=$T/data XDG_DATA_DIRS=$T/usr XDG_STATE_HOME=$T/state
export SPARKY_STEREO_POWER_PROFILE=balanced LANG=C.UTF-8 SPARKY_STEREO_QT_PAINT=1 PATH=$BIN:$PATH
unset LANGUAGE LC_ALL LC_MESSAGES WAYLAND_DISPLAY DISPLAY DRI_PRIME MESA_VK_DEVICE_SELECT VK_LOADER_DRIVERS_SELECT __NV_PRIME_RENDER_OFFLOAD QT_WIDGETS_GPU_PAINT
mkdir -p "$XDG_CONFIG_HOME" "$T/etc" "$T/usr/applications" "$T/data/applications"
printf '[Desktop Entry]\nType=Application\nName=Kate\nExec=true\nCategories=Qt;KDE;Utility;TextEditor;\n' >"$T/usr/applications/org.kde.kate.desktop"
printf '[Desktop Entry]\nType=Application\nName=Dolphin\nExec=true\nCategories=Qt;KDE;System;FileManager;\n' >"$T/usr/applications/org.kde.dolphin.desktop"
printf '[Desktop Entry]\nType=Application\nName=Browser\nExec=true\nCategories=Network;WebBrowser;\n' >"$T/usr/applications/browser.desktop"
RC=$XDG_CONFIG_HOME/sparky-stereo-graphicsrc
PROBLEMS=$XDG_STATE_HOME/sparky-stereo-problems
rec() { echo "$PROBLEMS/sparky-stereo-graphics_$1.json"; }
env_for() { SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 "$BIN/sparky-stereo-gpu-env" "${@:2}"; }
paint() { env_for "$@" 2>/dev/null | grep '^QT_WIDGETS_GPU_PAINT=' | tr '\n' ' '; }

# nothing chosen, nothing measured: the processor, as every Qt paints; nothing is handed over
check "default: no painting variable" "$(env_for host --app org.kde.kate.desktop | grep -c QT_WIDGETS)" 0
check "default: the way" "$(env_for host --app org.kde.kate.desktop --print paint)" cpu
check "default: the reason" "$(env_for host --app org.kde.kate.desktop --print paint-reason)" unmeasured
check "default, one GPU: no variable at all" "$(env_for one --app org.kde.kate.desktop | wc -l)" 0

# a kind's choice
printf '[Paint]\nOther=batch\n' >"$RC"
check "kind batched: the variable" "$(paint host --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=batch "
check "kind batched: the program is told whom to tell" "$(env_for host --app org.kde.kate.desktop | grep -c "^QT_WIDGETS_GPU_PAINT_TELL=$BIN/sparky-stereo-gpu-env$")" 1
check "kind batched: the reason" "$(env_for host --app org.kde.kate.desktop --print paint-reason)" choice
check "kind batched, one GPU: it paints there too" "$(paint one --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=batch "
check "kind batched: by category" "$(paint host --category other)" "QT_WIDGETS_GPU_PAINT=batch "
check "kind batched: another kind is not touched" "$(paint host --app browser.desktop)" ""
check "shell form" "$(env_for host --app org.kde.kate.desktop --shell | grep -c "^export QT_WIDGETS_GPU_PAINT='batch'$")" 1
check "only the painting's variables" "$(env_for host --app org.kde.kate.desktop --print paint-env | head -1)" "QT_WIDGETS_GPU_PAINT=batch"

# a program's own choice wins over its kind, either way
printf '[Paint]\nOther=batch\n\n[PaintPrograms]\norg.kde.kate.desktop=opengl\norg.kde.dolphin.desktop=cpu\n' >"$RC"
check "program: Qt's OpenGL engine" "$(paint host --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=opengl "
check "program: the reason" "$(env_for host --app org.kde.kate.desktop --print paint-reason)" program
check "program: the processor while its kind is batched" "$(paint host --app org.kde.dolphin.desktop)" ""
check "program: the processor, said as the way" "$(env_for host --app org.kde.dolphin.desktop --print paint)" cpu

# the GPU's own variables come first and are not changed (a browser on the performance profile, batched)
printf '[Paint]\nBrowsers=batch\n' >"$RC"
check "the GPU variables first, then the painting" "$(env_for host --app browser.desktop --profile performance | tr '\n' ' ' | cut -d' ' -f1,2,5)" "__GLX_VENDOR_LIBRARY_NAME=nvidia __NV_PRIME_RENDER_OFFLOAD=1 QT_WIDGETS_GPU_PAINT=batch"
rm -f "$RC"

# Automatic follows what was measured on this machine for that kind (the machine's record, [MeasuredPaint])
printf '[MeasuredPaint]\nOther=batch\nMeasurement=test\nOrigin=local\n' >"$T/etc/sparky-stereo-graphicsrc"
check "measured: batched" "$(paint host --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=batch "
check "measured: the reason" "$(env_for host --app org.kde.kate.desktop --print paint-reason)" measured
check "measured: a kind that was not measured stays on the processor" "$(paint host --app browser.desktop)" ""
printf '[Paint]\nOther=cpu\n' >"$RC"
check "the person's choice wins over the measurement" "$(paint host --app org.kde.kate.desktop)" ""
check "the person's choice: the reason" "$(env_for host --app org.kde.kate.desktop --print paint-reason)" choice
rm -f "$RC" "$T/etc/sparky-stereo-graphicsrc"

# QT_WIDGETS_GPU_PAINT set by hand in the session is the person's: kept, nothing printed over it
printf '[Paint]\nOther=batch\n' >"$RC"
check "set by hand: nothing printed" "$(QT_WIDGETS_GPU_PAINT=opengl env_for host --app org.kde.kate.desktop | grep -c QT_WIDGETS)" 0
check "set by hand: the reason" "$(QT_WIDGETS_GPU_PAINT=opengl env_for host --app org.kde.kate.desktop --print paint-reason)" session
check "set by hand: the way" "$(QT_WIDGETS_GPU_PAINT=opengl env_for host --app org.kde.kate.desktop --print paint)" opengl

# a way that cannot be had: said, kept, the program still starts (status 0) and paints on the processor
SPARKY_STEREO_QT_PAINT=0 env_for host --app org.kde.kate.desktop >"$T/out" 2>"$T/err"
check "a Qt without the painting: status 0" "$?" 0
check "a Qt without the painting: no variable" "$(grep -c QT_WIDGETS "$T/out")" 0
has "a Qt without the painting: said, with the program" "$T/err" "Painting on the graphics card cannot be used for Kate: the installed Qt cannot paint on the graphics card. The windows are painted on the processor."
has "a Qt without the painting: what to do" "$T/err" "Choose On the processor for it in System Settings, Graphics"
check "a Qt without the painting: kept" "$([ -f "$(rec paint-org.kde.kate)" ] && echo kept)" kept
check "a Qt without the painting: the way it says" "$(SPARKY_STEREO_QT_PAINT=0 env_for host --app org.kde.kate.desktop --print paint 2>/dev/null)" cpu
check "a Qt without the painting: the reason it says" "$(SPARKY_STEREO_QT_PAINT=0 env_for host --app org.kde.kate.desktop --print paint-reason 2>/dev/null)" qt
has "kept problems are listed" <(env_for host --problems 2>&1) "Painting on the graphics card cannot be used for Kate"
env_for host --app org.kde.kate.desktop >/dev/null 2>&1
check "the painting can be had again: the kept problem is over" "$([ -f "$(rec paint-org.kde.kate)" ] || echo gone)" gone
env_for empty --app org.kde.kate.desktop >"$T/out" 2>"$T/err"
check "no graphics processor: status 0" "$?" 0
has "no graphics processor: said" "$T/err" "this computer has no graphics processor that can draw now"
check "no graphics processor: kept" "$([ -f "$(rec paint-org.kde.kate)" ] && echo kept)" kept
SPARKY_STEREO_QT_PAINT=0 env_for host --category other >/dev/null 2>"$T/err"
has "a kind without a program: said with the kind's words" "$T/err" "Painting on the graphics card cannot be used for other programs:"
check "a kind without a program: kept under the kind" "$([ -f "$(rec paint-other)" ] && echo kept)" kept
rm -rf "$PROBLEMS"

# what only the program knows: it tells, the page keeps, and the next good start ends it
env_for host --paint-failed org.kde.kate software "llvmpipe (LLVM 21.1.8, 256 bits)" 2>"$T/err"
check "told by the program: status 0" "$?" 0
has "told by the program: said" "$T/err" "Painting on the graphics card cannot be used for Kate: the OpenGL of this session is drawn by the processor (llvmpipe (LLVM 21.1.8, 256 bits)). The windows are painted on the processor."
check "told by the program: kept" "$([ -f "$(rec paint-run-org.kde.kate)" ] && echo kept)" kept
check "told by the program: its action" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(d["actions"][0]["command"]))' "$(rec paint-run-org.kde.kate)" 2>&1)" "sparky-stereo-gpu-env --use-paint org.kde.kate.desktop cpu"
check "while it is kept, the program is asked to tell when it works" "$(env_for host --app org.kde.kate.desktop | grep -c '^QT_WIDGETS_GPU_PAINT_TELL_OK=1$')" 1
check "another program is not asked" "$(env_for host --app org.kde.dolphin.desktop | grep -c TELL_OK)" 0
env_for host --paint-ok org.kde.kate
check "it works again: over" "$([ -f "$(rec paint-run-org.kde.kate)" ] || echo gone)" gone
check "and it is no longer asked to tell" "$(env_for host --app org.kde.kate.desktop | grep -c TELL_OK)" 0
for code in no-opengl library context; do
	env_for host --paint-failed org.kde.kate $code "words" 2>/dev/null
	check "told by the program: $code kept" "$([ -f "$(rec paint-run-org.kde.kate)" ] && echo kept)" kept
	rm -rf "$PROBLEMS"
done
env_for host --paint-failed org.kde.kate something-new "x" 2>/dev/null
check "a code this page does not know is not kept" "$([ -f "$(rec paint-run-org.kde.kate)" ] || echo none) $?" "none 0"
env_for host --paint-failed plainprogram no-opengl "" 2>"$T/err"
has "a program without a menu entry is named by its own name" "$T/err" "cannot be used for plainprogram: this session has no OpenGL"
check "a program without a menu entry: only Open Graphics settings is offered" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(a["id"] for a in d["actions"]))' "$(rec paint-run-plainprogram)" 2>&1)" "open"

# "Paint on the processor": the person's explicit choice, saved, and what was kept is over
env_for host --paint-failed org.kde.kate no-opengl "" 2>/dev/null
env_for host --use-paint org.kde.kate.desktop cpu
check "use-paint: status" "$?" 0
check "use-paint: saved for the program" "$(grep -A1 '^\[PaintPrograms\]' "$RC" | tail -1)" "org.kde.kate.desktop=cpu"
check "use-paint: what was kept is over" "$([ -f "$(rec paint-run-org.kde.kate)" ] || echo gone)" gone
check "use-paint: the program now paints on the processor" "$(paint host --app org.kde.kate.desktop)" ""
env_for host --use-paint org.kde.kate.desktop auto
check "use-paint auto: the program follows its kind again" "$(paint host --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=batch "
env_for host --use-paint other opengl
check "use-paint: a kind" "$(paint host --app org.kde.dolphin.desktop)" "QT_WIDGETS_GPU_PAINT=opengl "
env_for host --use-paint other auto
check "use-paint auto: a kind is not written" "$(grep -c Other "$RC" 2>/dev/null)" 0
check "use-paint: not a way" "$(env_for host --use-paint other fast >/dev/null 2>&1; echo $?)" 2
check "use-paint: not a kind" "$(env_for host --use-paint nothing cpu >/dev/null 2>&1; echo $?)" 2
check "use-paint: needs both" "$(env_for host --use-paint other >/dev/null 2>&1; echo $?)" 2
rm -f "$RC"

# the wrapper: a program started by hand follows the page; with a GPU the caller chose, the painting is still the page's
printf '[Paint]\nOther=batch\n' >"$RC"
cp "$SRC/share/sparky-stereo-gpu-run" "$T/run"; chmod +x "$T/run"
check "wrapper: the painting" "$(SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$T/run" --category other env | grep -c '^QT_WIDGETS_GPU_PAINT=batch$')" 1
check "wrapper: with the caller's GPU" "$(DRI_PRIME=1 SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$T/run" --category other env | grep -E '^(DRI_PRIME=1|QT_WIDGETS_GPU_PAINT=batch)$' | wc -l)" 2
rm -f "$RC"

# the machine's record: a measurement on this machine, and the record shipped for a model
R=$T/root; mkdir -p "$R"
rec_() { "$BIN/sparky-stereo-gpu-record" --root "$R" "$@"; }
rec_ --set-paint other batch --measurement "ORDER 518 fixed work, test"
check "record: written" "$?" 0
check "record: shown" "$(rec_ --show | grep -E '^paint-(other|origin|measurement)=' | tr '\n' ' ')" "paint-other=batch paint-origin=local paint-measurement=ORDER 518 fixed work, test "
check "record: readable by everyone" "$(stat -c %a "$R/etc/xdg/sparky-stereo-graphicsrc")" 644
check "record: read by the page's resolver" "$(XDG_CONFIG_DIRS=$R/etc/xdg paint host --app org.kde.kate.desktop)" "QT_WIDGETS_GPU_PAINT=batch "
rec_ --set-paint other unset
check "record: unset removes it, and the empty file" "$([ -e "$R/etc/xdg/sparky-stereo-graphicsrc" ] || echo gone)" gone
check "record: not a way" "$(rec_ --set-paint other fast >/dev/null 2>&1; echo $?)" 2
check "record: not a kind" "$(rec_ --set-paint nothing cpu >/dev/null 2>&1; echo $?)" 2
mkdir -p "$T/machines"
cat >"$T/machines/test-a10.conf" <<'M'
[Match]
Vendor=LENOVO
Product=80ST*
Gpus=1002:9874,1002:6660

[Measured]
BestGpu=1002:6660
Model=Test model

[MeasuredPaint]
Other=batch
Measurement=shipped test
M
A=$T/a10
"$BIN/sparky-stereo-gpu-record" --root "$A" --machines "$T/machines" --apply-known >"$T/out" 2>&1
check "shipped: applied on its model" "$(cat "$T/out")" written
check "shipped: the way and its origin" "$("$BIN/sparky-stereo-gpu-record" --root "$A" --show | grep -E '^paint-(other|origin)=' | tr '\n' ' ')" "paint-other=batch paint-origin=shipped "
check "shipped: applied again changes nothing" "$("$BIN/sparky-stereo-gpu-record" --root "$A" --machines "$T/machines" --apply-known)" unchanged
sed -i 's/^Other=batch/Other=opengl/' "$T/machines/test-a10.conf"
check "shipped: a new record for the model is written" "$("$BIN/sparky-stereo-gpu-record" --root "$A" --machines "$T/machines" --apply-known)" written
check "shipped: the new way" "$("$BIN/sparky-stereo-gpu-record" --root "$A" --show | grep '^paint-other=')" "paint-other=opengl"
"$BIN/sparky-stereo-gpu-record" --root "$A" --set-paint other cpu --measurement "measured here"
"$BIN/sparky-stereo-gpu-record" --root "$A" --machines "$T/machines" --apply-known >/dev/null
check "a measurement on the machine is never replaced by the model's" "$("$BIN/sparky-stereo-gpu-record" --root "$A" --show | grep -E '^paint-(other|origin)=' | tr '\n' ' ')" "paint-other=cpu paint-origin=local "
H=$T/host
"$BIN/sparky-stereo-gpu-record" --root "$H" --machines "$T/machines" --apply-known >"$T/out" 2>&1
check "shipped: not applied on another model" "$(cat "$T/out"; [ -e "$H/etc/xdg/sparky-stereo-graphicsrc" ] || echo no-file)" "nothing-known
no-file"
"$BIN/sparky-stereo-gpu-record" --root "$A" --forget
check "forget removes the painting's record too" "$([ -e "$A/etc/xdg/sparky-stereo-graphicsrc" ] || echo gone)" gone

# in the person's language (the engine's catalogue is built from the same .po files)
mkdir -p "$T/usr/locale/pt_BR/LC_MESSAGES"
msgfmt -o "$T/usr/locale/pt_BR/LC_MESSAGES/kcm_sparkystereo_graphics.mo" "$SRC/po/pt_BR/kcm_sparkystereo_graphics.po"
printf '[Paint]\nOther=batch\n' >"$RC"
LANG=pt_BR.UTF-8 SPARKY_STEREO_QT_PAINT=0 env_for host --app org.kde.kate.desktop >/dev/null 2>"$T/err"
has "said in Portuguese" "$T/err" "Não é possível pintar na placa de vídeo para Kate: o Qt instalado não sabe pintar na placa de vídeo. As janelas são pintadas no processador."

echo "paint: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
