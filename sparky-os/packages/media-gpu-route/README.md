# Shared media GPU routing

Inside Sparky Stereo, this library lets decoder engines follow the display device selected by the graphics stack.
It uses the Vulkan loader order, including Mesa device selection and the compositor's linux-dmabuf feedback.
Explicit driver overrides retain their effect.
GL and Vulkan rendering remain the output engine's responsibility.
This library does not write configuration, choose a monitor mode or change a user's file.

`media_gpu_route_default` reports the first accessible hardware render node without creating a logical GPU device.
`media_gpu_route_decoder` tries GPUs in that order and checks the source codec, profile, depth, chroma and dimensions against VA-API or NVDEC capabilities.
NVDEC queries use a temporary CUDA context on the selected PCI device and restore the previous current context.
Unsupported sources stay in software.
Unavailable capability information is reported as unknown so the calling engine can try its own guarded open; for the GPU chosen for players it is said instead (below).
The optional FFmpeg header adapts `AVCodecParameters` fields to the neutral interface without adding a libavcodec ABI dependency to the library.

Select the decoder before opening it.
Do not change a threaded codec's device from its format callback.
A renderer may still need to download a hardware surface when its import path cannot use that surface directly.
The library does not promise zero copy or that one GPU wins on every machine.

## Copying back is a choice

The order is: hardware decoding whose pictures the renderer uses where they are first, software decoding next, and hardware decoding that copies every picture back to system memory only by choice.
Copying back is slower than software decoding on some machines: on an AMD A10-9600P (Carrizo) with its 3D television, Life of Pi 3D dropped 427.7 frames a minute through mpv's vaapi-copy, against 13.7 in software (ORDER 234).
On Carrizo each copied picture is a blit to a staging copy on the GPU that also composites the desktop, then a read by the CPU.

`media_gpu_route_decoder_frames` takes the caller's frame path.
`MEDIA_GPU_FRAMES_IMPORT` is for a renderer that imports the decoder's surfaces, and gets the capability answer.
`MEDIA_GPU_FRAMES_COPY` is for a caller that copies every picture back (MLT, VLC's copy path), and gets software unless copying back is allowed.
`media_gpu_route_decoder` and `media_gpu_route_av` keep their 0.1 signatures and are the copy-back caller's choice.
`media_gpu_route_av_frames` is the FFmpeg adapter with the frame path.

`media_gpu_route_copy_back` says whether copying back is allowed without the person choosing it in the program:
- `MEDIA_GPU_ROUTE_COPY_BACK` (true or false), for one start;
- `CopyBack` in group `[Decoding]` of `sparky-stereo-graphicsrc`: the person's file in `$XDG_CONFIG_HOME` (`~/.config`) over the machine's measured record in `$XDG_CONFIG_DIRS` (`/etc/xdg`), the first system directory being the most important, as KConfig reads them;
- otherwise not allowed.
A program's own choice of a copying decoder (mpv's `auto-copy` or `vaapi-copy`, VLC's and Kdenlive's explicit decoders) stays the person's choice and is never overridden.

## The Graphics page

Where players draw is the person's choice on the Graphics page (`sparky-stereo-graphics`); Automatic there is the GPU measured best on the machine for playback, whatever the power profile.
When `sparky-stereo-gpu-env` is installed and copying back is allowed, a copy-back caller decodes on the render node it names for players (`--category players --print render-node`), asked again at each choice.
Nothing changes GPU without telling (Daniel, 2026-11-01: "either it works or not and the user must know"):
- A source that GPU cannot decode in hardware is decoded on another GPU that can, and that is said: the page's "Decode on another GPU", on by default. Turned off (`OtherGpu=false` in group `[Decoding]` of `sparky-stereo-graphicsrc`, the person's file over the machine's, or `MEDIA_GPU_ROUTE_OTHER_GPU=false` for one start), such a source is decoded in software, and that is said.
- A page that fails (it says why itself, on the same stderr), answers nothing, or names a GPU this program cannot open, and a GPU whose VA-API or NVDEC driver does not answer, are said, and nothing decodes on another GPU in their place.
- `media_gpu_route_decoder_said` gives the reason in the person's language (the edition's nine, chosen from `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` and `LANG` as gettext does) and returns -2 when the GPU chosen for players cannot be resolved. The 0.2 entry points that MLT and VLC call answer software (0) then, since they take another GPU on -1, and write the reason to stderr.
A caller that imports decoded surfaces, and `media_gpu_route_default`, keep the graphics stack's order: the renderer draws on the GPU the program was started on, and the decoder must be on that GPU for the import to work; the page's launch environment (`sparky-stereo-gpu-run`, KDE's per-program setting) is what moves such a program.
A GPU chosen at launch (`DRI_PRIME`, `MESA_VK_DEVICE_SELECT`, `VK_LOADER_DRIVERS_SELECT`, an NVIDIA offload) wins over the page, and the page is then not asked; a computer without the page has nothing to ask.
`media_gpu_route_copy_back_off_text` is what a player says when a conversion needs the decoded pictures in memory and copying back is off (mpv's 3D conversion).
`tests/graphics-page.sh` checks this on two real GPUs (with `AV1=1`, a pair where one decodes AV1 and one does not), `tests/page-order.sh` and `tests/unresolved.sh` without any.

`media_gpu_route_vulkan_import` says whether a Vulkan renderer on a GPU can import decoded surfaces: dma-buf memory (`VK_EXT_external_memory_dma_buf`) laid out by DRM format modifiers (`VK_EXT_image_drm_format_modifier`), which libplacebo requires.
Mesa's RADV offers the modifier extension from GFX9 on (`radv_physical_device.c`, `gfx_level >= GFX9`), so GFX6 to GFX8 GPUs such as Carrizo, Stoney, Polaris and Hainan are copy-only for Vulkan renderers.
OpenGL renderers import dma-bufs through `EGL_EXT_image_dma_buf_import`, which needs no modifier.

`media-gpu-route-query --capabilities` lists every GPU with its Vulkan import and the copy-back choice; `--decoder CODEC PROFILE BITS WIDTHxHEIGHT copy|import` prints the choice for a source.
`tests/capabilities.sh` checks both with Mesa's amdgpu drm-shim (Renoir: import present; Stoney and Polaris12: copy-only; no GPU: none) and, with `RENDER=1`, on a real render node.

Build with CMake and the installed Vulkan, DRM, VA-API and nv-codec-headers development packages.
NVIDIA libraries are loaded only for a discovered NVIDIA device.
The edition's matched NVIDIA driver transaction supplies the CUDA and NVDEC runtimes.
Tests in the adjacent `hardware-decode/tests/routing` directory use private container compositors and recorded analytic fixtures.
The existing release packaging and Lean Code pipeline follows the plain source build.
Elsewhere, these integrations can be proposed to the respective projects after their contribution review.
