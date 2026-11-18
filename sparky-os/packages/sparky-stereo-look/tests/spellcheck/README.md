# Inspect the installed Spell Check page before changing defaults

Build sonnet-state with CMake, make, a C++ compiler and the installed Qt Widgets and KF6Sonnet development packages in a container.
The UI probe additionally needs libkf6kcmutils-bin, which supplies kcmshell6; kde-cli-tools alone does not supply it.
The helper prints the real Sonnet Settings and Speller state, including the dictionary selected by the ConfigView used by Plasma's KCM.
It does not save settings.

Mount the executable folder at /test-bin and this folder at /spelling-probe in the login-splash rig.
Use DESKTOP_PROBE=/spelling-probe/probe.sh and LOGIN_LANG=pt_BR.UTF-8, de_DE.UTF-8 or ja_JP.UTF-8 in separate fresh logins.
Generate those locales in the image first.
The probe opens the installed kcmspellchecking page through kcmshell6 and captures it with ScreenShot2.
The session's CASE directory receives sonnet-state.json, the KCM log, screenshot and capture metadata.

Include the image's existing language dictionaries and sonnet6-plugins in the baseline.
A minimal image installed with --no-install-recommends alone can omit Sonnet's recommended plugin and must not be presented as the full edition's installed-language result.
Compare systemLocale, defaultLanguage, pageSelectedLanguage, spellerLanguage, clients and dictionaries separately.
A locale string in a settings file does not establish that a corresponding spelling dictionary exists or is selected.
The helper is an inventory, not a claim that each dictionary's linguistic quality has been tested.

Run check-inventory.py on sonnet-state.json to check coverage of the ten required entries and the current page selection.
A missing dictionary or mismatched selection exits 1; this failure is retained while the requirement remains unmet.
