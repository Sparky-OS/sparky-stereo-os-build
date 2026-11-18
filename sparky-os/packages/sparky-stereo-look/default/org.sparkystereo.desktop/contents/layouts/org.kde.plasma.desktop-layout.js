// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
// Used for a fresh layout, never as a login-time rewrite of an existing panel.
// The panel is KDE's default one (plasma-desktop, layout-templates/org.kde.plasma.desktop.defaultPanel, by the KDE
// community, GPL-2.0-or-later), written out here because one widget differs: the launcher is the Application Menu
// (org.kde.plasma.kicker, the cascading one), not Kickoff (Daniel, 2026-11-17, ORDER 668). When KDE's template
// changes, this follows it.
if (panels().length === 0) {
    var panel = new Panel;
    var panelScreen = panel.screen;
    panel.height = 2 * Math.ceil(gridUnit * 2.5 / 2);
    const maximumAspectRatio = 21 / 9;
    if (panel.formFactor === "horizontal") {
        const geo = screenGeometry(panelScreen);
        const maximumWidth = Math.ceil(geo.height * maximumAspectRatio);
        if (geo.width > maximumWidth) {
            panel.alignment = "center";
            panel.minimumLength = maximumWidth;
            panel.maximumLength = maximumWidth;
        }
    }
    panel.addWidget("org.kde.plasma.kicker");
    panel.addWidget("org.kde.plasma.pager");
    var tasks = panel.addWidget("org.kde.plasma.icontasks");
    tasks.currentConfigGroup = ["General"];
    tasks.writeConfig("launchers", ["applications:sparky-aptus-stereo-appcenter.desktop", "applications:org.kde.dolphin.desktop", "applications:firefox.desktop", "applications:steam.desktop", "applications:vlc-stereo.desktop", "applications:libreoffice-writer.desktop", "applications:libreoffice-calc.desktop", "applications:org.kde.kcalc.desktop", "applications:org.kde.konsole.desktop"]);
    panel.addWidget("org.kde.plasma.marginsseparator");
    var langIds = ["as", "bn", "bo", "brx", "doi", "gu", "hi", "ja", "kn", "ko", "kok", "ks", "lep", "mai", "ml", "mni", "mr",
                   "ne", "or", "pa", "sa", "sat", "sd", "si", "ta", "te", "th", "ur", "vi", "zh_CN", "zh_TW"];
    if (langIds.indexOf(languageId) != -1) {
        panel.addWidget("org.kde.plasma.kimpanel");
    }
    panel.addWidget("org.kde.plasma.systemtray");
    panel.addWidget("org.kde.plasma.digitalclock");
    panel.addWidget("org.kde.plasma.showdesktop");
}

// The desktop's Folder View arrangement is 1, the value Daniel's own machines carry (ORDER 704; Daniel, 2026-11-18: "arrange desktop icons
// in line, not in collums"). System Settings lists value 1 as "In Rows" and the key's own label in main.xml calls it Columns; measured on this
// Plasma (6.7.4) in a fresh login: with 1 the icons stack from the top down the first column and continue below, with the default 0 they
// lay left to right along the first line. A fresh layout only: an account that already has a desktop keeps its own arrangement.
var desktopContainments = desktopsForActivity(currentActivity());
for (var i = 0; i < desktopContainments.length; i++) {
    desktopContainments[i].currentConfigGroup = ["General"];
    desktopContainments[i].writeConfig("arrangement", 1);
}
