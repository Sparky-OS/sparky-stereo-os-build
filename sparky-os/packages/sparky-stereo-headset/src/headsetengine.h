// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariant>

// What the page, the panel entry and the user service know about a headset. Everything comes from HeadsetControl (Denis Arnst "Sapd" and
// the contributors) as it prints it with `headsetcontrol -o json`: a capability that the headset does not report is not here.
namespace Sparky::Headset
{
struct Headset {
    QString id; // "03f0:018b", the vendor and product numbers HeadsetControl prints
    QString name; // the headset's name as HeadsetControl knows it
    QStringList caps; // CAP_BATTERY_STATUS, CAP_SIDETONE ...
    QStringList presets; // the equaliser presets in HeadsetControl's own order (the number given to -p is the position)
    int battery = -1; // percent, -1 when the headset does not say
    QString batteryStatus; // BATTERY_AVAILABLE, BATTERY_CHARGING, BATTERY_UNAVAILABLE ...
    int chatmix = -1; // 0 to 128, -1 when the headset does not say

    bool has(const QString &cap) const
    {
        return caps.contains(cap);
    }
    bool charging() const
    {
        return batteryStatus == QLatin1String("BATTERY_CHARGING");
    }
    bool batteryKnown() const
    {
        return battery >= 0 && batteryStatus != QLatin1String("BATTERY_UNAVAILABLE");
    }
};

// One thing a person can set. The key is the name kept in sparky-stereo-headsetrc.
struct SettingDef {
    enum Kind { Switch, Number, Choice };
    const char *key;
    const char *cap; // the capability that must be reported
    Kind kind;
    int min;
    int max;
    const char *option; // HeadsetControl's command line option
};

const QList<SettingDef> &settingDefs();
const SettingDef *settingDef(const QString &key);

// The program, or an empty string when it is not installed
QString programPath();

// Read `headsetcontrol -o json`; false with the text to show when it cannot be read
bool parse(const QByteArray &json, QList<Headset> &out, QString &error);
bool query(QList<Headset> &out, QString &error, int timeoutMs = 10000);

// The arguments for one change; an empty list with the text in `error` when the headset cannot take it
QStringList argumentsFor(const Headset &headset, const QString &key, const QVariant &value, QString &error);

// Set it now on the headset; the returned text is empty on success, else what to tell the person
QString apply(const Headset &headset, const QString &key, const QVariant &value);
}
