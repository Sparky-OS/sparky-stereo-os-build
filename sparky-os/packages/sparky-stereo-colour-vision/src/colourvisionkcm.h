// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KQuickConfigModule>

#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QTimer>
#include <QVariantList>

// The Colour vision page: one choice (none, protan, deutan, tritan, mono) and the terminals box.
// Every read and every write goes through the helper (sparky-stereo-colour-vision), the one place
// that knows the surfaces, so the page, the login sync and the tests share one code path.
class ColourVisionKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QString kind READ kind WRITE setKind NOTIFY kindChanged)
    Q_PROPERTY(bool terminals READ terminals WRITE setTerminals NOTIFY terminalsChanged)
    Q_PROPERTY(QVariantList surfaces READ surfaces NOTIFY surfacesChanged)
    Q_PROPERTY(QString helperError READ helperError NOTIFY surfacesChanged)

public:
    ColourVisionKcm(QObject *parent, const KPluginMetaData &data);

    QString kind() const
    {
        return m_kind;
    }
    void setKind(const QString &kind);
    bool terminals() const
    {
        return m_terminals;
    }
    void setTerminals(bool terminals);
    QVariantList surfaces() const
    {
        return m_surfaces;
    }
    QString helperError() const
    {
        return m_helperError;
    }

public Q_SLOTS:
    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void kindChanged();
    void terminalsChanged();
    void surfacesChanged();

private:
    bool runHelper(const QStringList &arguments, QJsonObject *result);
    void takeStatus(const QJsonObject &status);
    void updateNeedsSave();
    void watchConfig();

    QString m_kind = QStringLiteral("none");
    QString m_savedKind = QStringLiteral("none");
    bool m_terminals = false;
    bool m_savedTerminals = false;
    QVariantList m_surfaces;
    QString m_helperError;
    QFileSystemWatcher m_watcher;
    QTimer m_reload;
};
