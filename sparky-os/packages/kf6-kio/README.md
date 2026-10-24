# kf6-kio: Plasma's launcher on the Graphics page's GPU

Rebuild the edition's published kf6-kio 6.30.0-1+stereo3d5+lc1 as 6.30.0-1+stereo3d6+lc1 with one more patch, `patches/EDITION-ONLY-run-applications-on-the-GPU-of-the-graphics-settings.patch`.

KIO decides where an application started from its desktop entry runs in one place, `KProcessRunner::fromApplication` (`src/gui/kprocessrunner.cpp`): an entry with `PrefersNonDefaultGPU=true` gets `KIO::discreteGpuEnvironment()` (`src/gui/gpudetection.cpp`, from switcheroo-control, else Solid's `hasDualGpu`), every other entry starts with the session's environment.
The patch adds the other entries: when the entry sets neither `PrefersNonDefaultGPU` nor the older `X-KDE-RunOnDiscreteGpu`, and the launch environment chooses no GPU (`DRI_PRIME`, `MESA_VK_DEVICE_SELECT`, `VK_LOADER_DRIVERS_SELECT`, `__NV_PRIME_RENDER_OFFLOAD`, the variables libmedia-gpu-route also leaves to the launch), KIO runs `sparky-stereo-gpu-env --app MENU-ID` (or the desktop file's absolute path when it is outside the menu) and starts the application with the `VARIABLE=value` lines it prints.
That is the Graphics page's resolver (`sparky-stereo-graphics`), the same command `sparky-stereo-gpu-run` and libmedia-gpu-route ask; KIO keeps no policy of its own.
A missing command, a non-zero exit or no answer within two seconds leaves the launch as it was.
D-Bus activated applications (`DBusActivatable=true`, started without files) are started by the session bus and get neither KDE's own key nor this answer, as before.

The tests are in `autotests/applicationlauncherjobtest.cpp` (`shouldRunOnTheGpuOfTheGraphicsSettings`, twelve rows with a stand-in resolver); Debian's build does not run them (`BUILD_TESTING=OFF`).

## Build

`build.sh` runs as root in a freshly updated Debian testing container whose APT has the published edition repository at priority 1001.
It takes the predecessor source from the signed index (`SPARKY_PUBLISHED_TREE`), checks every file the `.dsc` names against it, adds the patches after the existing series with quilt, writes the changelog entry once, installs the build dependencies and builds as UID 1000 with the source's own Lean Code hooks.
It then runs `lean.release check-debs` and `check-link --previous-dir "$SPARKY_LC_PREVIOUS_DIR"` (the predecessor's binary packages) from `SPARKY_RELEASE_TOOLKIT` (this tree's `sparky-os`), and stages the archives with `SHA256SUMS` in `OUT`.
Only amd64 is built, as for the predecessor; no i386 twin exists for kf6-kio.
