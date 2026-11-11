# Play shared media on another screen

Media Devices controls a renderer already known to Universal Media Server.
Choose a file in a folder you already share, then use **Play on TV** or **Play on the headset** in Dolphin or Purpose.
Choose the device explicitly and press **Play Selected File**.
The selected device appears in Plasma's media controls through MPRIS2.

The controller never enables the UMS service, adds a shared folder or starts another file server.
If UMS requires authentication, use **Sign in to UMS**.
The password is sent only to the configured UMS web interface; its session token stays in memory.
The normal address is the local web interface, using `web_gui_port` from UMS.conf.
An explicit `--server URL` is available for managed setups; use HTTPS when sending credentials to a remote server.

Media selection uses UMS's renderer-specific browse and control API.
A generic ContentDirectory browse by the desktop would select the desktop's renderer profile.
Using the chosen renderer's ID lets UMS retain its format conversion, permissions and library decisions.
The controller identifies a local file by its existing shared-folder hierarchy and display name.
Renamed, flattened, virtual or ambiguous library entries can be refused with a visible message; they are never matched by guessing.

AVTransport carries Play, Pause, Stop and relative-time seek.
RenderingControl carries volume and optional brightness.
Service URLs, versions and supported actions come from the selected device's SSDP description and SCPD.
The controller supports the default transport/rendering instance 0.
It does not allocate multi-instance connections or claim DLNA certification.

MPRIS2 exposes the currently selected renderer, not a local playback engine.
Refresh and target changes remove the old MPRIS service before another device is selected.
Track IDs are derived from the current URI; stale SetPosition calls are ignored.
Unsupported actions are disabled and SOAP failures return an error to D-Bus callers as well as appearing in the window.
Periodic polling does not clear an action error.
OpenUri is unsupported; file selection stays in the explicit shared-file actions.
There is no playlist, rate control or repeat/shuffle feature.

The ten-language table is `translations.tsv`.
Run `python3 po/make-po.py` from the source root to regenerate catalogues, menus and Purpose metadata.
Translations are drafts pending native-speaker review.

The local wire test needs an isolated multicast-capable network and a private session bus.
`umsrenderertest` starts its own synthetic UMS API and renderer on loopback, validates SOAP arguments and calls MPRIS from a separate process.
Set `UMS94_CAPTURES` for translated window captures.
`umsrealservertest` is a separate fixture check for an isolated local UMS instance and an emulated headset; it is not run against a person's devices.

Protocol references:

- [MPRIS2 Player interface](https://specifications.freedesktop.org/mpris/latest/Player_Interface.html), methods, properties and PropertiesChanged.
- [OCF MediaServer:4 / MediaRenderer:3](https://openconnectivity.org/developer/specifications/upnp-resources/upnp/mediaserver4-and-mediarenderer3/), AVTransport:3 and RenderingControl:3.
- AVTransport:3 §5.4.14, Seek: REL_TIME is an absolute offset within the current track, in contrast to MPRIS Seek's relative microsecond offset.

Credits: Universal Media Server's SubJunk and team, jUPnP, KDE Frameworks Purpose and KIO contributors, and the MPRIS authors.
