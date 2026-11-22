# Live-caption bench kit

This kit is for the main session on the A10-9600P, after choosing its test window.
It refuses other CPUs and refuses real recognition inside containers. No model
run is part of the station rerun. Copy this scripts directory and the verified
row-73 stage to the bench. If Vibe is not already installed, also copy row 69's
accepted Vibe stage with its SHA256SUMS and pass `--vibe-stage THAT_DIRECTORY`.
Use a fresh output directory on an SSD with room for the named downloads.

Run as root (the main session supplies its established privilege route):

```sh
python3 a10-kit.py STAGE NEW_OUTPUT --download-models --vibe-stage VIBE_STAGE
```

For a remote run, start that exact command detached with `nohup`, redirect both
streams to a chosen log and retain its PID. The process name is `lc73-a10-kit`;
wait with `pgrep -x lc73-a10-kit`, never `pgrep -f`. Read the process exit and
cleanup.json, not merely the end of the log. SIGTERM requests cleanup.

The kit refuses package upgrades or removal of existing packages. It prints each
package/model HTTPS source, byte count and SHA-256 before fetching it, verifies
both, rechecks the apt plan, and installs without network access. Missing or
ambiguous index digests fail before download. It never runs `apt update`, changes
sources, or substitutes an unsigned archive. Two shared models, Tiny and Base,
are downloaded only because `--download-models` was explicitly supplied.

It creates one temporary account under its output scratch, its own user manager,
virtual KWin and private PipeWire. Physical audio/Bluetooth monitors are disabled
for this account; it plays the packaged fox.wav into its own null sink and links
that monitor to captiond. Existing accounts, devices and their settings are not
changed. The microphone choice stays off. Graphics' own inventory supplies CPU
and both usable AMD card IDs; each is selected through Partners, never a guessed
ggml ordinal. Failure to find both cards is said and fails the run.

For each model/card, three trials use the integration's actual `on` and `off`.
Each requires the whole known fox sentence in a final daemon caption and in
Kaption's AT-SPI announcement. It also requires successful playback drain. Lag is
arrival minus the monotonic playback-drain timestamp, sampled at 100 ms; it is
settled/visible caption lag after the end of this known clip, not per-word lag or
physical loudspeaker latency. Model load is excluded and readiness is bounded.
The 90-second trial bound is retained from the earlier kit; slow is reported,
not silently turned into a faster model. CPU ticks/load and temperatures are
recorded. k10temp's hwmon temp1_input works without thermal_zone directories;
unreadable temperature is explicitly recorded as unavailable. A measured 62 C
stops the run. The main session decides when a cooled bench is ready to retry.

The native captiond model listing must include that exact file. Vibe's own local
server loads the same absolute path, lists its basename through `/v1/models`,
and transcribes the same WAV using the documented multipart `file` field.
Its response must contain all the known words. The model's digest and inode are
checked again. This is Vibe-server's own listing/transcription, not a claim that
the graphical model chooser was clicked. The private Vibe server binds loopback
on an allocated port, is unloaded and stopped after each file, and sends no audio
off the bench.

Finally the kit stops/removes its user manager and account, purges only its apt
additions, checks original package states and restores automatic/manual marks.
It removes its downloaded archives, model files and temporary settings. Logs,
results and manifests remain. A failed cleanup is a failed run, explicitly said.
A hard power loss or SIGKILL cannot execute Python's finally block: the account
name, scratch path and apt Inst plan in the output are the recovery record.
No existing model or settings file is ever moved or overwritten.

The station checks this worker with a protocol stand-in and synthetic 56-byte
files, and a strict local Vibe HTTP stand-in. These results are labelled synthetic
and prove mechanics only. Real shared-file compatibility and lag await this bench
run. The native API shape was checked against Vibe v3.3.5's server/routes sources.
