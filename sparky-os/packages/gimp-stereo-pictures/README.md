# gimp-stereo-pictures: the stereo pictures plug-in for GIMP 3

The plug-in that opens and saves stereo photographs (MPO, JPS, PNS) as "Left eye" and "Right eye" layers and edits side-by-side pictures one eye at a time or both eyes alike (queue row 101, round 1), packaged from a source package for the first time (queue row 137 with row 148, the stereo GIMP's milestone 1).
The edition's GIMP (package `gimp`, recipe `../gimp`) shows these images per eye.

- **Source:** the plug-in's code lives in [Sparky-OS/PhotoGIMP](https://github.com/Sparky-OS/PhotoGIMP), branch `order137e`; `source.pin` names the commit and the two trees taken, and `make-source.sh` refuses any other.
- **Build:** `build.sh WORK PHOTOGIMP_REPO REPO`: a `3.0 (quilt)` source whose orig tarball is made reproducibly from the pinned trees (its upstream is the PhotoGIMP branch), the catalogues compiled by `msgfmt -c` from the ten languages' `.po` files, installed into GIMP's system plug-in folder `/usr/lib/<triplet>/gimp/3.0/plug-ins/stereo-pictures/`.
- **Tests:** they need GIMP and the stereo layer's fixtures, so the build runs none; the proof runs round 1's tests on the installed package.

## Credits

- Daniel Ramos (Capitain Jack), the plug-in and its MPO writer (from sony-bravia-linux's `bravia_mpo.py`).
- Diolinux, for PhotoGIMP, where the plug-in was first written.
- GIMP's developers, for GIMP 3's plug-in API.
