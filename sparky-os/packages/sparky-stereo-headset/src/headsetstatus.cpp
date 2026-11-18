// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "headsetstatus.h"

#include "headsetstore.h"

#include <KLocalizedString>
#include <KNotification>

using namespace Sparky::Headset;

HeadsetStatus::HeadsetStatus(QObject *parent)
    : QObject(parent)
{
    connect(&m_process, &QProcess::finished, this, &HeadsetStatus::finished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            m_present = false;
            m_headset = {};
            Q_EMIT changed();
        }
    });
    // Without a headset the entry stays hidden and costs one short question every half minute
    m_poll.setInterval(30000);
    connect(&m_poll, &QTimer::timeout, this, &HeadsetStatus::refresh);
    m_poll.start();
    refresh();
}

void HeadsetStatus::refresh()
{
    if (m_process.state() != QProcess::NotRunning) {
        return;
    }
    const QString program = programPath();
    if (program.isEmpty()) {
        if (m_present) {
            m_present = false;
            m_headset = {};
            Q_EMIT changed();
        }
        return;
    }
    m_process.start(program, {QStringLiteral("-o"), QStringLiteral("json")});
}

void HeadsetStatus::finished()
{
    QList<Headset> list;
    QString error;
    const bool ok = parse(m_process.readAllStandardOutput(), list, error);
    m_present = ok;
    m_headset = ok ? list.first() : Headset();
    m_saved = ok ? savedChoices(m_headset.id) : QVariantMap();
    Q_EMIT changed();
}

HeadsetStatus::~HeadsetStatus()
{
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
}

bool HeadsetStatus::hasBattery() const
{
    return m_present && m_headset.has(QStringLiteral("CAP_BATTERY_STATUS"));
}

QString HeadsetStatus::batteryText() const
{
    return m_present ? Sparky::Headset::batteryText(m_headset) : QString();
}

QString HeadsetStatus::iconName() const
{
    return QStringLiteral("audio-headset");
}

bool HeadsetStatus::has(const QString &key) const
{
    const SettingDef *def = settingDef(key);
    if (!m_present || !def || !m_headset.has(QString::fromLatin1(def->cap))) {
        return false;
    }
    return def->kind != SettingDef::Choice || !m_headset.presets.isEmpty();
}

QVariant HeadsetStatus::value(const QString &key) const
{
    const SettingDef *def = settingDef(key);
    if (!def) {
        return {};
    }
    if (m_saved.contains(key)) {
        return m_saved.value(key);
    }
    switch (def->kind) {
    case SettingDef::Switch:
        return false;
    case SettingDef::Number:
        return def->min;
    case SettingDef::Choice:
        return QString();
    }
    return {};
}

void HeadsetStatus::set(const QString &key, const QVariant &value)
{
    const QString error = apply(m_headset, key, value);
    if (error.isEmpty()) {
        saveChoice(m_headset.id, key, value);
        m_saved.insert(key, value);
        m_problem.clear();
    } else {
        m_problem = error;
        KNotification::event(QStringLiteral("applyFailed"), i18n("The headset kept its setting"), error, QStringLiteral("audio-headset"), KNotification::CloseOnTimeout,
                             QStringLiteral("sparkystereoheadset"));
    }
    Q_EMIT problemChanged();
    Q_EMIT changed();
}
