// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include <PowerDevilProfileSettings.h>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QTextStream>
#include <Solid/Battery>
#include <Solid/Device>
#include <algorithm>
#include <kscreensaversettings.h>
#include <powerdevilenums.h>
#include <powerdevilsettingsdefaults.h>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTextStream out(stdout);
    const bool laptop = app.arguments().contains(QStringLiteral("--laptop"));
    const bool supply = app.arguments().contains(QStringLiteral("--supply"));
    const bool profiles = app.arguments().contains(QStringLiteral("--profiles"));
    const bool user = app.arguments().contains(QStringLiteral("--user"));
    int failures = 0;
    const auto check = [&](bool pass, const QString &name) {
        out << (pass ? "PASS " : "FAIL ") << name << Qt::endl;
        failures += !pass;
    };
    const auto batteries = Solid::Device::listFromType(Solid::DeviceInterface::Battery);
    check(std::any_of(batteries.begin(), batteries.end(), [](const Solid::Device &device) {
        const auto battery = device.as<Solid::Battery>();
        return battery && battery->isPowerSupply();
    }) == supply,
          QStringLiteral("native Solid power-supply fixture"));
    const QDBusInterface upower(QStringLiteral("org.freedesktop.UPower"),
                                QStringLiteral("/org/freedesktop/UPower"),
                                QStringLiteral("org.freedesktop.UPower"),
                                QDBusConnection::systemBus());
    check(upower.isValid() && upower.property("LidIsPresent").toBool() == laptop, QStringLiteral("native UPower lid presence"));
    check(PowerDevil::ProfileDefaults::defaultAutoSuspendAction(false, true) == 1, QStringLiteral("legacy default-action semantics"));
    check(PowerDevil::ProfileDefaults::defaultAutoSuspendAction(true, true) == 0, QStringLiteral("legacy VM suppression"));
    check(PowerDevil::ProfileDefaults::defaultAutoSuspendAction(false, false) == 0, QStringLiteral("legacy unsupported suspend suppression"));
    for (const bool tablet : {false, true}) {
        for (const auto &profile : {QStringLiteral("AC"), QStringLiteral("Battery"), QStringLiteral("LowBattery")}) {
            PowerDevil::ProfileSettings settings(profile, tablet, false, true);
            settings.load();
            const bool ac = profile == QStringLiteral("AC");
            const bool eco = profile == QStringLiteral("LowBattery");
            const int dim = user && ac ? 901 : eco ? 180
                                                   : 900;
            const int off = user && ac ? 3600 : ac ? 9900
                : eco                              ? 300
                                                   : 1200;
            const int sleep = user && ac ? 7200 : ac ? 14400
                : eco                                ? 600
                                                     : 1800;
            const uint action = ac && !laptop && !user ? 0 : 1;
            const auto prefix = profile + (tablet ? QStringLiteral(" tablet ") : QStringLiteral(" desktop-mode "));
            out << prefix << "dim=" << settings.dimDisplayIdleTimeoutSec() << " off=" << settings.turnOffDisplayIdleTimeoutSec()
                << " action=" << settings.autoSuspendAction() << " sleep=" << settings.autoSuspendIdleTimeoutSec() << Qt::endl;
            check(settings.dimDisplayWhenIdle() && settings.dimDisplayIdleTimeoutSec() == dim, prefix + QStringLiteral("dim"));
            check(settings.turnOffDisplayWhenIdle() && settings.turnOffDisplayIdleTimeoutSec() == off, prefix + QStringLiteral("off"));
            check(settings.lockBeforeTurnOffDisplay(), prefix + QStringLiteral("lock before off"));
            check(settings.autoSuspendAction() == action && settings.autoSuspendIdleTimeoutSec() == sleep, prefix + QStringLiteral("sleep"));
            check(settings.powerButtonAction() == 8, prefix + QStringLiteral("shutdown button"));
            check(settings.lidAction() == uint(ac ? 0 : 1), prefix + QStringLiteral("lid"));
            if (profiles) {
                const auto expected = ac ? QStringLiteral("performance") : eco ? QStringLiteral("power-saver") : QStringLiteral("balanced");
                check(settings.powerProfile() == expected, prefix + QStringLiteral("power profile"));
            }
            if (!ac) {
                check(!settings.inhibitLidActionWhenExternalMonitorPresent(), prefix + QStringLiteral("battery lid with external output"));
            }
            if (ac) {
                check(action == 0 || sleep > off, prefix + QStringLiteral("awake through screen-off"));
            }
        }
    }
    if (!user) {
        PowerDevil::ProfileSettings vm(QStringLiteral("AC"), false, true, true);
        vm.load();
        check(vm.autoSuspendAction() == 0, QStringLiteral("AC VM native sleep suppression"));
        PowerDevil::ProfileSettings unsupported(QStringLiteral("AC"), false, false, false);
        unsupported.load();
        check(unsupported.autoSuspendAction() == 0, QStringLiteral("AC unsupported suspend suppression"));
    }
    KScreenSaverSettings::self()->load();
    check(!KScreenSaverSettings::autolock(), QStringLiteral("no independent idle lock"));
    check(KScreenSaverSettings::lockGrace() == 0, QStringLiteral("zero lock grace"));
    check(KScreenSaverSettings::lockOnResume(), QStringLiteral("lock on suspend"));
    out << "Failures: " << failures << Qt::endl;
    return failures ? 1 : 0;
}
