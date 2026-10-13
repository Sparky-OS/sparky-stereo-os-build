# Format-only X11 declaration

The available shared helper source still exposes only a combined declaration
that always writes both layout and class properties. Passing zero class values
does not mean leaving class metadata alone.

`stereo-declare-format-only.patch` adds `stereo_declare_x11_format()` to that
MIT library without changing existing API behavior or its SONAME. It accepts
none or full SBS, requires layout support version 1, and writes just the layout
property. The layer calls it once when activating a window. Existing program
class metadata is preserved. The old combined call remains for its existing
clients; the layer no longer calls it or reads GL_STEREO_CLASS.

This is a proposed shared-library change for integration before shipping this
layer. It is not applied to any external checkout or installed on the host.
The non-root test runner copies only helper source files and its XML into this
workspace, applies the patch, builds a private helper and deletes that scratch
at exit. Linking the layer against the unmodified helper fails, deliberately,
instead of silently declaring metadata against the new contract.

Tests assert that the class property stays absent or retains a program-supplied
value, and count exactly one layout event across repeated context binding.
A test-only interposer redirects the new call to the old combined API;
the absence assertion must fail, proving it detects the original problem.
