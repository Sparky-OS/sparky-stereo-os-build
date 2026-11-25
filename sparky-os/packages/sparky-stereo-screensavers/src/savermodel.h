// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QSet>
#include <QVariantMap>

/* Every saver the installed packages ship: the stereo catalogue's (drawn as a
 * pair) and XScreenSaver's other programs (one view, the same in both eyes). */
class SaverModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY loaded)
    Q_PROPERTY(int stereoCount READ stereoCount NOTIFY loaded)
    Q_PROPERTY(int flatCount READ flatCount NOTIFY loaded)
    Q_PROPERTY(int notOffered READ notOffered NOTIFY loaded)
    Q_PROPERTY(int tickedCount READ tickedCount NOTIFY ticksChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY loaded)

public:
    enum Roles { IdRole = Qt::UserRole + 1, TitleRole, StereoRole, OfferedRole, ReasonRole, TickedRole, AuthorsRole };
    struct Saver {
        QString id, title, authors, reason;
        bool stereo = false, offered = true, ticked = false;
    };
    struct Paths {
        QString share = QStringLiteral("/usr/share/gl-stereo");
        QString library = QStringLiteral("/usr/lib/gl-stereo/savers");
        QString config = QStringLiteral("/usr/share/xscreensaver/config");
        QString hacks = QStringLiteral("/usr/libexec/xscreensaver");
    };

    explicit SaverModel(QObject *parent = nullptr);
    static Paths paths();
    void load(const Paths &paths);
    /* The store: the catalogue savers left out, the 2D savers ticked. */
    void setStore(const QStringList &disabled, const QStringList &flat);
    QStringList disabled() const;
    QStringList flat() const;

    int count() const { return m_savers.size(); }
    int stereoCount() const;
    int flatCount() const { return count() - stereoCount(); }
    int notOffered() const;
    int tickedCount() const;
    QString problem() const { return m_problem; }

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int find(const QString &id) const;
    Q_INVOKABLE void setTicked(int row, bool ticked);
    Q_INVOKABLE void tickOnly(int row);
    Q_INVOKABLE void tickAllStereo();

Q_SIGNALS:
    void loaded();
    void ticksChanged();

private:
    QList<Saver> m_savers;
    QSet<QString> m_unknownDisabled, m_unknownFlat; // names the store holds for savers not installed now: kept as they are
    QString m_problem;
};
