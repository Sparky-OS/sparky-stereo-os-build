# DXVK packed-eye copy correction

`patches/packed-eye-exact-copy.patch` applies after the patches in the edition's DXVK `2.7.1-4+stereo3d3+lc1` source descriptor.
The published descriptor's Debian rules remain the package recipe; this directory does not replace its native, PE32, PE64, debug-symbol or Lean Code build steps.

When a packed eye has exactly the size of its destination half, interpolated texture coordinates can round across a texel boundary.
The one-to-one copy now uses integer framebuffer coordinates.
Source and destination extents must match without truncating fractional half-widths; scaling continues through the existing sampler.
The C++ and GLSL push-constant layouts change together.
Normal mono presentation and color-space conversion retain their existing paths.

The synthetic D3D9 and D3D11 fixtures in `../wine-stereo/tests/` upload the same coordinate-labelled packed image, then resize.
`check-d3d9-pair.py` checks their raw X11 captures without tolerance.
Capture is signaled after the eleventh Present, so these fixtures do not assert first-Present timing.

Measured with the AMD Vulkan provider, the old D3D9 PE64 copy has 718 wrong pixels at 320x200 and 574 at 256x160, each with maximum channel error one.
The corrected PE32 and PE64 copies and their mono controls are exact at both sizes.
Stereo ScreenShot2 captures additionally require a compositor declaration; this shader patch alone does not supply that declaration.

The DXVK/Wine declaration handoff remains a separate owner and lifecycle change.
Do not treat this patch, a private module substitution, or these bounded pixel controls as a complete DXVK package/release qualification.
Other packed layouts, scaled rectangles, HDR, native DXVK and NVIDIA still require their applicable controls before release.

### Versioned Wine surface request candidate

`patches/wine-wsi-v1-request.patch` applies after the published DXVK `2.7.1-4+stereo3d3+lc1` patches.
It is independent of the exact-copy patch above.
`prepare-source.py SOURCE --toolkit TOOLKIT` appends this patch and the exact-copy patch to a fresh extraction of that descriptor and prepares version `2.7.1-4+stereo3d4+lc1`.
It normalizes the older descriptor's trailing Lean Code build-dependency list before the current toolkit's checked plain-source conversion.
It preserves the native and Windows build targets, symbols, package set and ordinary fallback.
Create one descriptor, then build every architecture from it; source preparation alone is not package qualification.

D3D9 and the packed-input DXGI surface factory scope a version-1 request to the Windows thread creating the Vulkan surface.
The Wine runtime owns the native content declaration and acknowledges a complete child-surface contract.
The producer restores any previous Win32 property value after the call.
Failure to set the hint, an old runtime or an old compositor retains ordinary surface creation instead of turning an optional hint failure into allocation failure.
Native stereo array swapchains remain on their existing path.

The matching Wine patch requires libstereo-declare 1.8 and the compositor's version-9 child-shape consumer.
PE32 and PE64 D3D9 acknowledgement, old-runtime and old-compositor fallback have private-module evidence.
D3D11's versioned path, injected property failures and restoration, native DXVK, packaging and GPU coverage still need their own gates; the earlier unversioned D3D11 proof is not a proof of this new handshake.
