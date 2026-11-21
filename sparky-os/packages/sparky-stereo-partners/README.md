sparky-stereo-partners
The Partners page of System Settings (ORDER 70): for each kind of work (text, speech, image, 3D), who answers, with which model
and on which card; the local engines (Ollama, installed with the runner for this computer's card, and llama.cpp), turned on and
off, Ollama's models downloaded with their size shown first; signing in to Ollama's service; providers with their keys in KDE
Wallet; each program's own choice beside the system default.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see the copyright file. GNU GPL 3 or later.

Where things are
-------------
- The page: kcm_sparkystereo_partners, in a category of its own at the top of System Settings (share/settings-partners.desktop:
  systemsettings 6.7 reads every categories/*.desktop of the data path; a category with an empty parent is a top-level entry).
- The command: sparky-stereo-partners (status, resolve, set-default, program, card, engine on|off [--engine ollama|llamacpp],
  models, download, account, signin, signout, provider, install-plan, install [--engine ...]); the page runs it for every fact
  and every change, so programs and tests read the same answers.
- llama.cpp: Debian's llama-server (llama.cpp-tools) with ggml's Vulkan back end, started by the user service
  sparky-stereo-llama-server.service (installed off) in router mode on 127.0.0.1:8080, offline, on the person's folder
  ~/.local/share/llama.cpp/models, on the Partners card, with --cors-origins localhost (llama-server's own default allows every
  origin). Debian's llama.cpp-services is not installed: its system service starts at installation.
- Ollama's service (ollama.com): signing in is Ollama's own route, through the local engine: POST /api/me answers the account,
  or 401 with ollama.com's connect page for this computer's name and Ollama's public key (~/.ollama/id_ed25519.pub, written by
  Ollama at its first start); the page opens it in the browser and asks again on "Check"; POST /api/signout unlinks the key.
  The page asks when it opens while Ollama is on, and says so.
- The settings: /etc/xdg/sparky-stereo-partnersrc (shipped defaults) under ~/.config/sparky-stereo-partnersrc (the person's,
  written through kwriteconfig6), key by key as KConfig cascades them. The card is the Graphics package's one key,
  [Render] Partners in sparky-stereo-graphicsrc, written by either page. Keys never go into either file: a provider's key is
  kept in KDE Wallet (folder sparky-stereo-partners, entry provider-ID), read and written through kwallet-query.
- The install: /usr/libexec/sparky-stereo-partners/install-engine (root, through pkexec, action
  org.sparkylinux.sparkystereo.partners.install): ollama and the runner the hardware setup names (its "partner" lines), or
  llama.cpp-tools and libggml0-backend-vulkan.

Nothing fails silently
-------------
A step that cannot be done is said, with its cause, on the page and on standard error, and kept by the edition's problems
engine until it works: the engine's address taken by another program (exit 6), the engine that could not start (3), the card
chosen for partners that cannot be used (4, kept by Graphics), a download that failed (3), a key KDE Wallet could not keep (3).
A download waits on a metered connection, and when the connection's state cannot be read, and says so (exit 5); "Download
anyway" is the person's explicit choice.

Tests
-------------
tests/partners-test.sh USER: as root in a container booted with systemd, with the packages installed and no network: the engine
on and off, its address taken, the model list from a stand-in registry (tests/standin-registry.py: a few kilobytes, not a
model), a download held on a metered connection (tests/fake-networkmanager.py, from sparky-stereo-apt), the registry gone, a
provider and a program's own choice (KMail's answering Kontact), the card that cannot be used; llama.cpp's service off after
installation, on and off, loopback only, its CORS answer to another origin, and the text default on it; signing in to a stand-in
of ollama.com over TLS (tests/standin-ollama-com.py, its own certificate authority) through the real engine: not signed in with
the connect page for this computer's key, the browser asked, signed in, signed out, the engine off, the service unreachable.
