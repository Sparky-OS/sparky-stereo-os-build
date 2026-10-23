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
Unavailable capability information is reported as unknown so the calling engine can retain its normal guarded fallback.
The optional FFmpeg header adapts `AVCodecParameters` fields to the neutral interface without adding a libavcodec ABI dependency to the library.

Select the decoder before opening it.
Do not change a threaded codec's device from its format callback.
A renderer may still need to download a hardware surface when its import path cannot use that surface directly.
The library does not promise zero copy or that one GPU wins on every machine.

Build with CMake and the installed Vulkan, DRM, VA-API and nv-codec-headers development packages.
NVIDIA libraries are loaded only for a discovered NVIDIA device.
The edition's matched NVIDIA driver transaction supplies the CUDA and NVDEC runtimes.
Tests in the adjacent `hardware-decode/tests/routing` directory use private container compositors and recorded analytic fixtures.
The existing release packaging and Lean Code pipeline follows the plain source build.
Elsewhere, these integrations can be proposed to the respective projects after their contribution review.
