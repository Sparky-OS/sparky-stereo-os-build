# nvkms-query

Reports what NVIDIA's NVKMS chose for each connected display (bit depth, colour format, range). It runs under Wayland and needs neither X nor nvidia-settings. It is read-only: it never sets an attribute and never changes a mode.

```
SONY TV (HDMI-0) connected bpc=12 format=rgb range=full valid_bpc=6,8,10,12,16
```

## What it reads, and why

It opens `/dev/nvidia-modeset` (root needed) and talks to NVKMS the way nvidia-drm does.

- Framing: `ioctl(fd, NVKMS_IOCTL_IOWR, &NvKmsIoctlParams{cmd, size, address})`, with `address` pointing at the per-command params struct.
- `ALLOC_DEVICE`: `versionString` must equal the module version (built in from `version.mk`, 615.71.09). `deviceId.rmDeviceId` is the RM device instance (0 is the first GPU), as in `nvkms-kapi.c`. There is no "default" id except `NVKMS_DEVICE_ID_TEGRA`, which is for SoCs. NVKMS answers EPERM for an instance that does not exist, which ends the GPU loop. `no3d` is set and console hotplug handling is left enabled.
- `QUERY_DISP`: gives the valid dpy id list. `QUERY_DPY_DYNAMIC_DATA`: name and connected state, with every force/override field zero. `QUERY_DPY_STATIC_DATA` is also called.
- `GET_DPY_ATTRIBUTE`: `CURRENT_COLOR_BPC`, `CURRENT_COLOR_FORMAT`, `CURRENT_COLOR_RANGE`.
- `GET_DPY_ATTRIBUTE_VALID_VALUES` for `CURRENT_COLOR_BPC`: the attribute's value set (an INTBITS mask). This is NVKMS's generic enum, not the TV's EDID capability, so it lists 16 even on a TV that tops out at 12. The chosen value is the `bpc=` field.
- `FREE_DEVICE` at the end.

## Build

`./build.sh [tree] [output]` builds a static binary in a `debian:testing` container (`--cpus 4`, non-interactive apt) against the open-gpu-kernel-modules tree's headers (default `$SPARKY_WORKSPACES/nvidia-16bpc/open-gpu-kernel-modules`). The default output is `$SPARKY_SCRATCH/sparky-os/nvkms-query`.

## Licence

The NVIDIA headers are MIT (`SPDX-License-Identifier: MIT`). `nvkms-query.c` is MIT too.
