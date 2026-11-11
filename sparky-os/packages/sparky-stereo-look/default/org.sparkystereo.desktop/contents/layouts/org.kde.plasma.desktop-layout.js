// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
// Used for a fresh layout, never as a login-time rewrite of an existing panel.
if (panels().length === 0) {
    loadTemplate("org.kde.plasma.desktop.defaultPanel");
    var created = panels();
    for (var i = 0; i < created.length; ++i) {
        var widgets = created[i].widgets();
        for (var j = 0; j < widgets.length; ++j) {
            if (widgets[j].type === "org.kde.plasma.icontasks" || widgets[j].type === "org.kde.plasma.taskmanager") {
                widgets[j].currentConfigGroup = ["General"];
                widgets[j].writeConfig("launchers", ["applications:sparky-aptus-stereo-appcenter.desktop", "applications:org.kde.dolphin.desktop", "applications:firefox.desktop", "applications:steam.desktop", "applications:vlc-stereo.desktop", "applications:libreoffice-writer.desktop", "applications:libreoffice-calc.desktop", "applications:org.kde.kcalc.desktop", "applications:org.kde.konsole.desktop"]);
            }
        }
    }
}
