# GLX window lifetime probe

Build `glx-window-lifetime.c` with `cc -O2 -Wall -Wextra -Werror -lGL -lX11` and run it in a disposable headless edition X11 session from an empty output directory.
It creates two ordinary owner windows and two stereo children, draws labelled constant eye colours, and exercises GLX drawable destruction/recreation, X-window reparenting and X-window destruction.
It never writes stereo properties.

`IMMEDIATE` records the first observed owner lists.
`SETTLED` polls only properties, with no rendering or swap during the wait, for at most 200 attempts separated by 5 ms.
All nine `SETTLED` records must have `matched=1` for the owner-lifetime contract.
Both ordinary owners must remain undeclared, and their application event masks must remain zero.
A live child remains listed when only its GLX drawable is destroyed.
Reparenting transfers it to the new owner; destroying the X window removes it before the next swap.

Capture the actual X requests independently when checking write counts.
The two child windows receive one content declaration each, layout 3.
For this sequence, owner-list maintenance performs six writes: two additions, one removal and one addition on reparent, and two removals on destruction.
These maintenance counts are specific to the sequence, not a fixed protocol-wide contract.
No content declaration is inferred from an owner-list update.

The probe preserves the X error from explicitly destroying a GLX drawable after its underlying X window has already been destroyed.
It also retains raw front-eye planes and mapped module paths.
Exit zero means the probe completed; the printed property assertions and independent request/pixel checkers determine acceptance.
Owner-lifetime success does not establish stereo pixel, clipping, overlap, input or DPI correctness.


Set `LIFETIME_CAPTURE=1` to pause at each of the nine lifecycle stages. The
fixture prints `CAPTURE <stage>` and waits for one newline on stdin; it does
not render or swap while waiting. Capture the full side-by-side virtual output
and record actual X geometry while paused. USPosition hints keep the two owner
windows apart. Set `LIFETIME_MSAA=1` to request a four-sample visual in the same fixture. Each draw records `GL_SAMPLES` and requires at least four samples; capture mode may be combined with it.

`check-window-lifetime-capture.py CASE OUTPUT --require-pass` checks all 144,000
raw GL front pixels, all 336,000 captured child-eye pixels, ordinary owner
background pixels, nine lifetime observations, declaration counts and the
actual declaration-before-Present order. Its capture contract is an 800x600
virtual output, side-by-side screen captures, the fixture's requested window
positions, zero stereo depth and no decorations. CASE contains `client.stdout`,
`frameN-eyeE.rgb`, `wire.jsonl` (XRECORD requests with extension metadata and
monotonic timestamps), and `captures.json` (stage, observed geometry, capture
metadata) plus `<stage>.png`. A completed process alone is not a pass. Preserve
old failing rows; do not replace the first frame with a later one. This bounded
fixture does not certify overlap, clipping, input, DPI or other GPU routes.


Build `egl-surfaceless-mono.c` with `cc -O2 -Wall -Wextra -Werror -lEGL -lGL`.
It uses the surfaceless EGL platform without a native window, creates ordinary
pbuffers of 64x48, 32x24 and 64x48, and compares every RGB pixel with four
constant quadrant colours. It requires a mono context, reports the renderer
and mapped providers, and returns failure on any mismatch or EGL operation
error. Run against installed predecessor and candidate libraries. This is an
ordinary EGL pbuffer control, not a Wayland window or stereo declaration test.

## Native Wayland EGL windows

`egl-wayland-window.c` checks ordinary windows, two-view windows drawing only
left, and two-view windows drawing both eyes. It binds only `wl_compositor`
and `xdg_wm_base`; Mesa owns all stereo declarations. Generate the xdg-shell
client glue from the installed public protocol and build in a disposable SDK:

