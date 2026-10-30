# DXVK packed-eye copy correction

`patches/packed-eye-exact-copy.patch` applies after the patches in the edition's
DXVK `2.7.1-4+stereo3d3+lc1` source descriptor. The published descriptor's Debian
rules remain the package recipe; this directory does not replace its native,
PE32, PE64, debug-symbol or Lean Code build steps.

When a packed eye has exactly the size of its destination half, interpolated
texture coordinates can round across a texel boundary. The one-to-one copy now
uses integer framebuffer coordinates. Source and destination extents must match
without truncating fractional half-widths; scaling continues through the existing
sampler. The C++ and GLSL push-constant layouts change together. Normal mono
presentation and color-space conversion retain their existing paths.

The synthetic D3D9 and D3D11 fixtures in `../wine-stereo/tests/` upload the same
coordinate-labelled packed image, then resize. `check-d3d9-pair.py` checks their
raw X11 captures without tolerance. Capture is signaled after the eleventh
Present, so these fixtures do not assert first-Present timing.

Measured with the AMD Vulkan provider, the old D3D9 PE64 copy has 718 wrong pixels
at 320x200 and 574 at 256x160, each with maximum channel error one. The corrected
PE32 and PE64 copies and their mono controls are exact at both sizes. Stereo
ScreenShot2 captures additionally require a compositor declaration; this shader
patch alone does not supply that declaration.

The DXVK/Wine declaration handoff remains a separate owner and lifecycle change.
Do not treat this patch, a private module substitution, or these bounded pixel
controls as a complete DXVK package/release qualification. Other packed layouts,
scaled rectangles, HDR, native DXVK and NVIDIA still require their applicable
controls before release.
