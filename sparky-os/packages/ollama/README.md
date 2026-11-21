# Ollama, split by hardware

Ollama 0.40.16 (MIT, https://github.com/ollama/ollama), upstream's own release build for Linux amd64 and its ROCm bundle, repackaged for Sparky Stereo OS (ORDER 70).
It is the local engine the edition's Partners page turns on: nothing runs and nothing is downloaded until the person chooses it there.

## The packages

| Package | What it holds | Installed size, measured |
| --- | --- | --- |
| `ollama` | `/usr/bin/ollama`, the processor runners and llama.cpp's libraries in `/usr/lib/ollama`, the Vulkan runner (AMD, Intel and NVIDIA cards) and the user service | 120 MB |
| `ollama-cuda` | the CUDA 13 runner (`/usr/lib/ollama/cuda_v13/libggml-cuda.so`), for NVIDIA cards of the Turing generation and newer | 281 MB, plus NVIDIA's CUDA 13 libraries from NVIDIA's repository |
| `ollama-rocm` | the ROCm 7.2 runner with AMD's ROCm 7.2.1 libraries | about 2.7 GB |

The runner packages Enhance `ollama`; which one a computer gets is the hardware setup's answer, never every one of them.

## How the release is checked

The release publishes no signature for its Linux bundles.
`release.tsv` pins each input by size and SHA-256; `make-orig.sh` checks them, and checks both bundles against the release's own `sha256sum.txt`, which comes from the same origin as the files.
The tag's source is pinned by its tarball's SHA-256, the commit its pax header names (d63b702609c4300a2ca07be2bdb0adb9834725e5) and the git tree id of its files (5d6b350951162c38b342985c12ebd10e7522dfeb).
The package build checks every installed file against `release/MANIFEST.sha256` again.

## What is left out, and why

`release/EXCLUDED.tsv` (installed as `/usr/share/doc/ollama/EXCLUDED.tsv`) lists each file with its size, SHA-256 and reason:
- **NVIDIA's CUDA libraries** (`libcudart`, `libcublas`, `libcublasLt`, `libnvrtc`, `libnvrtc-builtins`, `libnvJitLink`, `libnvfatbin`): NVIDIA's CUDA EULA (last updated 2026-01-26) lets "applications developed by you" carry the files of its Attachment A, and `libnvfatbin` is not in that list. The edition did not develop Ollama, so these come from NVIDIA's repository on the person's machine: `ollama-cuda` depends on NVIDIA's `cuda-cudart-13-*`, `libcublas-13-*`, `cuda-nvrtc-13-*`, `libnvjitlink-13-*` and `libnvfatbin-13-*`, which put `/usr/local/cuda-13/targets/x86_64-linux/lib` on the loader's path.
- **The CUDA 12 runner** (1.32 GB): NVIDIA's CUDA 12 runtime (`libcudart.so.12`) has no package in NVIDIA's repository for Debian 13 nor in Debian, so the runner could not load. Cards that run only CUDA 12 (Maxwell, Pascal and Volta on NVIDIA's 580 driver) use the Vulkan runner.
- **GCC's OpenMP library**: no file of the bundle links it.
- **libdrm, libdrm_amdgpu, libnuma and libelf** of the ROCm bundle: Debian ships them, and `ollama-rocm` depends on Debian's.
- **The MLX bundle** (1.21 GB, MLX on CUDA 13) is not packaged: it would be a third copy of a GPU runtime, with no machine here to prove it.

AMD's ROCm libraries stay in `ollama-rocm`: Debian ships ROCm 6.4, and the runner needs ROCm 7.2's `libamdhip64.so.7`.
Their licences (MIT, BSD 2-clause, NCSA, Apache 2.0 with LLVM exceptions) allow redistribution; the bundle carries no texts, so `make-orig.sh` takes them from AMD's repositories at the tag `rocm-7.2.1`, pinned by SHA-256.

## The service

`ollama.service` is a user service, installed with `dh_installsystemduser --no-enable`, so nothing is enabled or started at installation.
It listens on `127.0.0.1:11434` only (`OLLAMA_HOST`) and lets mail add-ons in Thunderbird and Betterbird call it (`OLLAMA_ORIGINS=moz-extension://*`, ThunderAI's documented setting).
Models are kept where Ollama keeps them, `~/.ollama/models`, for each person.
Models hosted by Ollama's own service (names ending in `:cloud`) are allowed, as upstream ships it: they send what the person writes to that service, and the Partners page says so beside each choice.
Which graphics card it uses is upstream's own rule until the Graphics page gives it one: every card Ollama finds, Vulkan on.

## Building

```sh
IMAGE=<a Debian testing build image> SPARKY_SCRATCH=<scratch on an SSD> SPARKY_LC_ARCHIVE_DIR=<the link gate folder> bash sparky-os/packages/ollama/build.sh OUT DOWNLOADS
```

The first run fetches the inputs into `DOWNLOADS` (about 2.6 GB) with `ORIG_NETWORK=bridge`; later runs read them from there with no network.
The orig tarballs `make-orig.sh` makes are kept in `DOWNLOADS/orig-0.40.16+ds` and reused (the same inputs give the same bytes); delete that folder to make them again.
The build needs about 15 GB of scratch at its peak. Lean Code's link and start gate needs `SPARKY_LC_ARCHIVE_DIR` with a `sources.json` naming Debian forky and NVIDIA's repository for Debian 13 with their keyrings (`sparky-os/lean/archive.md`); its step reads them over the network, and the gate runs the programs with none.

## Credits

Ollama, by its authors ("Copyright (c) Ollama"); llama.cpp and ggml, by Georgi Gerganov and the ggml authors; AMD's ROCm libraries, by Advanced Micro Devices, Inc.
