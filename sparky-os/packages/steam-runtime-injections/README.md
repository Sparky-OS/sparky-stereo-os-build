# Steam Runtime stereo injections

Prepare the successor source from the exact published descriptor using
`prepare-source.py NAME PREDECESSOR OUTPUT --epoch SOURCE_DATE_EPOCH`.
GL's explicit preloads keep the saver-qualified interposer binary.
DXVK builds the architecture-independent setup package with `dpkg-buildpackage -A`.
It uses the published PE32 and PE64 payloads.
The prefix setup copies with reflinks where available, as DXVK's former setup script did.
wiz3D keeps its temporary injector alongside the displaced original D3D9 library.
Relative links inside the prefix make the copies visible in the same places under Wine and pressure-vessel.
The injector writes its state under the shared Wine drive so the declaration helper can read it from the outer session.

Valve's Proton uses a shared compatibility tool tree and its `pfx_copy` helper for prefix files.
The edition's tools take their payload from the distribution's `/usr`, which pressure-vessel maps under `/run/host/usr`.
A prefix-local copy avoids depending on either mount layout.
