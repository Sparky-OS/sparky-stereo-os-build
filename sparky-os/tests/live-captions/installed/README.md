# Installed live-caption coordination proof

Run only inside the isolated container recipe. No speech model is acquired or
loaded. Prepare an image with the qualified Partners and live-caption packages,
Kaption and captiond, the stereo desktop, Qt and the Python accessibility/capture
tools. The fixture folder contains a declared full side-by-side `stereo.mkv`;
the known audio is captiond's packaged `fox.wav`.

Set `DOCKER_HOST` to your lane socket, `LC73_RIG_IMAGE` to the verified installed
image, and `LC73_FIXTURES` to that fixture folder. Optional `LC73_CONTAINER_LEDGER`
appends the container ID to the lane's own ledger before removal. Run:

```sh
bash run.sh amd 1 en NEW_OUTPUT
bash run.sh amd 1.25 pt_BR ANOTHER_NEW_OUTPUT
bash run.sh nvidia 1 en ANOTHER_NEW_OUTPUT
bash run.sh nvidia 1.25 pt_BR ANOTHER_NEW_OUTPUT
```

The fixture boundary is recorded in `session/fixture-boundary.json`; never call
the synthetic words recognition. `rows.json` contains the functional expected
and found values and load readings. Analyze the marked desktop/video captures
with `analyze-eyes.py OUTPUT/session SCALE`; the expected caption disparity is
zero, with nonzero rows retained separately for the compositor correction.
The output includes accessible controls, unit results, private capture nodes,
known-sentence events, unchanged-file checks and the mismatch/lag sentences.
The sentence TSV lists all 30 integration keys in English and pt_BR and names
the eight languages still owed to the translations lane.

This is the installed portion of the milestone, not the complete milestone rerun
or the real-model A10 kit. The wrapper assumes the prepared image and fixture;
its prerequisite package installation and source gates must also be retained.

For full-page text geometry, build the test-only viewport observer and set
LC73_PROBE_TOOLS to its directory and LC73_LOCALES to verified locale data.
The observer is preloaded only into the KCM. LC73_VIEWPORT_ONLY=1 limits a run
to the page checks and stereo capture. Discover installed catalogues with
page-languages.py and run each at both scales on both cards. The complete
milestone command includes this matrix and refuses unrecorded locale bytes.
