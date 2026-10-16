#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# The system default for OpenGL stereo, from the graphics card the desktop runs on.
# NVIDIA's OpenGL gives a window no second view, so on a desktop that runs on NVIDIA's driver
# programs get their two views from Mesa's OpenGL over NVIDIA's Vulkan driver (zink, the
# default) or keep NVIDIA's own OpenGL (nvidia; gl-stereo-run then gives them the views).
# A desktop on Mesa (AMD, Intel, nouveau, a hybrid laptop's integrated card) keeps Mesa.
# Sourced by sparky-stereo-opengl-default and by the tests.

# opengl_desktop_card SYSFS DEVDIR: prints "<card> <kernel driver>" of the card KWin renders on,
# or nothing. Only cards that can render count (a render node in DEVDIR); the boot VGA card first,
# as KWin chooses, else the first with a screen connected, else the first: the same order
# share/plasma-env/sparky-stereo-primary-gpu.sh gives KWin when the boot VGA cannot render.
opengl_desktop_card() {
	_og_boot= _og_first= _og_second=
	for _og_c in "$1"/class/drm/card[0-9]*; do
		case ${_og_c##*/} in *-*) continue ;; esac
		[ -e "$_og_c/device" ] || continue
		_og_render=$(ls "$_og_c/device/drm" 2>/dev/null | grep '^renderD' | head -n1)
		[ -n "$_og_render" ] && [ -e "$2/$_og_render" ] || continue
		_og_driver=$(readlink "$_og_c/device/driver" 2>/dev/null)
		_og_card="${_og_c##*/} ${_og_driver##*/}"
		_og_conn=0
		for _og_s in "$_og_c"-*/status; do
			[ "$(cat "$_og_s" 2>/dev/null)" = connected ] && _og_conn=1
		done
		if [ "$(cat "$_og_c/device/boot_vga" 2>/dev/null)" = 1 ]; then
			_og_boot=$_og_card
		elif [ $_og_conn = 1 ] && [ -z "$_og_first" ]; then
			_og_first=$_og_card
		elif [ -z "$_og_second" ]; then
			_og_second=$_og_card
		fi
	done
	_og_pick=${_og_boot:-${_og_first:-$_og_second}}
	[ -z "$_og_pick" ] || echo "$_og_pick"
}

# opengl_desktop SYSFS DEVDIR: prints nvidia (NVIDIA's driver runs the desktop), mesa or none
opengl_desktop() {
	_og_pick=$(opengl_desktop_card "$1" "$2")
	case $_og_pick in
		'') echo none ;;
		*' nvidia') echo nvidia ;;
		*) echo mesa ;;
	esac
}

# opengl_default_write CONF DESKTOP CARD [CHOICE]: writes the default; the person's choice
# (opengl=zink or nvidia) already in CONF is kept unless CHOICE replaces it
opengl_default_write() {
	_og_choice=${4:-}
	if [ -z "$_og_choice" ] && [ -f "$1" ]; then
		_og_choice=$(sed -n 's/^opengl=\(zink\|nvidia\)$/\1/p' "$1" | tail -n1)
	fi
	mkdir -p "${1%/*}"
	cat > "$1.new" <<EOF
# Written by sparky-stereo-hardware at install, at boot and when a graphics card is added,
# removed or changes driver. desktop: the driver family of the card the desktop runs on.
# opengl: how programs get OpenGL stereo when NVIDIA's driver runs the desktop:
#   zink   Mesa's OpenGL over NVIDIA's Vulkan driver, which has the two views (the default)
#   nvidia NVIDIA's own OpenGL; gl-stereo-run gives a program its two views
# Change it with: sparky-stereo-opengl-default --opengl zink|nvidia
# It applies from the next login; gl-stereo-run --nvidia-opengl chooses per program.
desktop=$2
card=$3
opengl=${_og_choice:-zink}
EOF
	mv "$1.new" "$1"
}

# opengl_nvidia_programs SYSTEM-LIST ETC-LIST USER-LIST: prints the programs that keep NVIDIA's
# own OpenGL: the system list, then "NAME nvidia" adds and "NAME zink" removes, the person's
# list last, so the person's choice wins
opengl_nvidia_programs() {
	{
		[ -r "$1" ] && sed -n 's/#.*//; s/^[[:space:]]*\([^[:space:]]\+\)[[:space:]]*$/\1 nvidia/p' "$1"
		for _og_f in "$2" "$3"; do
			[ -r "$_og_f" ] && sed -n 's/#.*//; s/^[[:space:]]*\([^[:space:]]\+\)[[:space:]]\+\(nvidia\|zink\)[[:space:]]*$/\1 \2/p' "$_og_f"
		done
	} | awk '{ choice[$1] = $2; if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 } }
		END { for (i = 1; i <= n; i++) if (choice[order[i]] == "nvidia") print order[i] }'
}

# opengl_program_overrides OUT DATA-DIRS PROGRAM...: for every menu entry in the applications
# directories of DATA-DIRS (colon separated, first wins, as XDG_DATA_DIRS) whose Exec starts one
# of the programs, writes a copy under OUT/applications whose Exec lines start through
# sparky-stereo-nvidia-opengl; prints how many it wrote
opengl_program_overrides() {
	_og_out=$1/applications _og_dirs=$2; shift 2
	mkdir -p "$_og_out"
	_og_programs=" $* "
	echo "$_og_dirs" | tr ':' '\n' | while IFS= read -r _og_d; do
		[ -n "$_og_d" ] && [ -d "$_og_d/applications" ] || continue
		(cd "$_og_d/applications" && find . -name '*.desktop') | sed 's|^\./||' | while IFS= read -r _og_file; do
			[ -e "$_og_out/$_og_file" ] && continue
			_og_prog=$(awk '/^Exec=/ { sub(/^Exec=/, ""); n = split($0, t, " "); i = 1
				if (t[i] == "env") { i++; while (i <= n && t[i] ~ /=/) i++ }
				p = t[i]; gsub(/"/, "", p); sub(/.*\//, "", p); print p; exit }' "$_og_d/applications/$_og_file")
			case $_og_programs in
				*" $_og_prog "*)
					[ -n "$_og_prog" ] || continue
					mkdir -p "$(dirname "$_og_out/$_og_file")"
					sed 's|^Exec=|Exec=sparky-stereo-nvidia-opengl |' "$_og_d/applications/$_og_file" > "$_og_out/$_og_file" ;;
			esac
		done
	done
	find "$_og_out" -name '*.desktop' | wc -l
}

# opengl_program_shims OUT PROGRAM...: for every program found in PATH, writes OUT/bin/PROGRAM,
# which starts it through sparky-stereo-nvidia-opengl, for a terminal or a script that starts
# it by name; prints how many it wrote
opengl_program_shims() {
	_og_bin=$1/bin; shift
	mkdir -p "$_og_bin"
	for _og_p in "$@"; do
		case $_og_p in */*) continue ;; esac
		_og_path=$(command -v "$_og_p" 2>/dev/null) || continue
		case $_og_path in /*) ;; *) continue ;; esac
		[ "${_og_path%/*}" = "$_og_bin" ] && continue
		printf '#!/bin/sh\n# written at session start by sparky-stereo-opengl.sh\nexec sparky-stereo-nvidia-opengl %s "$@"\n' "'$_og_path'" > "$_og_bin/$_og_p"
		chmod 755 "$_og_bin/$_og_p"
	done
	find "$_og_bin" -type f | wc -l
}
