// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KQuickConfigModule>
#include <QVariantList>

class MemoryKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(bool cushionEnabled READ cushionEnabled WRITE setCushionEnabled NOTIFY cushionEnabledChanged)
    Q_PROPERTY(QString cushionState READ cushionState NOTIFY statusChanged)
    Q_PROPERTY(QString cushionMode READ cushionMode NOTIFY statusChanged)
    Q_PROPERTY(QString cushionArea READ cushionArea NOTIFY statusChanged)
    Q_PROPERTY(int cushionStatus READ cushionStatus NOTIFY statusChanged)
    Q_PROPERTY(QString cushionProtection READ cushionProtection NOTIFY statusChanged)
    Q_PROPERTY(QString cushionReason READ cushionReason NOTIFY statusChanged)
    Q_PROPERTY(QString cushionStatusError READ cushionStatusError NOTIFY statusChanged)
    Q_PROPERTY(QStringList cushionProblemKeys READ cushionProblemKeys NOTIFY statusChanged)
    Q_PROPERTY(QVariantList cushionProblems READ cushionProblems NOTIFY statusChanged)
    Q_PROPERTY(QString cushionProblemsError READ cushionProblemsError NOTIFY statusChanged)
    Q_PROPERTY(QVariantMap zram READ zram NOTIFY zramChanged)
    Q_PROPERTY(bool zramBusy READ zramBusy NOTIFY zramChanged)
    Q_PROPERTY(bool repairing READ repairing NOTIFY repairingChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)

public:
    MemoryKcm(QObject *parent, const KPluginMetaData &data);

    bool cushionEnabled() const;
    void setCushionEnabled(bool enabled);
    QString cushionState() const;
    QString cushionMode() const;
    QString cushionArea() const;
    QString errorText() const;

    // Same five outcomes as cushion-swap --status.
    enum CushionStatus { Protected, ProtectedWithProblem, NotProtected, NotRunning, Unreadable };
    Q_ENUM(CushionStatus)
    int cushionStatus() const { return m_cushionStatus; }
    QString cushionProtection() const { return m_cushionProtection; }
    QString cushionReason() const;
    QString cushionStatusError() const { return m_cushionStatusError; }
    QStringList cushionProblemKeys() const { return m_cushionProblemKeys; }
    QVariantList cushionProblems() const { return m_cushionProblems; }
    QString cushionProblemsError() const { return m_cushionProblemsError; }
    bool repairing() const { return m_repairing; }
    Q_INVOKABLE void refreshStatus();
    Q_INVOKABLE void repairProblem(int index);

    QVariantMap zram() const { return m_zram; }
    bool zramBusy() const { return m_zramBusy; }
    Q_INVOKABLE void refreshZram();
    Q_INVOKABLE void changeZram();

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void zramChanged();
    void cushionEnabledChanged();
    void statusChanged();
    void errorTextChanged();
    void saveFinished(bool success);
    void repairingChanged();

private:
    void updateState();
    void readCushionStatus();
    void readProblems();

    QVariantMap m_zram;
    bool m_zramBusy = false;
    bool m_zramReading = false;
    bool m_zramKnown = false;
    bool m_cushionEnabled = true;
    bool m_savedCushionEnabled = true;
    QString m_cushionState;
    QString m_cushionMode;
    QString m_cushionArea;
    int m_cushionStatus = Unreadable;
    QString m_cushionProtection;
    QString m_cushionReason;
    QString m_cushionStatusError;
    QStringList m_cushionProblemKeys;
    QVariantList m_cushionProblems;
    QString m_cushionProblemsError;
    bool m_repairing = false;
    QString m_errorText;
};
