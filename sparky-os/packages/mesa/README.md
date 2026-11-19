# mesa recipe

Patch `patches/0045-glx-a-stereo-child-is-declared-once-its-window-is-viewable.patch` (ORDER 50 step 2) is kept here and is in no `next-source-*.sh` list, so no Mesa version or series changed.
It waits for the next Mesa build (stereo3d27): a GL child of a Tk window (Netgen's drawing area) is declared once its window is viewable.
Proof so far is a whole-Mesa stand-in build (softpipe), unpatched 3 of 3 flat against patched 3 of 3 stereo; see skill native-linux, references/x11-declared-child-limits-and-first-pair.md.
