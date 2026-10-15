// SPDX-License-Identifier: GPL-3.0-only
// Kubabbar Glass, menu bar and dock: the application menu on a bar at the top, a floating centred dock at the bottom.
// Created by Daniel Ramos and EchoSystems AI studios, 2026.

var menubar = new Panel
menubar.location = "top"
menubar.height = 2 * Math.ceil(gridUnit * 1.6 / 2)
menubar.hiding = "none"
menubar.floating = false
menubar.opacity = "translucent"

var launcher = menubar.addWidget("org.kde.plasma.kickoff")
launcher.currentConfigGroup = ["General"]
launcher.writeConfig("icon", "kubabbar-glass-launcher")
menubar.addWidget("org.kde.plasma.appmenu")
menubar.addWidget("org.kde.plasma.panelspacer")
menubar.addWidget("org.kde.plasma.systemtray")
var clock = menubar.addWidget("org.kde.plasma.digitalclock")
clock.currentConfigGroup = ["Appearance"]
clock.writeConfig("showDate", false)

var dock = new Panel
dock.location = "bottom"
dock.height = 64
dock.alignment = "center"
dock.lengthMode = "fit"
dock.floating = true
dock.opacity = "translucent"
dock.hiding = "none"

var tasks = dock.addWidget("org.kde.plasma.icontasks")
tasks.currentConfigGroup = ["General"]
tasks.writeConfig("launchers", ["applications:org.kde.dolphin.desktop", "applications:org.kde.konsole.desktop", "applications:org.kde.kate.desktop", "applications:systemsettings.desktop"])
dock.addWidget("org.kde.plasma.marginsseparator")
dock.addWidget("org.kde.plasma.trash")

var desktops = desktopsForActivity(currentActivity())
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.kde.image"
}

// Plasma does not apply KWin effect keys from a Look and Feel, so the layout turns Magic Lamp on and Squash off in kwinrc;
// KWin reloads its effects when the file changes. kubabbar-glass-minimize squash goes back.
var plugins = ConfigFile("kwinrc", "Plugins")
plugins.writeEntry("magiclampEnabled", true)
plugins.writeEntry("squashEnabled", false)
