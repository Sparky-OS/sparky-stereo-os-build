# gtk+3.0: a stereo GtkGLArea in GTK 3

Debian's gtk+3.0 3.24.52-3 with the edition's stereo GtkGLArea, built with Lean Code: 3.24.52-3+stereo3d1+lc1 (queue row 137, milestone 4).
GTK 4's stereo area (packages/gtk4) is the model, with the same names: the property `stereo`, the render signal once per eye with `gtk_gl_area_get_current_eye()`, `stereo-shown` and `stereo-error`, `stereo-view-width` and `stereo-view-height`, `format` and `color-state`.

## The patches

- `stereo3d-gdk-color-state.patch`: GDK gains `GdkMemoryFormat` (the five formats an area renders in, with GTK 4's values), `GdkColorState` and `GdkCicpParams` (ITU-T H.273 code points), under GTK 4's names.
- `stereo3d-gtkglarea-stereo.patch`: the stereo area (gtk/gtkglarea.c), its own surface on Wayland and X11 (gtk/gtkglareastereo.c) and the window's hole over it (gtk/gtkwindow.c, the opaque region).
- `stereo3d-gtk3-demo-glarea-stereo.patch`: gtk3-demo's OpenGL Area in stereo.
- `stereo3d-testsuite-glarea.patch`: GTK's own test of the API (testsuite/gtk/glarea.c).

How each piece works, its proof and its traps: the public skill stereo-window-3d-area, references/gtk-glarea.md, section "GTK 3".

## Build

`build.sh WORK PREVIOUS_DIR SOURCE_DIR` (see its header): the source package once, the Lean Code source, then the build with the link and start gate against Debian's 3.24.52-3 binary packages.

## Credits

- GTK (names from the file headers and the gtk-3-24 history of each file): Emmanuele Bassi wrote GtkGLArea (the copyright line of gtk/gtkglarea.c, 2014) and GDK's GL contexts (gdk/gdkglcontext.c), with Alexander Larsson and Matthias Clasen, who wrote most of the later changes to both; GDK 3's Wayland windows and their subsurfaces (gdk/wayland/gdkwindow-wayland.c) are mostly Jonas Ådahl's, Jasper St. Pierre's, Carlos Garnacho's, Olivier Fourdan's and Matthias Clasen's work, and Robert Mader added the frame callbacks of surfaces a program makes itself (d3316a37, 2021); GtkWindow (gtk/gtkwindow.c) carries Peter Mattis', Spencer Kimball's and Josh MacDonald's copyright line and the GTK+ Team's. The API shape is GTK 4's: GdkColorState and GdkCicpParams by Matthias Clasen, with Benjamin Otte.
- The OpenGL Area demo (demos/gtk-demo/glarea.c): Emmanuele Bassi, Matthias Clasen and Alexander Larsson (its gtk-3-24 history; Alexander Larsson started it as tests/testglarea, 3b3726ae, 2014).
- The protocols (their XML copyright lines): wp_color_management_v1, Sebastian Wick, Erwin Burema, AMD, Collabora, Xaver Hugl and Red Hat; wp_viewporter and zwp_linux_dmabuf_v1, Collabora; the stereo declaration `kde_stereo_content_v1` through libstereo-declare.
- Debian's packaging: Simon McVittie, Dmitry Shachnev and Jeremy Bícha (the Uploaders of gtk+3.0), the Debian GNOME team.
