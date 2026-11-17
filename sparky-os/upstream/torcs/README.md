# TORCS screen planes by camera mode

The source producer starts from TORCS 1.3.7+dfsg-5+stereo3d2+lc1, verifies its descriptor and keeps the owning libtgfclient Xrandr link correction.
The driver profile uses a 1.8 m screen plane and 0.065 m separation; chase uses 2 m and 0.10 m.
The sky uses the world camera's infinity disparity.

`build.sh PUBLISHED.dsc WORK POOL IMAGE ARCHIVE PLIB_DEBS` prepares the source and builds it with the current toolkit and the new plib packages supplied to both APT and the archive gate.
The plib folder's README describes the shared arguments.
This recipe needs plib 1.8.5-15+stereo3d3+lc1 or newer for its additive per-draw interfaces.

The Graphic section of a person's ~/.torcs/config/graph.xml accepts stereo cockpit convergence, stereo chase convergence, stereo cockpit eye separation and stereo chase eye separation.
Package defaults and code fallbacks agree; existing personal files are left alone.
Explicit PLIB_SSG_CONVERGENCE and PLIB_SSG_EYE_SEPARATION settings override both profiles.
The existing PLIB_SSG_STEREO option enables native rendering; do not also enable a second camera-injection layer.
