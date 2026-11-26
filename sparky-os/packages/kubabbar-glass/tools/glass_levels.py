#!/usr/bin/env python3
"""The Kubabbar family's glass, in one place: every look of the family (Kubabbar Glass, Kubabbar Glass 9) draws its
Plasma style's backgrounds at these levels, so a change here reaches the whole family at the next generation.
GPL-3.0-only."""

# Sparky Black's levels, transplanted (Daniel, 2026-10-15: "both, kubabbar glass and stereo oxygen must carry the same
# transluscent configs every where (Sparky Black transluscent levels transplanted to both sparky stereo themes)"):
# the 8-bit alpha of each surface's centre as KSvg draws Sparky Black's Plasma style (QSvgRenderer, by element id;
# queue row 125). Each look keeps its own colours and drawing; only the level comes from Sparky Black. A panel's
# level depends on its edge, as in Sparky Black; "" is the centre without a prefix.
SPARKY_BLACK_ALPHA = {
    "widgets/panel-background": {"": 164, "north": 44, "south": 129, "east": 44, "west": 44},
    "dialogs/background": {"": 157},
    "widgets/tooltip": {"": 157},
    "widgets/background": {"": 80},
    "widgets/translucentbackground": {"": 60},
}

# Qt's 256-step painter opacity must render the nearest 8-bit alpha to 91%: 232. The solid/ and opaque/ variants keep
# it: Plasma draws them for a panel the person set to Opaque (or Adaptive beside a maximized window) and without
# compositing.
BACKGROUND_ALPHA = 233 / 256


def painter_opacity(alpha):
    """The opacity Qt's 256-step painter turns into this 8-bit alpha: the smallest k/256 that it rounds to alpha,
    (255 * k + 128) // 256 == alpha (233/256 gives 232; checked by rendering with QSvgRenderer)."""
    k = next(k for k in range(257) if (255 * k + 128) // 256 == alpha)
    return k / 256


def level(path, prefix, variant):
    """The opacity of a frame element: the transplanted level, or 91 % in the solid/ and opaque/ variants."""
    if variant in ("solid", "opaque"):
        return BACKGROUND_ALPHA
    return painter_opacity(SPARKY_BLACK_ALPHA[path][prefix])
