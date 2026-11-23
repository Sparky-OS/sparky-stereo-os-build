## Copyright (C) 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Octave; see the file COPYING.  If not, see
## <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {} {} sparky_stereo_menu (@var{hf}, @var{htools})
## Sparky Stereo OS: add a figure's 3D options to its Tools menu
## @var{htools}: Enable 3D, and the desktop's display settings.
##
## Enable 3D is on by default.  It is kept as the preference
## @code{enable_3d} of the group @code{sparky_stereo}
## (@pxref{XREFsetpref,,setpref}) and is the default of the figure property
## @code{stereo} (@code{set (0, "defaultfigurestereo", ...)}), so it
## applies to the figures made after it; a figure chooses its OpenGL
## buffers when its window is made.  The depth of a 3D figure is not a
## setting of Octave: it is fitted to the person's depth limits, kept with
## the 3D screens in the desktop's display settings.
## @end deftypefn

function sparky_stereo_menu (hf, htools)

  onoff = {"off", "on"};
  ## getpref with a default would create the preference: read it only when the
  ## person has set it
  on = (! ispref ("sparky_stereo", "enable_3d")
        || getpref ("sparky_stereo", "enable_3d"));

  uimenu (htools, "text", sparky_stereo_text ("menu-enable-3d"),
          "separator", "on", "checked", onoff{on + 1},
          "tag", "__sparky_stereo_enable_3d__", "handlevisibility", "off",
          "menuselectedfcn", @enable_3d_cb);
  uimenu (htools, "text", sparky_stereo_text ("menu-display-settings"),
          "tag", "__sparky_stereo_display_settings__",
          "handlevisibility", "off", "menuselectedfcn", @display_settings_cb);

endfunction

function enable_3d_cb (h, ~)

  onoff = {"off", "on"};
  on = ! strcmp (get (h, "checked"), "on");

  try
    setpref ("sparky_stereo", "enable_3d", on);
  catch
    printf ("%s\n", sparky_stereo_text ("choice-not-saved"));
  end_try_catch

  set (0, "defaultfigurestereo", onoff{on + 1});
  set (findall (0, "tag", "__sparky_stereo_enable_3d__"),
       "checked", onoff{on + 1});

endfunction

function display_settings_cb (~, ~)

  ## The depth limits and the 3D screens are in the desktop's display
  ## settings, opened in System Settings, else in the module's own window
  for cmd = {"systemsettings", "kcmshell6"}
    if (system (sprintf ("command -v %s > /dev/null 2>&1", cmd{1})) == 0)
      system (sprintf ("%s kcm_kscreen > /dev/null 2>&1 &", cmd{1}));
      return;
    endif
  endfor

  printf ("%s\n", sparky_stereo_text ("display-settings-failed"));

endfunction
