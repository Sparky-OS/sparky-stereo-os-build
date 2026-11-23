# Stable parameter metadata for independent effect instances

The installed frei0r-plugins is deb-multimedia 1:3.7.1-dmo1, from frei0r-dmo.
Two Cartoon instances in separate camera-eye pipelines exposed a double free
in f0r_construct. The C++ convenience header clears and rewrites its shared
parameter vector on every instance construction, including metadata swaps used
for failed construction. Other instances can read it at the same time.

Build the parameter metadata only with the plugin registration instance, before
the library is exposed, then leave it immutable. Each instance still owns its
parameter pointers and values. Allocation failures still return a null instance;
they cannot change already registered metadata. The successor version is
1:3.7.1-dmo1+stereo3d1+lc1, rebuilt from the edition's DMO source packaging.
The native probe builds the three C++ effects Kamoso uses: Cartoon, Twolay0r and
Delay. Distort0r is C and remains supplied by the installed package. The eventual
package rebuilds every plugin and the header, with every ordinary package gate.
No package or source closure is yet staged.

A deterministic test pauses an instance after its base constructor and reads
the public plugin metadata while it is paused: expected two parameters, found
zero before, two after. It then checks 2,000 instances on two threads, retaining
independent parameter values. The real 31-effect matrix also runs unchanged.
Upstream issue 188 documents related thread-safety problems; the historical
frame-parallelism commit 455c441a by Dan Dennedy changes per-frame state, not this
metadata lifetime. Current main and header history retain the mutable vector;
no matching repair was found. Nothing was filed or sent.
