# Diagnose packed SEI transport

`vaapi-packed-sei.py` measures where a frame packing arrangement SEI disappears.
It generates a marked H.264 source, transcodes it through both VA-API encoders, and compares that baseline with a client that submits a raw packed SEI before the first packed slice header.
The C shim does not inspect or change the encoded buffer.

Run only in a disposable container with the intended render node explicitly passed through, core dumps disabled, no desktop sockets, and at most four CPUs.
The test needs Python 3, GCC and libc development files, libva development files, vainfo, and FFmpeg with libx264, h264_vaapi, hevc_vaapi, showinfo and trace_headers.
Install the driver under test from published packages and record its version.
Use the build tree's HTTPS apt helper for any package installation.

Inside that container, as an unprivileged user with render-node access:

```sh
ulimit -c 0
python3 vaapi-packed-sei.py --run /writable/new-evidence-directory
```

Exit 0 means both encoders preserved the submitted type-3 SEI for eye orders 1 and 2, software decoding recovered the same layout/order, the coded picture NALs were unchanged, and the same byte check rejected the unmarked baseline with exit 1.
The original client must have received stereo side data but submitted no FPA.
This is a diagnostic for that specific symptom, not a general encoder test suite.
The four result rows and every command's log are retained beside the streams.

HEVC's `general_non_packed_constraint_flag` is recorded separately.
If it remains 1, the added FPA conflicts with the profile constraint: passing transport and decode checks does not make that diagnostic stream conformant.
A real encoder change must clear the relevant general and sublayer constraints as well as generate the SEI, following H.265 V11 §7.4.4, pp.90–91.
The fixture intentionally does not change the client's parameter sets.

The fixture is side by side only; it does not qualify all packings, persistence, temporal pairing, multiple slices, other profiles, VCE/UVD encoders or Intel drivers.
H.264 V16 §D.1.26, pp.346–347 and §D.2.26, pp.387–391 define its payload; H.265 V11 §D.2.16, p.302 and §D.3.16, pp.350–353 define the HEVC payload.
The independent NAL parser, FFmpeg trace_headers and real decoding are separate checks against those fields.
