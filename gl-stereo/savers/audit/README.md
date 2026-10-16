# All-saver diagnostic inventory

This directory starts the 2026-10-14 milestone from the accepted installed packages.
It is not the trusted rotation catalogue.
All 130 savers remain pending the new qualification contract.

`inventory-6.09.json` records the installed payload of xscreensaver-gl and xscreensaver-gl-extra 6.09+dfsg1-2+stereo3d1.
The 86 and 45 payload entries contain 130 standalone savers and `mapscroller.pl`, Mapscroller's helper.
The helper is retained as a dependency, not presented as a standalone saver.
Each record preserves its executable hash, original XML settings hash, authors named in that XML and credit records with source line numbers.
The `companioncube` executable uses the `companion*.c` sources, as recorded by XScreenSaver's Makefile.
Contacts are omitted from the generated credit records.

Run these commands inside the lane's accepted package proof container, with the checkout at `/workspace/gl-stereo` and scratch at `/build`:

```sh
python3 /workspace/gl-stereo/savers/audit/inventory.py /build/source/xscreensaver-6.09 /build/inventory.json
python3 /workspace/gl-stereo/savers/audit/sweep.py /build/inventory.json /build/new-sweep /workspace/gl-stereo/measure-hack.py
```

The source is the accepted Debian original tarball, SHA256 `678cbcbe8e15cc5789c9a9cec8e5419a001668dd7cbb884c11ca7ffe9ff4600e`.
The sweep needs a new output directory and rejects changed executable hashes.
Optional trailing saver IDs select a smaller diagnostic run.
Every command retains stock options apart from window mode and geometry.
Each case has its own Xvfb server, software rendering, four Mesa threads and an eight-second budget to reach frame 30.
No KWin support property is simulated.
Raw colour and depth dumps are discarded after checking; eye PNGs, logs and measurements remain.

`diagnostic-6.09.json` is the complete 130-case sweep using gl-stereo 0.2.0-1 from `gl-stereo-package-proof:3`.
The installed layer SHA256 is `429338301caa199d036c7c24e6e1b85ecdd4933c558336d940516f8e8d3ac0bb`.
There were 127 captures, 68 passing depth probes and 19 captures with pixel-identical eyes.
No display-number write failure occurred after the pipe-reader fix.
The three commands without a capture within the probe budget were flipscreen3d, glslideshow and mirrorblob.
A missing frame or failed depth oracle does not establish a rendering bug or that a scene is flat.
Random defaults, startup delays, orthographic views, shader cameras, sparse edges and absent depth writes require individual investigation.

The 68 passing probes do not prove the requested stock-2D identity, all overlays at the screen plane, preservation of each setting or LEFT/RIGHT composition under Stereo KWin.
No entry is promoted by this script, and both generated JSON files are rejected by the existing trusted-catalogue loader.
The three final classification groups are therefore unassigned, with 130 qualifications pending.
The prior five-saver catalogue remains unchanged.
Full diagnostic evidence is in `out/all-savers/sweep-fixed/`; REPORT.md at the workspace root records the milestone status.

## Stereo KWin and deterministic input fixtures

The resumed audit image is `gl-stereo-all-savers:1`, built from the accepted amd64 proof image with this directory's Dockerfile.
The container uses four CPUs, UID/GID 1000, scratch `/mnt/build/gl-stereo/all-savers` mounted at `/build`, and the workspace at `/workspace`.
The edition repository is mounted read-only at `/var/local/sparky-stereo-repo`.
Only the explicitly permitted `/dev/dri/renderD128` is passed to KWin, with supplementary group 125; no card node or host session is mounted.
Every saver gets a fresh D-Bus, KWin virtual backend and Xwayland session.
The saver uses llvmpipe while KWin uses its OpenGL renderer.

Inside that container:

```sh
gcc -shared -fPIC fixture.c -o /build/fixture-egl.so -ldl -lGL -lX11 -lEGL
gcc -shared -fPIC reference.c -o /build/reference.so -ldl -lGL -lm
g++ ../../plasma/capture.cpp -o /build/capture $(pkg-config --cflags --libs Qt6Gui Qt6DBus)
python3 run-kwin.py /build/new-kwin-run gears molecule
python3 mono.py /build/new-mono-run /build/fixture-egl.so /workspace/gl-stereo/libgl-stereo.so gears molecule
AUDIT_REFERENCE=1 python3 mono.py /build/new-reference-run /build/fixture-egl.so /build/reference.so bubble3d cubestack
python3 compare-composed.py /build/new-kwin-run
```

