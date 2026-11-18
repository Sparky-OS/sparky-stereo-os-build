// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "headsetstore.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

namespace Sparky::Headset
{
static KSharedConfigPtr config()
{
    return KSharedConfig::openConfig(QStringLiteral("sparky-stereo-headsetrc"), KConfig::SimpleConfig);
}

static QString groupName(const QString &id)
{
    return QStringLiteral("Headset ") + id;
}

QVariantMap savedChoices(const QString &id)
{
    QVariantMap out;
    const KConfigGroup g = config()->group(groupName(id));
    for (const SettingDef &d : settingDefs()) {
        const QString key = QString::fromLatin1(d.key);
        if (!g.hasKey(key)) {
            continue;
        }
        switch (d.kind) {
        case SettingDef::Switch:
            out.insert(key, g.readEntry(key, false));
            break;
        case SettingDef::Number:
            out.insert(key, g.readEntry(key, 0));
            break;
        case SettingDef::Choice:
            out.insert(key, g.readEntry(key, QString()));
            break;
        }
    }
    return out;
}

void saveChoice(const QString &id, const QString &key, const QVariant &value)
{
    KConfigGroup g = config()->group(groupName(id));
    g.writeEntry(key, value);
    g.sync();
}

void forgetChoices(const QString &id)
{
    config()->deleteGroup(groupName(id));
    config()->sync();
}

QString batteryText(const Headset &h)
{
    if (!h.has(QStringLiteral("CAP_BATTERY_STATUS"))) {
        return QString();
    }
    if (h.batteryStatus == QLatin1String("BATTERY_UNAVAILABLE") || h.battery < 0) {
        return i18n("The headset is switched off or out of range, so its battery is not known.");
    }
    if (h.charging()) {
        return i18n("Charging, %1%", h.battery);
    }
    return i18n("Battery at %1%", h.battery);
}

static QString label(const QString &key)
{
    if (key == QLatin1String("Sidetone")) {
        return i18n("Sidetone (hear your own voice)");
    }
    if (key == QLatin1String("Lights")) {
        return i18n("Lights");
    }
    if (key == QLatin1String("VoicePrompts")) {
        return i18n("Voice prompts");
    }
    if (key == QLatin1String("InactiveTime")) {
        return i18n("Switch off after (minutes, 0 is never)");
    }
    return i18n("Equalizer preset");
}

QVariantMap describe(const Headset &h, const QVariantMap &saved)
{
    QVariantMap out;
    out[QStringLiteral("id")] = h.id;
    out[QStringLiteral("name")] = h.name;
    out[QStringLiteral("hasBattery")] = h.has(QStringLiteral("CAP_BATTERY_STATUS"));
    out[QStringLiteral("battery")] = h.battery;
    out[QStringLiteral("batteryKnown")] = h.batteryKnown();
    out[QStringLiteral("charging")] = h.charging();
    out[QStringLiteral("batteryText")] = batteryText(h);
    out[QStringLiteral("hasChatmix")] = h.has(QStringLiteral("CAP_CHATMIX_STATUS")) && h.chatmix >= 0;
    out[QStringLiteral("chatmix")] = h.chatmix;
    QVariantList settings;
    for (const SettingDef &d : settingDefs()) {
        if (!h.has(QString::fromLatin1(d.cap))) {
            continue; // a capability the headset does not report is not shown, not even as a dead control
        }
        if (d.kind == SettingDef::Choice && h.presets.isEmpty()) {
            continue;
        }
        const QString key = QString::fromLatin1(d.key);
        QVariantMap s;
        s[QStringLiteral("key")] = key;
        s[QStringLiteral("label")] = label(key);
        s[QStringLiteral("kind")] = d.kind == SettingDef::Switch ? QStringLiteral("switch") : d.kind == SettingDef::Number ? QStringLiteral("number") : QStringLiteral("choice");
        s[QStringLiteral("min")] = d.min;
        s[QStringLiteral("max")] = d.max;
        s[QStringLiteral("choices")] = h.presets;
        s[QStringLiteral("saved")] = saved.contains(key);
        s[QStringLiteral("value")] = saved.value(key, d.kind == SettingDef::Choice ? QVariant(h.presets.value(0)) : QVariant(d.kind == SettingDef::Switch ? false : d.min));
        settings << s;
    }
    out[QStringLiteral("settings")] = settings;
    return out;
}
}
