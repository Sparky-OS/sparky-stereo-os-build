# Vibe integration

Presets are templates in /usr/share/sparky-stereo/vibe/presets.
The shared integration runner invokes seed only after vibe-server is present.
The only live speech-model and transcription settings are Vibe's XDG_DATA_HOME/github.com.thewh1teagle.vibe/app_config.json.
The path was established by launching the actual signed binary with isolated XDG config/data roots and comparing readback and theme; the config-home seed was ignored.
GPU policy is the Graphics page's per-app policy; model.gpuDevice is its Vibe device-number mapping at seed time, null for an uncertain match.
AI tasks stay disabled. This pack introduces no provider store: the Partners page integration will own connection choices and its adapter to Vibe's existing ai.connection object.
No Partners page or connection synchronization is supplied here.
The Dolphin action reads the native store, calls the local speech engine and exclusively publishes a sibling SRT.
It never downloads a model or modifies media, and it refuses to replace an existing caption file.
The shared runner owns the missing-program offer through command-not-found and the integration catalogue.
English and Brazilian Portuguese are authored here; the other eight menu labels use English pending translation.

The unmodified Vibe startup can attempt a model download automatically; the seed does not change that upstream behavior.
