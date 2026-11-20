# Paired phone orientation runtime successor

`prepare-source.sh INPUT OUTPUT PACKAGING` applies the pinned packaging overlay to the accepted Lean Code source package.
Set `SOURCE_DATE_EPOCH` to the recipe commit date and `SD762_SCRATCH` to disposable build storage.
The carried stress-test patch attaches the reader on the empty page before the producer starts; production reader semantics and every assertion stay unchanged.

The container entry expects the source package under `/work/package-source/displayxr`, its original components under `/work/source-inputs/displayxr`, and the build repository under `/lane/src/sparky-stereo-os-build`.
Run it with `SD762_PHASE=compile` to project and compile using the package's existing hooks and flags.
Then run `stress-proof.py /work/package-build/displayxr/source /work/stress-proof`: it compiles a separate delayed-attachment negative control, requires its accounting failure, and runs the complete patched pose-page test 200 times with four bounded CPU load workers.
The assertion sequence is checked before compiling the negative control.
Run the entry again with `SD762_PHASE=build` for the original `debian/rules` build and complete test invocation, unchanged.

Finally run `SD762_PHASE=package` with the saved build provenance and the normal Lean Code archive configuration, scratch and predecessor package variables.
The package phase uses the unchanged archive qualification and `check-debs` gates.
The proof directory is diagnostic evidence; neither its negative-control source nor its executable enters the package.
