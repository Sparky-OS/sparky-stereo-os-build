// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KQuickConfigModule>

class MemoryKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(int zramMode READ zramMode WRITE setZramMode NOTIFY zramModeChanged)
    Q_PROPERTY(bool autoZramOn READ autoZramOn NOTIFY statusChanged)
    Q_PROPERTY(QString autoReason READ autoReason NOTIFY statusChanged)
    Q_PROPERTY(bool zramActive READ zramActive NOTIFY statusChanged)
    Q_PROPERTY(bool cushionEnabled READ cushionEnabled WRITE setCushionEnabled NOTIFY cushionEnabledChanged)
    Q_PROPERTY(QString cushionState READ cushionState NOTIFY statusChanged)
    Q_PROPERTY(QString cushionMode READ cushionMode NOTIFY statusChanged)
    Q_PROPERTY(QString cushionArea READ cushionArea NOTIFY statusChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)

public:
    enum ZramMode {
        Automatic = 0,
        On,
        Off,
    };
    Q_ENUM(ZramMode)

    MemoryKcm(QObject *parent, const KPluginMetaData &data);

    int zramMode() const;
    void setZramMode(int mode);
    bool autoZramOn() const;
    QString autoReason() const;
    bool zramActive() const;
    bool cushionEnabled() const;
    void setCushionEnabled(bool enabled);
    QString cushionState() const;
    QString cushionMode() const;
    QString cushionArea() const;
    QString errorText() const;

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void zramModeChanged();
    void cushionEnabledChanged();
    void statusChanged();
    void errorTextChanged();
    void saveFinished(bool success);

private:
    void updateState();

    int m_zramMode = Automatic;
    int m_savedZramMode = Automatic;
    bool m_cushionEnabled = true;
    bool m_savedCushionEnabled = true;
    bool m_autoZramOn = false;
    QString m_autoReason;
    bool m_zramActive = false;
    QString m_cushionState;
    QString m_cushionMode;
    QString m_cushionArea;
    QString m_errorText;
};