Run the compile commands from this directory.
Do not replace a mapped shared library while a sweep is running; use a new filename for a changed build and `AUDIT_LIBRARY` for the KWin driver.
The fixture controls the saver's seed and clock, captures frame 120, swaps and stops that process before KWin captures it.
It intercepts both GLX and EGL, because these Debian savers implement glXSwapBuffers locally using EGL.
Mesa and KWin keep their own real clocks.
`AUDIT_TARGET` changes the requested frame; `AUDIT_STOCK_REPEAT=1` compares two stock runs to investigate nondeterministic input.
The fixed clock does not yet make all text/image helper inputs reproducible; mismatches are retained, never automatically dismissed.

The independent reference renders one ordinary window and one eye using Mesa's glFrustum plus glTranslated, without the production layer.
Its synthetic three-depth pair passes the analytic centroid check.
It supports canonical projection matrices and camera translation in the projection.
It also takes the camera from GL_MODELVIEW under an identity projection, as Star Wars draws: the modelview is a canonical perspective times a view that rotates, translates and scales uniformly; the perspective is recovered from it and the eye's camera reaches the projection as that camera times the perspective's inverse, leaving the modelview untouched.
`test-reference-modelview.sh` checks that form on the analytic three-quad scene (`tests/quads` with `TEST_MODELVIEW_CAMERA`), and checks that the same measurement fails without separation.
It is not a general reference for arbitrary offscreen effect chains or rotated combined projection/view matrices.
REFERENCE_LIST_PRIMITIVES=1 uses Mesa's display-list primitive rasterization in the oracle, while keeping the independently constructed single-eye frustum.
GLBlur needs that control to eliminate accumulated immediate/display-list raster differences.
Its left/right outputs are comparison evidence, not automatic eligibility receipts.

`compare-composed.py` requires exact producer/KWin interior pixels and rejects exchanged eyes for distinct-eye scenes.
It excludes only the four 8-by-8 bottom corner squares where KWin rounds decorated windows, separately for each eye.
The full captures and measured differences are retained; this exclusion is unrelated to the separate exact stock-2D comparison.
Splitflap's former mismatch was an unresolved multisample CPU readback; the explicit readback resolve now matches KWin exactly.

`tests/saver-oracle.py` exercises the revised spatial-variation guard using the dim Circuit capture, plus empty, uniform-red and reversed-eye negative controls.
`test-projection-view.sh` compares the original mapped library with `/build/projection-view.so` on the translated-camera analytic scene.
No diagnostic script in this directory promotes a saver into the trusted rotation.

## Flat scenes and text input

`flat-scenes.json` names the source-reviewed orthographic or picture-only candidates.
`check-flat.py` requires a nonempty image whose best eye alignment is exactly zero, with less than 0.001 changed pixels and a mean difference below 0.02/255.
Mesa viewport translation produces sparse rounding differences even at zero parallax; these measured limits do not relax the separate pixel-exact stock/disabled test.
The shifted-image negative control must be rejected.
`AUDIT_TEXT` names a test-only text file supplied synchronously at the saver's existing text-generator boundary.
This controls both text content and arrival time, leaving the saver's options and installed settings unchanged.

## Final installed qualification

The diagnostic history above remains a baseline, not the final result.
The final gate is `compile-qualification.py`, fed by `collect-installed.py` and complete installed-file sweeps.
It requires a nonempty exact stock/disabled 2D pair, unchanged XML settings, exact binary hashes, a full-SBS declaration and KWin composition for every standalone saver.
Stereo scenes additionally need either the depth oracle or independent per-eye reference images with an unambiguous wrong-eye rejection.
The camera references are ordinary one-eye Mesa frusta; production shaders remain unchanged.
The flat list is source-reviewed and tested for zero alignment rather than given artificial depth.

