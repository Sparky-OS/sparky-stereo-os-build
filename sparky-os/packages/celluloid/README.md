# celluloid 0.29-3+stereo3d1+lc1

Celluloid, the GTK 4 front end of mpv, showing 3D films in 3D (queue row 137, milestone 3).
Debian's 0.29-3 source with one patch, `patches/stereo3d-3d-films.patch`: the video area is a stereo GtkGLArea rendered once per eye from libmpv, the 3D menu has the edition's options and no others, a film's correction is kept beside its resume position and saved into the file only when the person chooses it.
"3D Input Format" is offered for every film with a picture, shown in 3D or flat, because it is how a person gives a film that declares nothing its packing; "Swap left and right eyes" and the save are offered only while the film is shown in 3D.

## Build

```
bash build.sh WORK DEBIAN_SOURCE SIBLINGS REPO
```

`make-source.sh` makes the Lean Code source from Debian's source package (checked against `source.sha256`); `release/build-from-lc-dsc.sh` builds it with the link and start gate.
It needs gtk4 4.24.1+ds-1+stereo3d3 (the stereo area's view size) and mpv-dmo 1:0.41.0-dmo9+stereo3d12 (the render API's stereo view parameter): until a round carries them, their packages are the build's siblings.

## What it depends on, and why

- `libmpv2 (>= 1:0.41.0-dmo9+stereo3d12~)`: the parameter is a value, not a symbol, so no shlibs line asks for it.
- `mkvtoolnix`: "Save the correction into the file" writes Matroska's StereoMode with mkvpropedit.
- `kde-cli-tools`, `kscreen`: "Display Settings…" opens the display page with kcmshell6.

## The sentences

English is the source. The menu's words are the stereo layer's (`Stereo::FileChoiceMenu`, `Stereo::NoSound`), copied from its catalogues into Celluloid's nine by the lane's `celluloid-po.py`; `tests/no-sound-wording/check.py` fails when the copy of "This film has no sound." drifts.

## Credits

Celluloid is written by gnome-mpv with Connor Duncan, Gaurav Narula, Harenome Ranaivoarivony Razanajato, Michael Heyns, Mingye Wang (Arthur2e5), Patrick Griffis, Sun, gipawu, tista500 and xuzhen (its AUTHORS file); Debian's packaging is by Ximin Luo and Danial Behzadi (Debian Multimedia Maintainers).
The render API it draws with is mpv's, written by wm4; GtkGLArea is Emmanuele Bassi's, GDK's subsurfaces and colour states Matthias Clasen's and Benjamin Otte's.
Upstream does not take changes written with AI assistance (its README), so this patch is the edition's and is not offered.
