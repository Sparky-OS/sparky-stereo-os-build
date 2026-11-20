# Paired phone orientation runtime successor

`prepare-source.sh INPUT OUTPUT PACKAGING` applies the pinned packaging overlay to the accepted Lean Code source package.
Set `SOURCE_DATE_EPOCH` to the recipe commit date and `SD762_SCRATCH` to disposable build storage.
The carried stress-test patch attaches the reader on the empty page before the producer starts; production reader semantics and every assertion stay unchanged.

The container entry expects the source package under `/work/package-source/displayxr-socket`, its original components under `/work/source-inputs/displayxr`, and the build repository under `/lane/src/sparky-stereo-os-build`.
Run it with `SD762_PHASE=compile` to project and compile using the package's existing hooks and flags.
Then run `stress-proof.py /work/package-build/displayxr-socket/source /work/stress-proof`: it compiles a separate delayed-attachment negative control, requires its accounting failure, and runs the complete patched pose-page test 200 times with four bounded CPU load workers.
The assertion sequence is checked before compiling the negative control.
Run the entry again with `SD762_PHASE=build` for the original `debian/rules` build and complete test invocation, unchanged.

Finally run `SD762_PHASE=package` with the saved build provenance and the normal Lean Code archive configuration, scratch and predecessor package variables.
The package phase uses the unchanged archive qualification and `check-debs` gates.
The proof directory is diagnostic evidence; neither its negative-control source nor its executable enters the package.

The +6 successor starts from the held +5 source and adds the local paired-headset socket patch.
A refused same-user socket is recovered after type, owner and inode checks; a live owner, foreign owner or regular file is refused explicitly.
The provider serializes its bind/listen window and removes only its own socket at clean destruction.
The ordinary provider tests cover recovery, continued first-owner pose, refusal diagnostics and clean removal.
No runtime package may be installed in the build/test image: installed plugins can change what an in-tree test discovers.
After an archive-gate failure, discard the disposable binary staging directories before packaging again; never project an already marked payload a second time.
