// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "headsetengine.h"

#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// The panel entry's view of the first connected headset: refreshed without blocking the shell, and the changes made from its menu are
// applied to the headset and kept the same way the System Settings page keeps them.
class HeadsetStatus : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool present READ present NOTIFY changed)
    Q_PROPERTY(QString id READ id NOTIFY changed)
    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(bool hasBattery READ hasBattery NOTIFY changed)
    Q_PROPERTY(bool batteryKnown READ batteryKnown NOTIFY changed)
    Q_PROPERTY(int battery READ battery NOTIFY changed)
    Q_PROPERTY(bool charging READ charging NOTIFY changed)
    Q_PROPERTY(QString batteryText READ batteryText NOTIFY changed)
    Q_PROPERTY(QString iconName READ iconName NOTIFY changed)
    Q_PROPERTY(QStringList presets READ presets NOTIFY changed)
    Q_PROPERTY(QString problem READ problem NOTIFY problemChanged)
    // What the connected headset reports and what the person last chose (properties, so that the menu follows them)
    Q_PROPERTY(bool hasSidetone READ hasSidetone NOTIFY changed)
    Q_PROPERTY(bool hasLights READ hasLights NOTIFY changed)
    Q_PROPERTY(bool hasVoicePrompts READ hasVoicePrompts NOTIFY changed)
    Q_PROPERTY(bool hasEqualizerPreset READ hasEqualizerPreset NOTIFY changed)
    Q_PROPERTY(int sidetone READ sidetone NOTIFY changed)
    Q_PROPERTY(bool lights READ lights NOTIFY changed)
    Q_PROPERTY(bool voicePrompts READ voicePrompts NOTIFY changed)
    Q_PROPERTY(QString equalizerPreset READ equalizerPreset NOTIFY changed)

public:
    explicit HeadsetStatus(QObject *parent = nullptr);
    ~HeadsetStatus() override;

    bool present() const
    {
        return m_present;
    }
    QString id() const
    {
        return m_headset.id;
    }
    QString name() const
    {
        return m_headset.name;
    }
    bool hasBattery() const;
    bool batteryKnown() const
    {
        return m_headset.batteryKnown();
    }
    int battery() const
    {
        return m_headset.battery;
    }
    bool charging() const
    {
        return m_headset.charging();
    }
    QString batteryText() const;
    QString iconName() const;
    QStringList presets() const
    {
        return m_headset.presets;
    }
    QString problem() const
    {
        return m_problem;
    }

    bool hasSidetone() const
    {
        return has(QStringLiteral("Sidetone"));
    }
    bool hasLights() const
    {
        return has(QStringLiteral("Lights"));
    }
    bool hasVoicePrompts() const
    {
        return has(QStringLiteral("VoicePrompts"));
    }
    bool hasEqualizerPreset() const
    {
        return has(QStringLiteral("EqualizerPreset"));
    }
    int sidetone() const
    {
        return m_saved.contains(QStringLiteral("Sidetone")) ? m_saved.value(QStringLiteral("Sidetone")).toInt() : -1; // -1: never chosen here, so no level is marked
    }
    bool lights() const
    {
        return value(QStringLiteral("Lights")).toBool();
    }
    bool voicePrompts() const
    {
        return value(QStringLiteral("VoicePrompts")).toBool();
    }
    QString equalizerPreset() const
    {
        return value(QStringLiteral("EqualizerPreset")).toString();
    }

    // Set it on the headset now; kept only when the headset took it
    Q_INVOKABLE void set(const QString &key, const QVariant &value);
    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void changed();
    void problemChanged();

private:
    void finished();
    // Does the connected headset report this setting (Sidetone, Lights, VoicePrompts, InactiveTime, EqualizerPreset)?
    bool has(const QString &key) const;
    // The saved choice, or the neutral value when nothing was ever chosen here
    QVariant value(const QString &key) const;

    Sparky::Headset::Headset m_headset;
    bool m_present = false;
    QVariantMap m_saved;
    QString m_problem;
    QProcess m_process;
    QTimer m_poll;
};
