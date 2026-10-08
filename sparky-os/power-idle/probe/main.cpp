// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later

#include <PowerDevilProfileSettings.h>
#include <kscreensaversettings.h>
#include <powerdevilenums.h>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDBusVariant>
#include <QTextStream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const bool candidate = app.arguments().contains(QStringLiteral("--candidate"));
    const bool requireTimeline = app.arguments().contains(QStringLiteral("--require-timeline"));
    const bool userOverride = app.arguments().contains(QStringLiteral("--user-override"));
    const bool legacy = app.arguments().contains(QStringLiteral("--legacy"));
    QTextStream out(stdout);
    const int applyIndex = app.arguments().indexOf(QStringLiteral("--apply-profile"));
    if (applyIndex >= 0) {
        if (applyIndex + 1 >= app.arguments().size()) {
            return 2;
        }
        const QString profile = app.arguments().at(applyIndex + 1);
        if (profile != QStringLiteral("AC") && profile != QStringLiteral("Battery") && profile != QStringLiteral("LowBattery")) {
            return 2;
        }
        PowerDevil::ProfileSettings settings(profile, false, false, true);
        settings.load();
        if (settings.powerProfile().isEmpty()) {
            out << "FAIL missing configured power profile" << Qt::endl;
            return 1;
        }
        QDBusInterface properties(QStringLiteral("org.freedesktop.UPower.PowerProfiles"),
                                  QStringLiteral("/org/freedesktop/UPower/PowerProfiles"),
                                  QStringLiteral("org.freedesktop.DBus.Properties"), QDBusConnection::systemBus());
        const QDBusReply<void> reply = properties.call(QStringLiteral("Set"),
                                                      QStringLiteral("org.freedesktop.UPower.PowerProfiles"),
                                                      QStringLiteral("ActiveProfile"),
                                                      QVariant::fromValue(QDBusVariant(settings.powerProfile())));
        if (!reply.isValid()) {
            out << "FAIL " << reply.error().message() << Qt::endl;
            return 1;
        }
        out << profile << " -> " << settings.powerProfile() << Qt::endl;
        return 0;
    }
    int failures = 0;
    const auto check = [&](bool condition, const QString &name) {
        out << (condition ? "PASS " : "FAIL ") << name << Qt::endl;
        failures += !condition;
    };

    for (const QString &profile : {QStringLiteral("AC"), QStringLiteral("Battery"), QStringLiteral("LowBattery")}) {
        PowerDevil::ProfileSettings settings(profile, false, false, true);
        settings.load();
        const bool ac = profile == QStringLiteral("AC");
        const bool battery = profile == QStringLiteral("Battery");
        const int dim = userOverride && ac ? 901 : candidate ? (profile == QStringLiteral("LowBattery") ? 180 : 900) : (ac ? 300 : battery ? 120 : 60);
        const int off = candidate ? (ac ? 9900 : battery ? 1200 : 300) : (ac ? 600 : battery ? 300 : 120);
        const int sleep = candidate ? (ac ? 14400 : battery ? 1800 : 600) : (ac ? 900 : battery ? 600 : 300);
        const auto action = PowerDevil::PowerButtonAction::Sleep;
        out << profile << " dim=" << settings.dimDisplayIdleTimeoutSec()
            << " off=" << settings.turnOffDisplayIdleTimeoutSec()
            << " sleep=" << settings.autoSuspendIdleTimeoutSec()
            << " suspendAction=" << settings.autoSuspendAction()
            << " powerButton=" << settings.powerButtonAction()
            << " lid=" << settings.lidAction()
            << " lockBeforeOff=" << settings.lockBeforeTurnOffDisplay() << Qt::endl;
        check(settings.dimDisplayWhenIdle() && settings.dimDisplayIdleTimeoutSec() == dim, profile + QStringLiteral(" dim"));
        check(settings.turnOffDisplayWhenIdle() && settings.turnOffDisplayIdleTimeoutSec() == off, profile + QStringLiteral(" off"));
        check(settings.autoSuspendIdleTimeoutSec() == sleep && settings.autoSuspendAction() == qToUnderlying(action), profile + QStringLiteral(" sleep"));
        check(settings.lockBeforeTurnOffDisplay() == candidate, profile + QStringLiteral(" lock setting"));
        check(settings.powerButtonAction() == qToUnderlying(candidate && !(userOverride && ac) ? PowerDevil::PowerButtonAction::Shutdown : PowerDevil::PowerButtonAction::PromptLogoutDialog),
              profile + QStringLiteral(" power button"));
        check(settings.lidAction() == qToUnderlying(candidate && ac ? PowerDevil::PowerButtonAction::NoAction : PowerDevil::PowerButtonAction::Sleep),
              profile + QStringLiteral(" lid"));
        if (candidate && !ac) {
            check(!settings.inhibitLidActionWhenExternalMonitorPresent(), profile + QStringLiteral(" battery lid with external display"));
        }
        if (requireTimeline && ac) {
            check(settings.autoSuspendAction() == qToUnderlying(PowerDevil::PowerButtonAction::NoAction), QStringLiteral("AC desktop never auto-suspends"));
        }
    }

    PowerDevil::ProfileSettings vm(QStringLiteral("AC"), false, true, true);
    vm.load();
    if (!legacy) {
        check(vm.autoSuspendAction() == qToUnderlying(PowerDevil::PowerButtonAction::NoAction), QStringLiteral("unoverridden AC VM auto-suspend suppressed"));
    }
    KScreenSaverSettings::self()->load();
    check(KScreenSaverSettings::autolock() == !(candidate || legacy), QStringLiteral("screen locker idle auto-lock setting"));
    check(KScreenSaverSettings::lockGrace() == (candidate || legacy ? 0 : 5), QStringLiteral("screen locker grace setting"));
    check(KScreenSaverSettings::lockOnResume(), QStringLiteral("screen locker suspend setting"));
    out << "Failures: " << failures << Qt::endl;
    return failures == 0 ? 0 : 1;
}
