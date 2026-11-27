# Stereo element depth protocol

`plasma-wayland-protocols` +stereo3d14 carries the version 7 `element_limit` event with two fixed-point distances for the selected output. The compositor sends the event before `output_width` and closes the group with `depth_limits`. Earlier events keep their wire order.

Prepare the source with `prepare-source-14.sh` from the +13 closure. The sources used for initial qualification have `SOURCE_DATE_EPOCH=1795728008`. The package build runs the virtual stereo contract test and the Wayland scanner suite.

The protocol package is the work of the KDE Plasma Wayland Protocols contributors. The edition's stereo content and depth protocol carries Daniel Ramos's design and implementation.
