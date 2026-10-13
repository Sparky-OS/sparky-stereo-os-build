// SPDX-License-Identifier: GPL-2.0-or-later
#include "stereoshowsettings.h"
#include <KConfigWatcher>
#include <QCoreApplication>
#include <QSignalSpy>
#include <cassert>
#include <iostream>
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    auto watcher = KConfigWatcher::create(KSharedConfig::openConfig(QStringLiteral("stereoshowrc")));
    QSignalSpy changes(watcher.data(), &KConfigWatcher::configChanged);
    StereoShowSettings settings;
    assert(settings.enabled() && settings.idleSeconds() == 8100 && settings.cycleSeconds() == 600);
    settings.setEnabled(false);
    settings.setIdleSeconds(7200);
    settings.setCycleSeconds(300);
    assert(settings.save());
    assert(changes.wait(2000));
    StereoShowSettings saved;
    assert(!saved.enabled() && saved.idleSeconds() == 7200 && saved.cycleSeconds() == 300);
    saved.setDefaults();
    assert(saved.enabled() && saved.idleSeconds() == 8100 && saved.cycleSeconds() == 600);
    assert(saved.save());
    std::cout << "PASS: generated KCM settings defaults, persisted overrides and live KConfig notification\n";
}
