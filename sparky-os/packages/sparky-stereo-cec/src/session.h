// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <QDBusConnection>
#include <QObject>

class SessionGate : public QObject
{
    Q_OBJECT

public:
    explicit SessionGate(const QDBusConnection &bus, QObject *parent = nullptr);
    bool isActive() const;

Q_SIGNALS:
    void activeChanged(bool active);

private Q_SLOTS:
    void propertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void resolve();
    void readActive();
    void setActive(bool active);
    QDBusConnection m_bus;
    QString m_path;
    uint m_revision = 0;
    bool m_active = false;
};
