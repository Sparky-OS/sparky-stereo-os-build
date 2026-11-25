// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <KQuickConfigModule>
#include <QJsonObject>
#include <QVariant>

class StorageKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList volumes READ volumes NOTIFY changed)
    Q_PROPERTY(QString volume MEMBER m_volume NOTIFY changed)
    Q_PROPERTY(QVariantList cleaners MEMBER m_cleaners NOTIFY changed)
    Q_PROPERTY(QVariantList items MEMBER m_items NOTIFY changed)
    Q_PROPERTY(QVariantList errors MEMBER m_errors NOTIFY changed)
    Q_PROPERTY(bool previewed MEMBER m_previewed NOTIFY changed)
    Q_PROPERTY(bool busy MEMBER m_busy NOTIFY changed)
    Q_PROPERTY(bool readOnly MEMBER m_readOnly NOTIFY changed)
    Q_PROPERTY(bool administrator MEMBER m_admin NOTIFY changed)
    Q_PROPERTY(QString period MEMBER m_period NOTIFY changed)
    Q_PROPERTY(QString scheduledAction MEMBER m_scheduledAction NOTIFY changed)
    Q_PROPERTY(QVariantList runs MEMBER m_runs NOTIFY changed)
    Q_PROPERTY(int temporaryAge READ temporaryAge NOTIFY changed)
public:
    StorageKcm(QObject *parent, const KPluginMetaData &data, const QVariantList &args);
    QVariantList volumes() const;
    int temporaryAge() const;

    Q_INVOKABLE void chooseVolume(const QString &path);
    Q_INVOKABLE void chooseAdministrator(bool admin);
    Q_INVOKABLE void setOption(const QString &cleaner, const QString &option, bool value);
    Q_INVOKABLE void preview();
    Q_INVOKABLE void clean(const QStringList &approved);
    Q_INVOKABLE void setSchedule(const QString &period, const QString &action);
    Q_INVOKABLE void setTemporaryAge(int days);
    Q_INVOKABLE QString formatSize(qint64 bytes) const;

Q_SIGNALS:
    void changed();

private:
    QStringList selectedOperations() const;
    QVariantMap describeItem(QVariantMap item) const;
    void activate(const QVariantList &args);
    void catalogue();
    void loadSchedule();
    void runBleachBit(const QStringList &args, const QString &field, const QByteArray &input = {});
    QString m_volume = QStringLiteral("/");
    QVariantList m_cleaners;
    QVariantList m_items;
    QVariantList m_errors;
    bool m_previewed = false;
    bool m_busy = false;
    bool m_readOnly = false;
    bool m_admin = false;
    QString m_openPreview;
    bool m_cachesOnly = false;
    QString m_period = QStringLiteral("manual");
    QString m_scheduledAction = QStringLiteral("review");
    QVariantList m_runs;
};
