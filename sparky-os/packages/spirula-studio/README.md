# Spirula Studio

Create a 3D model from photos or video, then inspect it in stereo.
This recipe builds the edition's fork of Harry Chen's Spirula Studio.
The application is GPL-3.0; the optional processing profiles retain their publishers' own terms.

`spirula-studio` installs the Vulkan application, menu entry and shared profile declarations.
`spirula-studio-cuda` adds the same program with CUDA training, selected by its menu action or `--compute-backend=cuda` as the first argument.
Graphics supplies one stable GPU identity for training, structure from motion and inference.
Native patented video is disabled; video decoding and extraction use the edition's external FFmpeg.

Each `spirula-studio-model-*` package selects one processing profile independently.
It contains no weights: installation shows the pinned publisher, byte count, metered notice and verbatim terms before downloading anything.
A required licence answer starts at No.
The program opens the missing profile's AppCenter installation page rather than fetching on first use.
Removal keeps downloaded models; purge removes installer-owned data, preserving files owned by the person and data shared with another profile.

Build inside an updated Debian testing container with the edition's signed repository and the house HTTPS apt helper.
Mount the CUDA 13.5 toolkit read-only at `/opt/cuda`, or install NVIDIA's `cuda-nvcc-13-5` and `cuda-cudart-dev-13-5` and point `/opt/cuda` to that toolkit.
The NVIDIA hardware setup already configures the edition's CUDA repository and driver lock; the CUDA runtime remains NVIDIA's separately installed package.
No driver, toolkit, processing model or GPU is needed by the Vulkan runtime package itself.
The pinned Slang compiler is a build tool downloaded into disposable `slang/`, excluded from both source and runtime payloads.
GLFW, Dear ImGui and the CJK fonts are declared source components with their original notices.

Set `SPIRULA_SOURCE` to the clean, committed fork checkout, `OUT` to an owned output directory, and run `build.sh` with at most four build jobs.
It composes a `3.0 (quilt)` source from upstream b8e15cb8 and the edition patch, retains the native Lean Code source-consumer plan, and uses ordinary debhelper with the qualified payload and link/start gates.
The generated `.dsc`, `.buildinfo` and `.changes` retain the build identity and checksums.
Run the source checks before the build projection, backend parity on both GPUs, and the installed-package stereo rig against the accepted compositor and Mesa cohort.

The application belongs on Graphics/Editors and Stereo players, editors and tools in AppCenter.
The accepted role mapping is designer and creator, as Suggests; this recipe changes neither role list.