Most inputs use a deterministic seed and clock at frame 120; startup scenes use frame 600.
References are rendered in the same KWin and Xwayland session type as the captures (`AUDIT_REFERENCE_EYE`): a reference made on Xvfb drew text with that server's fonts and differed from the composed capture (unicrud's labels).
FlipText's replay repeats its final frame, and the first rendering of that frame differs from its repeats; its capture and both references are frozen on the same repeat (`AUDIT_TARGET` five swaps past the trace's last frame), where the layer also dumps the frame the composition check compares.
Asynchronous helper inputs use identical recorded GL calls for the 2D control.
FlipText's stereo reference uses recorded input too, because text arrival changes its animation's random choices.
`AUDIT_RECORD_FIXTURE` and `AUDIT_RECORD_TEXT` supply synchronous neutral text when recording that fixture; `AUDIT_RECORD_SECONDS` (default 12) gives the recording more time on a loaded machine, so that the text has appeared by the trace's last frame.
The replay snapshot set includes a later sentinel call, preventing retrace's early exit after its last requested snapshot; each case still owns a fresh KWin session.
This is a test fixture only: the production layer dispatches camera draws directly and records no frame.

The trusted package manifest is `savers/qualification-6.09.json`.
`install-qualified.py` requires all 130 original IDs, the same stripped library, saver executables and XML settings, and all qualification flags.
`test-qualification.py` rejects missing or duplicate entries, unknown savers, stale binaries/settings and false proof flags.
The 130 entries combine with the accepted Starfield and Rocks receipts to form the 132-entry rotation.
Trim recorded fixtures by complete frame numbers, then read the resulting trace's call numbers again with `apitrace dump --calls=frame`.
Nested fixture queries can complete before their enclosing swap call; trimming by the enclosing entry number alone can omit that swap, and the trimmer can renumber those interleaved calls.
A capture must never accept a missing final swap or an empty frame as proof.

Flurry is an owning-place fix, not a flat scene: its original CPU code divided the particle's x/y by z before submitting OpenGL vertices.
The XScreenSaver patch exposes that existing camera and each trail endpoint's depth while keeping the original disabled path.
`check-flurry.py` requires the independent camera match, rejection of the former flat image, exact pre-patch 2D pixels, equal simulation timing-query counts and exact KWin composition.
The final classification includes ten flat scenes; `owning-fixes.json` records the source-level exception.

A clean rebuild can change DWZ debug-sidecar links without changing a saver's loaded image.
`debug-equivalence.py` permits differences only inside `.gnu_debugaltlink` and `.gnu_debuglink` sections that have no allocation flag and overlap no load segment.
File length, ELF headers, all section/program headers, executable bytes and every other byte must remain identical.
The gate rejects executable-byte and ELF-header mutations and rejects Flurry's actual camera-code change.
When this narrow equivalence applies, the receipt records both the captured executable hash and the installed executable hash; the compiler rechecks the original file and the byte comparison itself.
The installed catalogue remains bound to the final full-file hash.

## Requalifying after a layer change

The receipts bind the stripped layer, so any change to `libgl-stereo.so` needs all 130 again.
Build the package once with `savers/qualification-6.09.json` removed from the unpacked tree (the bootstrap keeps the accepted five receipts) in the directory the final build will use, so that both builds make the same stripped layer.
Then run `requalify-root.sh` as root in the audit image, with the checkout at `/workspace/gl-stereo`, scratch at `/build`, the bootstrap debs at `/debs`, XScreenSaver's original tarball at `/orig`, `xscreensaver-gl-extra 6.09+dfsg1-2+stereo3d1` at `/old` (Flurry before its camera fix, for the negative control), the edition's repository at `/var/local/sparky-stereo-repo`, `/dev/dri/renderD128` with group 125 and `SYS_NICE` for KWin.
It installs the bootstrap in every container it starts and runs `requalify-steps.sh` as UID 1000, one step at a time; `STEPS` names the steps to run again.
Every input is made here: the KWin sweep (a case that misses its frame under load runs again with a longer budget, its first attempt kept), the warmup, Star Wars and Flurry cases, the references, FlipText's recorded input, the 2D controls, the debug-link equivalence (empty when every capture used the installed executables), the collector and the Flurry check.
The functional suite needs the 132-entry catalogue, so the manifest is compiled once without that gate, installed the way the package build installs it, the suite runs, and `compile-qualification.py` then compiles it with every gate and must give the same file.
Copy `/build/qualification-6.09.json` into `savers/` and build the final package in the bootstrap's directory; its stripped layer must have the hash the receipts name.
