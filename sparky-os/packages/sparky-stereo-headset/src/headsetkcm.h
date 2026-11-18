// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "headsetengine.h"

#include <KQuickConfigModule>

#include <QTimer>
#include <QVariantList>

class HeadsetKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList headsets READ headsets NOTIFY headsetsChanged)
    Q_PROPERTY(QString message READ message NOTIFY headsetsChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY problemChanged)

public:
    HeadsetKcm(QObject *parent, const KPluginMetaData &data);

    QVariantList headsets() const
    {
        return m_described;
    }
    // Why no headset is shown (none connected, the program missing, a refusal); empty when one is listed
    QString message() const
    {
        return m_message;
    }
    // What a change was refused with; empty when the last Apply went through
    QString problem() const
    {
        return m_problem;
    }

    // The person moved a control: the value waits for Apply
    Q_INVOKABLE void stage(const QString &id, const QString &key, const QVariant &value);
    Q_INVOKABLE void refresh();

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void headsetsChanged();
    void problemChanged();

private:
    void describeAll();

    QList<Sparky::Headset::Headset> m_headsets;
    QVariantList m_described;
    QString m_message;
    QString m_problem;
    bool m_everDescribed = false;
    QMap<QString, QVariantMap> m_staged; // headset id -> key -> value, written and applied by Apply
    QTimer m_poll;
};
