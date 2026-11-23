Live captions through Partners
=============================

The optional package adds a live-caption switch, shared speech-model choice,
microphone choice and login choice to System Settings, Partners. Kaption draws
the captions; captiond recognizes speech; Vibe keeps its file editor and exports.
No recognizer, capture loop or renderer is implemented here.

The switch starts one user service containing both programs. Stopping it stops
both. Login start is separately enabled and installation enables neither.
The shared Graphics policy selects the card. The adapter compares captiond's
reported accelerator with its device listing and stops on a mismatch. Its
behind flag comes from measured processing time and dropped audio, rather than
the command-line latency estimate.

New models live in the user's captiond/models data directory. An existing
verified Tiny or Base file may stay in its original folder. The Partners speech
model key holds the absolute path. Selecting it sets Vibe's native model.path
and models_folder only while Vibe is closed, for a new store, an exact edition
preset, or this adapter's unchanged store. An unknown or changed store is
refused. No original media, existing model, or unrelated setting is replaced.
An application's own later edits are a reason to stop and review the store.

The model catalogue pins byte counts and SHA-256 digests from the upstream
Whisper model records. A requested download states these before fetching,
waits on metered or unknown connections, and publishes a verified file
exclusively. No model is included in the package. The file-open dialog can
reuse an existing file without downloading or moving it.

The ten locale catalogues in lang/*.json supply the adapter and the Partners
page. The matching extensionless files feed the edition's Problems catalog.

The native programs remain unchanged. This package contains no depth rule;
subtitle placement is the compositor's responsibility.
