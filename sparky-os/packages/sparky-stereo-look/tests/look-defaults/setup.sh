#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
xdg-user-dirs-update
# Keep the desktop folder present before KIO starts, as on an installed account.
mkdir -p "$(xdg-user-dir DESKTOP)"
if [ "${EXPECT_USER:-0}" = 1 ]; then
 mkdir -p "$HOME/.config/KDE"
 printf '[General]\ncheckerEnabledByDefault=false\ncheckUppercase=true\ndefaultLanguage=fr_FR\n' > "$HOME/.config/KDE/Sonnet.conf"
 printf '[Jobs]\nPermanentPopups=true\n' > "$HOME/.config/plasmanotifyrc"
fi
