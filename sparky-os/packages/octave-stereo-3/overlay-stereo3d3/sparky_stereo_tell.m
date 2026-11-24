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
## @deftypefn {} {} sparky_stereo_tell (@var{key})
## Sparky Stereo OS: print the sentence @var{key} of Octave's 3D figures
## (@pxref{XREFsparky_stereo_text,,sparky_stereo_text}) once in this
## session, in the person's language.  Octave's figure windows call it
## when a 3D figure cannot show its depth.
##
## A desktop without stereo buffers shows every figure in 2D and nothing is
## said, unless the person turned Enable 3D on themselves (the preference
## @code{enable_3d} of the group @code{sparky_stereo}).
## @end deftypefn

function sparky_stereo_tell (key)

  persistent told = {};

  if (any (strcmp (told, key)))
    return;
  endif

  if (strcmp (key, "no-stereo-desktop")
      && ! (ispref ("sparky_stereo", "enable_3d")
            && getpref ("sparky_stereo", "enable_3d")))
    return;
  endif

  told{end+1} = key;
  printf ("%s\n", sparky_stereo_text (key));
  fflush (stdout);

endfunction
