# UVC bulk payload boundaries without a camera

Run in a throwaway container (four CPUs, core limit zero, no USB devices),
with QEMU installed. This exercises the actual static UVC decoders and their
copy operations, queue transitions and clocks. The fixture supplies a stopped
USB controller; it never submits an URB to hardware. The KUnit copy helper
performs the scheduled copies and drops their queue references.

Start with vanilla Linux v7.3.1. Apply group 02 patch 0011 alone to get the
red control: the back-to-back case fails byte count, contents and frame
completion; nine existing-behaviour controls pass, the new capacity guard is
skipped. Apply 0010 as well for green: all eleven pass. Applying the test
alone is possible because it is appended beside the decoder and declares a
test-local quirk bit when the original driver lacks it.

To compare with an independently supplied generic fix, replace only
uvc_video.c with that reference and append the test include at the end.
Run the back-to-back case only: that generic fix intentionally predates the
trailer controls. Both implementations must reconstruct the same patterned
614400 bytes twice, from 37 full 16384-byte URBs plus 8264 bytes per frame.

Inside the container, from the source tree:

```
python3 tools/testing/kunit/kunit.py run --arch=x86_64 \
  --build_dir=/scratch/kunit --kunitconfig=/recipe/kernel/tests/uvc-bulk/uvc-bulk.kunitconfig \
  --make_options CC=gcc-16 --make_options HOSTCC=gcc-16 --jobs=4 \
  --timeout=180 --qemu_args="-accel tcg -smp 2" 'uvc-bulk-payload*'
```

For the reference select `uvc-bulk-payload.uvc_bulk_back_to_back_test`.
Retain the parsed exit status and the raw `test.log`; a raw-output-only
runner can report process success despite a failing KUnit case. The test
allocates no video device, userspace VB2 queue or physical camera. A held
queue reference keeps buffer completion local to the fixture.
