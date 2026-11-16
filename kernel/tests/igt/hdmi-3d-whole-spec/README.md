# IGT changes for kernel group 34 (every HDMI 3D structure)

Two changes to IGT GPU Tools that the tests of kernel series group 34-hdmi-3d-whole-spec need.
They were written on 16 October 2026 with that group (ORDER 151, step K) and are kept here so they travel with the kernel series.

- `0001`: `lib/igt_fb` lays out stereo framebuffers for every HDMI 3D structure; before, it asserted on side by side (full).
- `0002`: `lib/igt_kms` declares every HDMI 3D structure in its 3D EDID.

They apply to IGT's master of October 2026 with `git am`.
Offering them to IGT is a separate step (ORDER 157), after group 34's kernel interface settles.
