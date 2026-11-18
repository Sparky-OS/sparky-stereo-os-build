// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "headsetkcm.h"

#include "headsetstore.h"

#include <KLocalizedString>
#include <KPluginFactory>

using namespace Sparky::Headset;

K_PLUGIN_CLASS_WITH_JSON(HeadsetKcm, "kcm_sparkystereo_headset.json")

HeadsetKcm::HeadsetKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    setButtons(Apply | Default);
    // A headset switched on, plugged in or out while the page is open shows up without reopening it; the battery follows
    m_poll.setInterval(15000);
    connect(&m_poll, &QTimer::timeout, this, &HeadsetKcm::refresh);
    m_poll.start();
    refresh();
}

void HeadsetKcm::refresh()
{
    QString error;
    m_headsets.clear();
    if (query(m_headsets, error)) {
        m_message.clear();
    } else {
        m_message = error;
    }
    describeAll();
}

void HeadsetKcm::describeAll()
{
    const QVariantList before = m_described;
    m_described.clear();
    for (const Headset &h : std::as_const(m_headsets)) {
        QVariantMap saved = savedChoices(h.id);
        const QVariantMap staged = m_staged.value(h.id);
        for (auto it = staged.cbegin(); it != staged.cend(); ++it) {
            saved.insert(it.key(), it.value());
        }
        QVariantMap d = describe(h, saved);
        // a staged value is shown as the person set it, but only a written one counts as saved
        QVariantList settings = d.value(QStringLiteral("settings")).toList();
        for (QVariant &s : settings) {
            QVariantMap m = s.toMap();
            m[QStringLiteral("saved")] = savedChoices(h.id).contains(m.value(QStringLiteral("key")).toString());
            m[QStringLiteral("staged")] = staged.contains(m.value(QStringLiteral("key")).toString());
            s = m;
        }
        d[QStringLiteral("settings")] = settings;
        m_described << d;
    }
    // the controls are rebuilt only when something changed, so a refresh never interrupts a slider being dragged
    if (m_described != before || !m_everDescribed) {
        m_everDescribed = true;
        Q_EMIT headsetsChanged();
    }
}

void HeadsetKcm::stage(const QString &id, const QString &key, const QVariant &value)
{
    m_staged[id][key] = value;
    setNeedsSave(true);
    describeAll();
}

void HeadsetKcm::load()
{
    m_staged.clear();
    m_problem.clear();
    Q_EMIT problemChanged();
    setNeedsSave(false);
    refresh();
}

void HeadsetKcm::save()
{
    QStringList problems;
    for (auto h = m_staged.cbegin(); h != m_staged.cend(); ++h) {
        const Headset *headset = nullptr;
        for (const Headset &candidate : std::as_const(m_headsets)) {
            if (candidate.id == h.key()) {
                headset = &candidate;
            }
        }
        for (auto s = h.value().cbegin(); s != h.value().cend(); ++s) {
            if (!headset) {
                problems << i18n("The headset %1 is not connected now, so %2 was not changed.", h.key(), s.key());
                continue;
            }
            const QString error = apply(*headset, s.key(), s.value());
            if (error.isEmpty()) {
                saveChoice(h.key(), s.key(), s.value());
            } else {
                problems << error;
            }
        }
    }
    m_staged.clear();
    m_problem = problems.join(QLatin1Char(' '));
    Q_EMIT problemChanged();
    setNeedsSave(false);
    refresh();
}

void HeadsetKcm::defaults()
{
    // Back to what the headset does by itself: the saved choices of every connected headset are forgotten (the headset keeps what it has now)
    for (const Headset &h : std::as_const(m_headsets)) {
        forgetChoices(h.id);
    }
    m_staged.clear();
    setNeedsSave(false);
    refresh();
}

#include "headsetkcm.moc"
