# Disposable PJeOffice observations

Run only inside disposable containers, with core dumps disabled and a private Xvfb or Plasma login.
Never connect a real court, reader, identity or document.
Signing fixtures use `--network none`; `/scratch` is a disposable writable bind mount.
The application archive, keys, PINs, keystores, callbacks, generated files and compiled classes stay there and are deleted after verification.
The official application jar is neither changed nor distributed with these tools.

`startup.py`, `TrayProbe.java`, `TrustProbe.java`, `ProviderProbe.java` and `UpdaterPermission.java` measure their named boundaries.
Component success does not establish full task compatibility.
Compile Java helpers with `javac --release 8 -cp OFFICIAL_JAR -d /scratch FILE.java`.
MediaProbe also needs the bundled `jre/lib/ext/jfxrt.jar` at compile time.

For actual task fixtures:

1. Run `token-fixture.sh /scratch/identity` as the test user.
   It creates a two-day test root and leaf, a PKCS#12 file and a SoftHSM token.
   Its all-zero synthetic PF otherName makes the unchanged application's certificate filter recognize the test certificate.
   This does not create a legally valid ICP-Brasil identity.
2. Give each application case a fresh HOME.
   Its `.pjeoffice-pro/pjeoffice-pro.config` takes `list.a1=/scratch/identity/test.p12` for the file case, or `list.a3=/usr/lib/softhsm/libsofthsm2.so` for SoftHSM.
   Export SOFTHSM2_CONF pointing to the fixture configuration.
   For p11-kit, register the SoftHSM module in that test user's `.config/pkcs11/modules/` and set list.a3 to the installed p11-kit-proxy.so.
3. For a localhost login challenge, `LocalTestMain` invokes the application's existing developer entry point and developer-mode setting.
   This test-only launcher belongs in the isolated container, never in a product launcher.
   `backend.py` captures synthetic callbacks on loopback port 18818.
   Run `request.py login`, authorize TESTONLY in the application and enter the generated PIN from the fixture, only at its PIN dialog.
   `verify-login.py CALLBACK_INDEX EXPECTED_CERTIFICATE_COUNT` decodes the PkiPath chain, verifies it against the generated root, verifies the raw SHA256withRSA signature and refuses an altered challenge.
   The file case returns two certificates; the SoftHSM fixture imports only the leaf and returns one.
4. `CreatePdf /scratch/identity/document.pdf` creates a synthetic one-page PDF.
   Invoke the application's official local action in the same user HOME:
   `java -cp OFFICIAL_JAR br.jus.cnj.pje.office.shell.ShellExtension cnj.assinador /scratch/identity/document.pdf samefolder DEFINIDO CADES ATTACHED SHA256withRSA`.
   The application signs through its normal watched local task directory.
   A remote HTTP request with a local file task is refused.
5. Verify the `.pdf.p7s` output outside the application with `openssl cms -verify -inform DER -CAfile /scratch/identity/root.pem -purpose any`, compare extracted bytes with the input PDF, and inspect `openssl cms -cmsout -print` for contentType, signingTime, messageDigest and CMSAlgorithmProtection.
   This is an attached CAdES sidecar, not an embedded PAdES signature.

Use `LANG=C.UTF-8 LC_ALL=C.UTF-8` for the application and helpers.
The builtin module list and output filenames contain non-ASCII characters.

`MediaProbe` exposes JavaFX errors hidden by the cutter's generic MP4 error dialog.
`VideoProbe INPUT OUTPUT_DIRECTORY` exercises the unchanged jar's video-slice handler for 1–4 seconds, independently of that UI.
For system FFmpeg, the application requires a directory containing `ffmpeg.exe`; a test symlink to `/usr/bin/ffmpeg` exercises that boundary.
The `.mp4` extension includes its leading dot.

`SanShape CERTIFICATE` prints the SAN entry sizes returned by the selected Java.
`AppTrustProbe` inspects the application's own resource, and an optional HTTPS URL exercises its actual HTTPS codec.
Its `merge CERTIFICATE` test mode writes `/scratch/union/pjeoffice.jks`, adding a synthetic test root to all original trust entries.
Placing that resource directory first on the test classpath exercises an additive resource bridge without altering the jar.
`CompareStores ORIGINAL_JKS UNION_JKS` requires every original certificate encoding to survive unchanged.
These helpers do not grant new trust on the host or implement an installer.
