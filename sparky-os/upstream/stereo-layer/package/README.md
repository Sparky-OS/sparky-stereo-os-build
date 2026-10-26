# In-process content inspection for libstereo-av

`build-native.sh SOURCE_PACKAGE_DIR OUTPUT_DIR TOOLKIT_DIR` applies the patch to the 1.12.0 source package, prepares Lean Code, creates one source package, and builds its AV-only Debian profile.
The profile ships libstereo-av1 and libstereo-av-dev from the existing stereo-layer source package.
It runs the native multiview frame-assembly test.
The Qt picture/presentation packages are unchanged and excluded from this profile.
The application-selection service and command-line probe remain gated by BUILD_CONTENT_ENGINE, off by default until that integration is complete.

Use the installed library for consumer tests; a standalone probe compiled with copies of the sources does not prove the installed package.
Bino depends explicitly on 1.12.0-2+lc1 because the content-inspection API is additive within the 1.12.0 upstream version.
Keep the authored source and exact HR companion with the candidate.

Revision 1.12.0-3+lc1 fixes cross-track metadata inheritance in automatic selection.
The API and dependency minimum remain compatible with Bino +7. Gate all four
AV archives against the actual published 1.12.0-1+lc1 set, without an allowance.
The source regression is documented in autotests/content/README.md; retain the
installed -2 negative and installed -3 result beside the package evidence.