```sh
xml=$(pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header "$xml" xdg-shell-client-protocol.h
wayland-scanner private-code "$xml" xdg-shell-protocol.c
cc -O2 -Wall -Wextra -Werror -I. egl-wayland-window.c xdg-shell-protocol.c \
  $(pkg-config --cflags --libs wayland-client wayland-egl egl gl) -o egl-wayland-window
```

Run `egl-wayland-window MODE OUTPUT`, where MODE is `mono`, `left-only` or
`stereo`, in a fresh isolated Wayland compositor for each case, with
`WAYLAND_DEBUG=client`. Do not set DISPLAY or override the installed providers.
The fixture requires the edition's `EGL_EXT_multiview_window`, including for
the ordinary-window control. It checks every drawn GL back pixel and retains
bottom-up RGB arrays. At each `FRAME` line it waits for `next` followed by a
newline, without drawing another frame. Capture before releasing that barrier.
The four stages are first 96x64, first resized 80x48, repeated 80x48 and a new
96x64 native/EGL surface after destruction. An outer runner must bound waits
and preserve failed runs.

`check-egl-wayland.py ROOT --output RESULT` expects `mono`, `left-only` and
`stereo` subdirectories. Each contains `client.stdout`, `protocol.log`, the raw
`STAGE-eyeN.rgb` files, `STAGE.png`, `exit.png`, and a runner `result.json` with
`returncode`, `failure`, `environment`, and `mapped` provider records (each has
`elf_class`). Captures use one 800x600 virtual output, zero stereo depth, no
window decorations or cursor, and full side-by-side screenshots when stereo
is active. The first two cases remain ordinary and byte-identical. Stereo's
left capture must match them, with the right eye exactly 800 pixels to its
right; each eye retains the requested window dimensions. Exit restores black.

The checker independently compares 79,872 raw pixels and 79,872 captured
pixels. It checks actual buffer dimensions and requests: zero declarations
for mono/left-only, one full-SBS declaration for each of the two stereo
surfaces before its first buffer commit, no repeat/resize declaration, two
content destructions, and no viewport writes on the version-2 protocol.
Object numbers may be reused after destruction. Its negative controls reject
missing/changed/duplicate declarations, wrong buffer width, a changed pixel,
swapped eyes and a frozen right eye. This gate covers those native Wayland EGL
behaviors only; it does not establish input/DPI, clipping/overlap, NVIDIA,
Wine or Vulkan behavior.

## glx-back-both-eyes.c (patch 0037)

A GLX quad buffer window under Stereo KWin: the left eye is cleared red, the right eye blue, then `glDrawBuffer(GL_BACK)` and one green rectangle, which OpenGL 4.6 core 17.4.1 sends to both back buffers.
`MODE=out` draws it with a core profile shader that declares its output at location 0 (red before 0037: the rectangle is in the left eye only), `MODE=fragcolor` with `gl_FragColor`, `MODE=clear` with a scissored `glClear`, `MODE=fixed` with `glBegin`.
Build with `cc -o glx-back-both-eyes glx-back-both-eyes.c -lGL -lX11`, start it in a Stereo KWin session through Xwayland, capture the screen with ScreenShot2 and run `check-glx-back-both-eyes.py SHOT.png X Y W H` with the window's place and one eye's size: it exits 0 only when the corner of each eye holds its own colour and the middle of both is green.
`NOBACK=1` draws the rectangle with `GL_BACK_LEFT` and must fail the check.
`glx-draw-buffers.c` reads both back buffers back with `glReadPixels` instead of a capture, and with `ANNOUNCE_STEREO=1` it sets the root property a stereo compositor sets, so it runs on a plain virtual X server: `next-source.sh` puts it in debian/tests as `glx-back-both-eyes` (cases out, mrtwin, fragcolor, left, right; exit 77 with a message where no quad buffer configuration exists).
Its other cases (clear, fixed, dualsrc, mrtfbo, mono, es2, es3) are the regression set for a change to the state tracker's shader variants: the lines of two Mesa builds must be equal except where the change is meant.

