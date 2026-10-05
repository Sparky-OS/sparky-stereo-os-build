# Stereo Oxygen, step 1: eight real stereo icons

Eight Oxygen icons, drawn in two views from Oxygen's own source drawings, shown in both eyes under our KWin so you can judge how the parts of an icon should get their depth.

## Show the sheet

```
/K3D/temp/partners/queue/stereo-oxygen/step1/viewer/stereo-icon-sheet
```

Run it in your test session, under our KWin. It picks its way to the compositor by itself (see "Which path runs where"). It opens one window at the sheet's size on a mid-grey background, one row per icon: trash, hard disk, desktop, printer, dictionary, settings, USB stick, system tools.

- **Page 1** (default, key `1`): the icons at 128 pixels.
- **Page 2** (key `2`): the 32 and 48 pixel versions at their real size (the 32 pixel columns first, then the 48 pixel ones).
- **Page 3** (key `3`): the 256 pixel icons.
- Key `4` shows the single front and back parts used by the proofs (measurement pictures; skip it).
- Tab goes to the next page. The arrows and Page Up/Down scroll when the window is smaller than the sheet. Esc or `q` quits.
- `--size 1920x1080` sets the window size, `--page 2` starts on a page. Nothing is ever scaled: each cell's left half goes to the left eye and its right half to the right eye, pixel for pixel.

## The columns

From left to right, in every row:

1. **PLAIN**: Oxygen's own picture, the same in both eyes (the reference).
2. **A 2%, A 4%, A 6%**: depth rule A, three strengths.
3. **B 2%, B 4%, B 6%**: depth rule B, three strengths.
4. **C 2%, C 4%, C 6%**: depth rule C, three strengths.

The strength is the total depth between the back and the front of the icon, as a fraction of the icon's size: 2 %, 4 % and 6 % (at 32 pixels that is about 0.6, 1.3 and 1.9 pixels; at 256 pixels, 5, 10 and 15). It is the same fraction at every size. The back of the icon stays at the icon's own level and only the rest comes out toward you; nothing goes behind it and nothing is cut by the picture's edge (where a part would be, the strength of that one icon is reduced; the generator records it).

One thing to know when comparing: the PLAIN column is Oxygen's shipped PNG, the other columns are the source drawing rendered by librsvg, so at 32 and 48 pixels the two can differ a little in softness (Oxygen made its small PNGs with its own export steps).

## The three rules

**Rule A, by paint order.** The drawing's parts are taken in the order Oxygen's artists painted them. The first one painted stays at the icon's level and the last one painted is the most popped; the others are spread evenly in between.

**Rule B, by role guessed from the drawing.** Dark, soft or see-through parts (drop shadows) and the lowest part stay at the icon's level; small bright parts (highlights, glows) are the most popped; everything else, the body of the icon, is half way between. The exact tests are written at the top of `make_stereo_icon.py`.

**Rule C, by objects.** Mapped by hand, looking at each part: the drawing's parts are grouped into the objects a person sees (the can's opening and its front wall, the printer's body and its tray) and every object has one level from 0 (the icon's own level) to 1 (the most popped). All parts of one object move together, so a surface, its outline, its shading and its highlights never separate, and a reflection stays on its surface; the cast shadow is its own object at level 0. The maps are in `depthmaps/<context>/<name>.json`.

The objects of each icon, from back to front (level in brackets), as mapped:

- **trash:** cast shadow (0), opening of the can (0.4), front wall with its shading and glints (1).
- **hard disk:** cast shadow (0), base (0.3), top plate with arm, hub and screws (1).
- **desktop:** monitor frame and shadow (0), wallpaper with its reflection (0.35), panel (0.7), desktop icons (1).
- **printer:** cast shadow (0), rear paper (0.25), body (0.55), front tray with the printed sheet (1).
- **dictionary:** cast shadow (0), page block (0.3), cover with spine, title and rules (1).
- **settings:** cast shadows (0), wrench (0.35), screwdriver crossing in front (1).
- **USB stick:** cast shadow (0), base (0.35), top face with the USB symbol (1).
- **system tools:** cast shadow (0), gear (0.4), hub ring (1).

Tell me where you disagree with a grouping or a level.

## Which path runs where

The viewer reaches KWin in one of two ways and chooses by itself (`--path multiview` or `--path declare` forces one):

- **multiview**, when the EGL has `EGL_EXT_multiview_window`: only our Mesa has it. The window is a two-view surface (`GL_BACK_LEFT` and `GL_BACK_RIGHT`) and Mesa packs it and declares it.
- **declare**, otherwise (your host's Debian Mesa 26.1.6-1, which is what the test session runs): an ordinary EGL window whose buffer is twice as wide as the window, the left view in the left half and the right view in the right half. The window's size is one view (set with `wp_viewporter`), and the viewer declares the surface itself as full side by side, left eye first, through KWin's `kde_stereo_content_manager_v1`. It needs our KWin (the protocol); on another compositor it stops with a message.

The viewer prints which path it took on its first line (`path=...`).

## What is here

- `stereo-oxygen/`: the theme (`Inherits=oxygen`), the eight icons at 32, 48, 128 and 256 pixels, rule B at 4 % for now. A loader that knows nothing about stereo gets the plain Oxygen icon (tested with GTK 3, Qt and KDE's own loader).
- `depthmaps/`: the hand-made object maps of rule C.
- `make_stereo_icon.py`: the generator, in a `debian:testing` container with librsvg.
- `viewer/`: the sheet program (C, EGL, Wayland, libpng) and its pictures.
- `proofs/`, `loader/`: the scripts that checked all of this, and their logs.

## Licence

Oxygen's icons are LGPL-3.0-or-later (KDE's `oxygen-icons` v6.28.0, `COPYING` and `LICENSES/LGPL-3.0-or-later.txt`). The generated icons are derived from them and keep that licence; a copy of the texts is in `stereo-oxygen/`.
