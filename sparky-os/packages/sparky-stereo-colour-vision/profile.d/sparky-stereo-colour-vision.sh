# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The text console's palette for the person's colour vision (System Settings, Colour vision, "terminals" ticked).
# The page writes one line, ~/.config/sparky-stereo/colour-vision ("deutan terminals"); on the Linux console a login reads it
# and sets the 16 colours with the console's own sequence, ESC ] P n rrggbb (console_codes(4), "Set palette").
# Nothing happens in a terminal program (Konsole has its own scheme) or when the line is absent.
if [ "${TERM:-}" = linux ]; then
	_sparky_cv_line=${XDG_CONFIG_HOME:-$HOME/.config}/sparky-stereo/colour-vision
	if [ -r "$_sparky_cv_line" ]; then
		read -r _sparky_cv_kind _sparky_cv_terminals _sparky_cv_rest < "$_sparky_cv_line" || true
		_sparky_cv_palette=/usr/share/sparky-stereo/colour-vision/console-${_sparky_cv_kind:-none}.palette
		if [ "${_sparky_cv_terminals:-}" = terminals ] && [ -r "$_sparky_cv_palette" ]; then
			while read -r _sparky_cv_index _sparky_cv_rgb; do
				printf '\033]P%x%s' "$_sparky_cv_index" "$_sparky_cv_rgb"
			done < "$_sparky_cv_palette"
		fi
	fi
	unset _sparky_cv_line _sparky_cv_kind _sparky_cv_terminals _sparky_cv_rest _sparky_cv_palette _sparky_cv_index _sparky_cv_rgb
fi