## vk-views.c (patch 0040)

One window and one `VkSurfaceKHR`, and a timed sequence of swapchains with two image layers or one, as a program that turns its 3D off and on again presents: `PHASES="2:4,1:4,2:4,1:0"` (views and seconds; the last phase lasts until the program is stopped), `OLD=0` destroys the previous swapchain before the next instead of naming it as `oldSwapchain`, `X11=1` uses an X11 window through Xwayland, `VK_VENDOR=0x10de` picks NVIDIA's device.
A pair shows layer 0 red and layer 1 blue; a one-layer swapchain shows its picture's left half green and its right half yellow, so a flat window has both halves in each eye and a picture shown as a pair has one colour per eye (green left, yellow right).
Build with `wayland-scanner client-header` and `private-code` of `stable/xdg-shell/xdg-shell.xml` beside it and `cc -o vk-views vk-views.c xdg-shell-protocol.c -lvulkan -lwayland-client -lxcb`; in X11 mode it prints the window's `_KDE_NET_WM_STEREO_CONTENT` every second.
Before 0040, through the Vulkan stereo layer on NVIDIA every one-layer phase shows one half per eye on Wayland, and on X11 (the layer, radv and lavapipe) the window keeps declaring 3 and shows the one-layer picture mixed with the last pair; with 0040 every phase is the right picture and the X11 declaration goes 3, 0, 3, 0 with the phases.

# A declared child's first pair (ORDER 17)

`glx-child-first-pair.c` (`cc -O1 -o glx-child-first-pair glx-child-first-pair.c -lX11 -lGL`) is a plain top level with a quad buffer GLX child that swaps once, the way CloudCompare, a QOpenGLWidget or VTK window does.
`DELAY_MS` waits between the map and the swap, `EARLY=1` writes the declaration at the map instead of leaving it to Mesa's first swap, `SWAPS` and `GAP_MS` set later swaps.
Run it in a fresh Stereo KWin session (`kwin_wayland --virtual --xwayland`), capture the output after seven seconds and give the capture to `check-glx-child-first-pair.py`.
Without patch 0043 (or on a Stereo KWin that announces less than declaration support 11) a run with `DELAY_MS=0` is FLAT and told, with 1 or 10 swaps; with `EARLY=1 DELAY_MS=80` it is a PAIR: the child is taken by KWin some tens of milliseconds after it is declared.
With patch 0043 on Stereo KWin +stereo3d59 a run with `DELAY_MS=0` is a PAIR, and `LIBGL_DEBUG=verbose` prints `stereo child 0x...: the compositor took the child after N us`.

