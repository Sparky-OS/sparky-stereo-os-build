# proof-pair

Turns one full side-by-side capture (left eye first) into the two pictures the edition publishes as proof: an MPO, the stereo photo format of CIPA DC-007, and a red/cyan anaglyph.

```
./build.sh                                  # once: builds sbs2mpo against Qt 6
./proof-pair.sh capture-sbs.png out/NAME    # writes out/NAME.mpo and out/NAME-anaglyph.jpg
```

- `sbs2mpo` writes the MPO through Qt's image plugins; it needs the edition's KImageFormats with the stereo plugin, which reads the `Stereo3DLayout` text key (`sideBySideLeftFirst`).
- The anaglyph uses FFmpeg's `stereo3d` filter with the Dubois red/cyan matrix (`sbsl:arcd`), the least ghosting of its anaglyph matrices.
