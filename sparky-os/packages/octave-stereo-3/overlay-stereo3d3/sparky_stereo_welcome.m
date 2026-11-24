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
## @deftypefn  {} {} sparky_stereo_welcome ()
## @deftypefnx {} {} sparky_stereo_welcome ("show")
## Sparky Stereo OS: show a 3D example when the Octave GUI starts.
##
## The figure is shown in stereo 3D on a desktop that takes stereo content,
## as every figure is while Enable 3D is on (its Tools menu), with the
## depth fitted to the person's depth limits.  Its menu Welcome > Open
## empty closes it and keeps Octave from opening with it from then on; the
## choice is the preference @code{open_with_example} of the group
## @code{sparky_stereo} (@pxref{XREFsetpref,,setpref}).  Called with
## @qcode{"show"}, the example opens whatever the preference says.
## @end deftypefn

function sparky_stereo_welcome (action = "")

  ## (getpref with a default would create the preference: it is read only when
  ## the person has set it)
  if (! strcmp (action, "show")
      && ispref ("sparky_stereo", "open_with_example")
      && ! getpref ("sparky_stereo", "open_with_example"))
    return;
  endif

  hf = figure ("name", sparky_stereo_text ("welcome-name"),
               "numbertitle", "off", "color", "w",
               "position", [200 120 800 600]);

  ## A Klein bottle (the figure-8 immersion): one closed surface, no inside
  ## and no outside, which the eyes follow around in depth
  [u, v] = meshgrid (linspace (0, 2*pi, 120), linspace (0, 2*pi, 60));
  r = 2.5;
  x = (r + cos (u/2) .* sin (v) - sin (u/2) .* sin (2*v)) .* cos (u);
  y = (r + cos (u/2) .* sin (v) - sin (u/2) .* sin (2*v)) .* sin (u);
  z = sin (u/2) .* sin (v) + cos (u/2) .* sin (2*v);

  surf (x, y, z, u);
  shading interp;
  colormap (turbo (256));
  axis equal off;
  view (-35, 30);
  camlight headlight;
  lighting gouraud;
  material shiny;
  title (sparky_stereo_text ("welcome-title"), "fontsize", 14);
  rotate3d (hf, "on");

  ## The choice is in the figure's menu bar, beside its Tools menu (Enable
  ## 3D and the desktop's display settings)
  menu = sparky_stereo_text ("welcome-menu");
  open_empty_text = sparky_stereo_text ("welcome-open-empty");
  how_text = sparky_stereo_text ("welcome-how");
  hm = uimenu (hf, "text", menu);
  uimenu (hm, "text", open_empty_text,
          "callback", @(varargin) open_empty (hf));
  uimenu (hm, "text", how_text, "separator", "on",
          "callback", @(varargin) edit ("sparky_stereo_welcome"));
  uicontrol (hf, "style", "text", "units", "normalized",
             "position", [0.02 0.02 0.96 0.05], "backgroundcolor", "w",
             "horizontalalignment", "left",
             "string", sprintf (sparky_stereo_text ("welcome-hint"),
                                menu_path (menu, open_empty_text),
                                menu_path (menu, how_text)));

endfunction

## A menu's path as a person reads it: "Welcome > Open empty", without the
## mnemonics ("&" before a letter, or "(&W)" after the word)
function str = menu_path (menu, item)
  plain = @(s) strrep (regexprep (s, '\(&.\)$', ''), "&", "");
  str = [plain(menu) " > " plain(item)];
endfunction

function open_empty (hf)
  setpref ("sparky_stereo", "open_with_example", false);
  close (hf);
  printf ("%s\n", sprintf (sparky_stereo_text ("welcome-empty-done"),
                           'sparky_stereo_welcome ("show")'));
  printf ("%s\n", sprintf (sparky_stereo_text ("welcome-again"),
                           'setpref ("sparky_stereo", "open_with_example", true)'));
endfunction