Round 3 additions: `glx-child-first-pair.c` also takes `PRESENT_TRACE=1` (it selects PresentCompleteNotify on the child itself and prints each completion's serial and mode after the swap; it changes the outcome of the run on the final stack, so count pairs without it), and `egl-child-first-pair.c` is the same program for EGL on X11 (`cc -O1 -o egl-child egl-child-first-pair.c -lEGL -lGL -lX11`; `FRAMES=1 HOLD_S=10 COVER_AT=-1`): an EGL two-view surface on a child of a plain frame. The software GLX path is the same GLX program with `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe` in the program's environment only (in KWin's it breaks the screenshot). The wait's timeout is a compositor that announces support 11 and writes nothing: Stereo KWin +stereo3d58 with the root window's `_KDE_NET_WM_STEREO_CONTENT_SUPPORTED` set to 11 by a client after KWin starts; the swap then starts 0.505 s after the declaration and Mesa says "the compositor did not take the child in 500 ms".

# A Vulkan X11 surface's extents (patch 0047)

`vk-x11-surface-extent.c` makes a 640x480 window, creates an xcb and an Xlib surface for it with an allocator that fills every allocation with 0xff (a field the driver forgets to set then reads as true, every run), and asks each physical device for the surface's capabilities: `currentExtent`, `minImageExtent` and `maxImageExtent` must be the window's size ("With Xcb, minImageExtent, maxImageExtent, and currentExtent must always equal the window size", VK_KHR_xcb_surface).
Build with `cc -O2 -Wall -o vk-x11-surface-extent vk-x11-surface-extent.c -lvulkan -lX11 -lX11-xcb -lxcb` (libx11-xcb-dev) and run it on any X server: a plain Xvfb, and Stereo KWin's Xwayland (`kwin_wayland --virtual --xwayland`).
It prints PASS or FAIL per device and surface kind and exits 1 when one fails.
Measured (ORDER 39, 2026-11-19): Mesa 26.1.6-1+stereo3d26+lc1 FAIL on RADV (Renoir) and lavapipe, xcb and Xlib, on both servers (320x480 for the 640x480 window); the same source with patch 0047 PASS on all eight.

## egl-declared-pair-lifetime.c and qt-declared-child-hideshow.cpp (row 830)

A declared Wayland surface holding two views, taken down in every order a client may take: `declared`, `surface-first`, `withdraw-first`, `hide-show`, `resize`, `redeclare`, `late-release`, `current-destroy` (the EGL surface destroyed while current, as libobs does) and `never-withdrawn`.
Two routes: `packed` (the program draws both views into one buffer twice a view wide and declares it with libstereo-declare, as OBS's preview does) and `multiview` (`EGL_MULTIVIEW_VIEW_COUNT_EXT` 2, declared by Mesa), and `mono` as the 2D control; `THREAD=1` keeps a second declared surface drawing on its own thread.
The child is a desynchronized sub-surface of an xdg toplevel, as Qt's native child window is; between rounds the program reallocates many blocks so that glibc checks its chunks.
Build in the rig (xdg-shell glue as for `egl-wayland-window.c`):

```sh
cc -O1 -g -Wall -Wextra -I. egl-declared-pair-lifetime.c xdg-shell-protocol.c -o egl-declared-pair-lifetime \
  $(pkg-config --cflags --libs wayland-client wayland-egl egl gl stereo-declare) -lpthread
egl-declared-pair-lifetime packed|multiview|mono ORDER ROUNDS
```

It exits 0 with `DONE rounds=N`; a damaged heap ends it in glibc, a protocol error with libwayland's message (`never-withdrawn` must end with `wl_surface was destroyed before a set_content request`: libstereo-declare keys its declarations by the surface's address).
Run it under Valgrind's memcheck (`--error-exitcode=99 --undef-value-errors=no`) and against a sanitizer build of this tree; on +stereo3d29 every order was clean on radeonsi, on zink over the NVIDIA card, on llvmpipe and on NVIDIA's own EGL (row 830, 2026-11-23), so it is a regression test, not a red one.

`qt-declared-child-hideshow.cpp` is OBS's preview without OBS: a native child widget whose display (a heap block with a mutex, like libobs's `obs_display`) is made when its window is shown and freed at `visibleChanged(false)`, drawn on a graphics thread through an EGL display on Qt's own `wl_display` into a window surface twice a view wide, declared with libstereo-declare.
`old` repeats the stereo module's write into the freed display before its repair, `late` withdraws the declaration after Qt dropped the child's sub-surface without that write, `fixed` withdraws on the child window's own Hide event.
Build with `c++ -fPIC -std=c++17 qt-declared-child-hideshow.cpp $(pkg-config --cflags --libs Qt6Widgets wayland-client wayland-egl egl gl stereo-declare) -lpthread` and run `qt-declared-child-hideshow old|late|fixed CYCLES` with `QT_QPA_PLATFORM=wayland`; it prints `DONE cycles=N declarations=N withdrawals=N freed-writes=N`.
Qt 6.11 keeps a hidden child's `wl_surface` and destroys only its `wl_subsurface`: read `WAYLAND_DEBUG=client` before saying the surface was destroyed.
