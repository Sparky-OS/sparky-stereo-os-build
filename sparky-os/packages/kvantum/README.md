# Kvantum with the scroll arrows together

Debian's kvantum 1.1.8-1 (Tsu Jan's [Kvantum](https://github.com/tsujan/Kvantum), packaged by the LXQt Packaging Team), rebuilt as 1.1.8-1+stereo3d1+lc1 with one patch.

## What the patch does

A theme can now set `scroll_arrows_together=true` in its `[%General]` section.
Both scroll arrows then sit together at the end of the scrollbar: the bottom of a vertical one, the right of a horizontal one, the left in right-to-left layouts.
The groove starts at the other end.
This is how the classic Mac OS scroll bars could be set from Mac OS 8.5, and the Kubabbar Glass 9 look uses it (queue row 147).

Only `subControlRect()` changes, in the Qt 6 plugin (`style/Kvantum.cpp`) and the Qt 5 one (`style/qt5/Kvantum5.cpp`), with the key read by both theme parsers and described in `doc/Theme-Config`.
Kvantum draws the scrollbar and Qt finds what a press hits through `subControlRect()`, so drawing, pressing and holding an arrow follow the new place.
A theme without the key is unchanged, and the key does nothing when `scroll_arrows` is false or the scrollbars are transient.

## Upstream first

Searched on 2026-11-26: Kvantum's releases up to V1.1.9 (2026-11-08) and the unreleased V1.1.10 in its ChangeLog have no such option, and the five issues that mention scroll arrows (#3, #76, #196, #530, #862) ask for other things.
So the patch is ours; a heads-up to Tsu Jan is drafted, not sent.

## Build

`build.sh WORK PREVIOUS_DIR SOURCE_DIR` builds the source package once, then the binaries with Lean Code and the link gate, then runs the test.
`SOURCE_DIR` holds Debian's source package, checked against `source.sha256` (the sums its signed `.dsc` lists); `PREVIOUS_DIR` holds Debian's 1.1.8-1 binaries.

## Test

`tests/scroll-arrows/test.sh OUT EXPECT [DEB...]` builds a probe for Qt 6 and Qt 5 that asks the style where each part of a 200 pixel scrollbar is and what a press at each arrow's centre hits, vertical, horizontal and right to left, with a theme that sets the key and one that does not.
`EXPECT=together` must pass on this build; on Debian's build it must fail, and `EXPECT=ignored` must pass there (the red run and its control).
