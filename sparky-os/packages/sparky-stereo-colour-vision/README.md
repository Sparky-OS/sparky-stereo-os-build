# sparky-stereo-colour-vision

System Settings' **Colour Vision** page, beside Accessibility.
One choice (None, Protan, Deutan, Tritan, Monochromacy) and one box for the terminals.

Daniel, 2026-10-14: "make alternative color maps for the color deficiencyes - we need to work on the kde accessibility".
The accessibility study of that day measured every surface and proposed the maps; Daniel accepted its answer 5:
"The two contrast failures are fixed for everyone, and the hues become a switch."

## What the choice sets, and how a person's own files are kept

| Surface | What is written | The person's own |
| --- | --- | --- |
| KWin's colour correction | `kwinrc` `[Plugins] colorblindnesscorrectionEnabled`, `[Effect-colorblindnesscorrection] Mode`: the keys KDE's Accessibility page writes, so both pages show one choice; then KWin's `loadEffect` or `unloadEffect` and `reconfigureEffect` | the strength (`Intensity`) stays as set on the Accessibility page |
| Colour scheme | the colour-vision variant of the scheme in use (`NAMEColourVisionKIND`), applied with `plasma-apply-colorscheme`; shipped for the look's own scheme, made in `~/.local/share/color-schemes` for any other | the colour groups and keys of `~/.config/kdeglobals` are kept and written back exactly at None, unless the person chose another scheme meanwhile |
| Konsole (box ticked) | `~/.local/share/konsole/SparkyStereoColourVision.profile`, whose `Parent=` is the person's default profile and which sets only `ColorScheme=BreezeColourVisionKIND`; `konsolerc` `DefaultProfile` names it | no profile of theirs is rewritten; `DefaultProfile` comes back as it was |
| nano (box ticked) | `~/.config/nano/nanorc` with three lines, only when the person has neither `~/.nanorc` nor that file | a file of theirs is never written; the page gives the lines to add |
| Text console (box ticked) | `~/.config/sparky-stereo/colour-vision`, one line; `/etc/profile.d/sparky-stereo-colour-vision.sh` sets the 16 colours at a console login (`ESC ] P`) | |

The choice made on KDE's Accessibility page is followed too: `sparky-stereo-colour-vision.path` (a user unit) runs `sparky-stereo-colour-vision sync` when `kwinrc` changes.

## The maps

`data/maps.json` (colour schemes, per kind, for dark and light backgrounds), `tools/terminal-maps.json` (Konsole and the console),
generated into `data/` by `tools/make-terminal-maps.py`.
Each was measured as the person sees it: the dichromacy, the 0.6 anomaly and KWin's correction on the screen (Machado,
Oliveira and Fernandes 2009; CIEDE2000; WCAG 2.2 1.4.3).
`data/limits.json` names the pairs that stay close in the variants of some schemes the edition ships; the page says them.

## Translations

`tools/translations.py` writes `po/LANG/kcm_sparkystereo_colourvision.po` for the edition's ten languages.
