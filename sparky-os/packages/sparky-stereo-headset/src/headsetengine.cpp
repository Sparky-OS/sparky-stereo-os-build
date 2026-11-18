// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "headsetengine.h"

#include <KLocalizedString>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QStandardPaths>

namespace Sparky::Headset
{
const QList<SettingDef> &settingDefs()
{
    static const QList<SettingDef> defs = {
        {"Sidetone", "CAP_SIDETONE", SettingDef::Number, 0, 128, "-s"},
        {"Lights", "CAP_LIGHTS", SettingDef::Switch, 0, 1, "-l"},
        {"VoicePrompts", "CAP_VOICE_PROMPTS", SettingDef::Switch, 0, 1, "-v"},
        {"InactiveTime", "CAP_INACTIVE_TIME", SettingDef::Number, 0, 90, "-i"},
        {"EqualizerPreset", "CAP_EQUALIZER_PRESET", SettingDef::Choice, 0, 0, "-p"},
    };
    return defs;
}

const SettingDef *settingDef(const QString &key)
{
    for (const SettingDef &d : settingDefs()) {
        if (key == QLatin1String(d.key)) {
            return &d;
        }
    }
    return nullptr;
}

QString programPath()
{
    return QStandardPaths::findExecutable(QStringLiteral("headsetcontrol"));
}

// The text of the "devices" array split into the text of each device object, string-aware
static QList<QByteArray> deviceTexts(const QByteArray &json)
{
    QList<QByteArray> out;
    const int start = json.indexOf("\"devices\"");
    if (start < 0) {
        return out;
    }
    int i = json.indexOf('[', start);
    if (i < 0) {
        return out;
    }
    int depth = 0;
    int objStart = -1;
    bool inString = false;
    for (++i; i < json.size(); ++i) {
        const char c = json[i];
        if (inString) {
            if (c == '\\') {
                ++i;
            } else if (c == '"') {
                inString = false;
            }
            continue;
        }
        if (c == '"') {
            inString = true;
        } else if (c == '{') {
            if (depth++ == 0) {
                objStart = i;
            }
        } else if (c == '}') {
            if (--depth == 0 && objStart >= 0) {
                out << json.mid(objStart, i - objStart + 1);
                objStart = -1;
            }
        } else if (c == ']' && depth == 0) {
            break;
        }
    }
    return out;
}

// QJsonObject sorts its keys; the number given to -p is the position in the program's own list, so the names are read in the order printed
static QStringList presetNamesInOrder(const QByteArray &device)
{
    QStringList names;
    const int at = device.indexOf("\"equalizer_presets\"");
    if (at < 0) {
        return names;
    }
    int i = device.indexOf('{', at);
    if (i < 0) {
        return names;
    }
    int depth = 0;
    bool inString = false;
    int keyStart = -1;
    for (; i < device.size(); ++i) {
        const char c = device[i];
        if (inString) {
            if (c == '\\') {
                ++i;
            } else if (c == '"') {
                inString = false;
                if (depth == 1 && keyStart >= 0) {
                    // a key when a colon follows
                    int j = i + 1;
                    while (j < device.size() && (device[j] == ' ' || device[j] == '\n' || device[j] == '\r' || device[j] == '\t')) {
                        ++j;
                    }
                    if (j < device.size() && device[j] == ':') {
                        names << QString::fromUtf8(device.mid(keyStart, i - keyStart));
                    }
                    keyStart = -1;
                }
            }
            continue;
        }
        if (c == '"') {
            inString = true;
            keyStart = i + 1;
        } else if (c == '{' || c == '[') {
            ++depth;
        } else if (c == '}' || c == ']') {
            if (--depth == 0) {
                break;
            }
        }
    }
    return names;
}

bool parse(const QByteArray &json, QList<Headset> &out, QString &error)
{
    out.clear();
    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(json, &parseError);
    if (!doc.isObject()) {
        error = i18n("HeadsetControl answered in a form this page does not read.");
        return false;
    }
    const QJsonArray devices = doc.object().value(QLatin1String("devices")).toArray();
    const QList<QByteArray> texts = deviceTexts(json);
    for (int n = 0; n < devices.size(); ++n) {
        const QJsonObject d = devices[n].toObject();
        const QString status = d.value(QLatin1String("status")).toString();
        if (!status.isEmpty() && status != QLatin1String("success") && status != QLatin1String("partial")) {
            error = d.value(QLatin1String("message")).toString(i18n("HeadsetControl could not talk to the headset."));
            continue;
        }
        Headset h;
        h.name = d.value(QLatin1String("device")).toString(d.value(QLatin1String("product")).toString());
        const auto four = [](const QString &hex) {
            bool ok = false;
            const int v = hex.toInt(&ok, 16);
            return ok ? QStringLiteral("%1").arg(v, 4, 16, QLatin1Char('0')) : QString();
        };
        h.id = four(d.value(QLatin1String("id_vendor")).toString()) + QLatin1Char(':') + four(d.value(QLatin1String("id_product")).toString());
        for (const QJsonValue &c : d.value(QLatin1String("capabilities")).toArray()) {
            h.caps << c.toString();
        }
        const QJsonObject battery = d.value(QLatin1String("battery")).toObject();
        if (!battery.isEmpty()) {
            h.batteryStatus = battery.value(QLatin1String("status")).toString();
            h.battery = battery.value(QLatin1String("level")).toInt(-1);
        }
        if (d.contains(QLatin1String("chatmix"))) {
            h.chatmix = d.value(QLatin1String("chatmix")).toInt(-1);
        }
        if (n < texts.size()) {
            h.presets = presetNamesInOrder(texts[n]);
        }
        out << h;
    }
    if (!out.isEmpty()) {
        error.clear();
    }
    return !out.isEmpty();
}

bool query(QList<Headset> &out, QString &error, int timeoutMs)
{
    out.clear();
    const QString program = programPath();
    if (program.isEmpty()) {
        error = i18n("HeadsetControl is not installed, so no headset can be read.");
        return false;
    }
    QProcess p;
    p.start(program, {QStringLiteral("-o"), QStringLiteral("json")});
    if (!p.waitForFinished(timeoutMs)) {
        p.kill();
        p.waitForFinished(1000);
        error = i18n("HeadsetControl did not answer in time.");
        return false;
    }
    const QByteArray data = p.readAllStandardOutput();
    if (parse(data, out, error)) {
        return true;
    }
    if (error.isEmpty()) {
        error = i18n("No headset that HeadsetControl knows is connected.");
    }
    return false;
}

QStringList argumentsFor(const Headset &headset, const QString &key, const QVariant &value, QString &error)
{
    error.clear();
    const SettingDef *def = settingDef(key);
    if (!def) {
        error = i18n("This page cannot change %1.", key);
        return {};
    }
    if (!headset.has(QString::fromLatin1(def->cap))) {
        error = i18n("%1 does not report this setting, so it cannot be changed.", headset.name);
        return {};
    }
    QString argument;
    switch (def->kind) {
    case SettingDef::Switch:
        argument = value.toBool() ? QStringLiteral("1") : QStringLiteral("0");
        break;
    case SettingDef::Number:
        argument = QString::number(qBound(def->min, value.toInt(), def->max));
        break;
    case SettingDef::Choice: {
        const int index = headset.presets.indexOf(value.toString());
        if (index < 0) {
            error = i18n("%1 has no equalizer preset called %2.", headset.name, value.toString());
            return {};
        }
        argument = QString::number(index);
        break;
    }
    }
    return {QStringLiteral("-d"), headset.id, QString::fromLatin1(def->option), argument};
}

QString apply(const Headset &headset, const QString &key, const QVariant &value)
{
    QString error;
    const QStringList args = argumentsFor(headset, key, value, error);
    if (args.isEmpty()) {
        return error;
    }
    const QString program = programPath();
    if (program.isEmpty()) {
        return i18n("HeadsetControl is not installed, so no headset can be changed.");
    }
    QProcess p;
    p.start(program, args);
    if (!p.waitForFinished(10000)) {
        p.kill();
        p.waitForFinished(1000);
        return i18n("HeadsetControl did not answer in time.");
    }
    if (p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        const QString text = QString::fromUtf8(p.readAllStandardError() + p.readAllStandardOutput()).trimmed().section(QLatin1Char('\n'), 0, 0);
        return text.isEmpty() ? i18n("HeadsetControl refused the change.") : i18n("HeadsetControl refused the change: %1", text);
    }
    return {};
}
}
