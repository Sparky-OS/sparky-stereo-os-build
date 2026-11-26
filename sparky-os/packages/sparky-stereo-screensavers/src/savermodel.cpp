// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "savermodel.h"

#include <KLocalizedString>

#include <QCollator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QXmlStreamReader>

namespace
{
QString twelve(const QJsonValue &value)
{
    return value.toString().left(12);
}

/* The sentence for one reason catalogue.diagnose gave (the same reasons the show's controller logs). */
QString reasonText(const QJsonObject &reason)
{
    const QString kind = reason.value(QLatin1String("kind")).toString();
    const QString path = reason.value(QLatin1String("path")).toString();
    const QString expected = twelve(reason.value(QLatin1String("expected")));
    const QString found = twelve(reason.value(QLatin1String("found")));
    if (kind == QLatin1String("executable-differs")) {
        return i18n("The installed saver %1 differs from the one qualified (qualified %2, installed %3).", path, expected, found);
    }
    if (kind == QLatin1String("settings-differs")) {
        return i18n("The settings file %1 differs from the one qualified (qualified %2, installed %3).", path, expected, found);
    }
    if (kind == QLatin1String("library-differs")) {
        return i18n("The stereo layer %1 differs from the one qualified (qualified %2, installed %3).", path, expected, found);
    }
    if (kind.endsWith(QLatin1String("-missing"))) {
        return i18n("The file %1 is not installed (qualified %2).", path, expected);
    }
    if (kind == QLatin1String("proof")) {
        return i18n("Its qualification record does not pass the checks.");
    }
    return i18n("Its qualification record is incomplete.");
}
}

SaverModel::SaverModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

SaverModel::Paths SaverModel::paths()
{
    Paths p;
    // a test gives the page a tree of its own
    const QString root = qEnvironmentVariable("SPARKY_SAVER_ROOT");
    if (!root.isEmpty()) {
        p.share.prepend(root);
        p.library.prepend(root);
        p.config.prepend(root);
        p.hacks.prepend(root);
    }
    return p;
}

void SaverModel::load(const Paths &paths)
{
    beginResetModel();
    m_savers.clear();
    m_problem.clear();
    QHash<QString, QString> reasons;
    QSet<QString> stereo;

    // the catalogue's own rule says which receipts hold on this system (catalogue.dropped, the code the show runs)
    QFile catalogueFile(paths.share + QLatin1String("/catalogue.json"));
    QFile inventoryFile(paths.share + QLatin1String("/savers.json"));
    if (!catalogueFile.open(QIODevice::ReadOnly) || !inventoryFile.open(QIODevice::ReadOnly)) {
        m_problem = i18n("The stereo savers are not installed (the package gl-stereo-savers). Install it to choose and see them.");
    } else {
        const QJsonArray entries = QJsonDocument::fromJson(catalogueFile.readAll()).array();
        const QJsonArray inventory = QJsonDocument::fromJson(inventoryFile.readAll()).array();
        QProcess python;
        python.start(QStringLiteral("python3"),
                     {QStringLiteral("-I"), QStringLiteral("-c"),
                      QStringLiteral("import sys, json\nsys.path.insert(0, sys.argv[1])\nimport catalogue\n"
                                     "print(json.dumps(catalogue.dropped(json.load(open(sys.argv[2])))))"),
                      paths.library, catalogueFile.fileName()});
        QJsonArray dropped;
        if (python.waitForFinished(30000) && python.exitStatus() == QProcess::NormalExit && python.exitCode() == 0) {
            dropped = QJsonDocument::fromJson(python.readAllStandardOutput()).array();
        } else {
            m_problem = i18n("The stereo savers could not be checked: %1", QString::fromUtf8(python.readAllStandardError()).trimmed().right(300));
        }
        for (const QJsonValue &item : dropped) {
            QStringList texts;
            for (const QJsonValue &reason : item.toArray().at(1).toArray()) {
                texts << reasonText(reason.toObject());
            }
            reasons.insert(item.toArray().at(0).toString(), texts.join(QLatin1Char(' ')));
        }
        QHash<QString, QJsonObject> described;
        for (const QJsonValue &item : inventory) {
            described.insert(item.toObject().value(QLatin1String("id")).toString(), item.toObject());
        }
        for (const QJsonValue &item : entries) {
            Saver saver;
            saver.id = item.toObject().value(QLatin1String("id")).toString();
            if (saver.id.isEmpty() || stereo.contains(saver.id)) {
                continue;
            }
            const QJsonObject about = described.value(saver.id);
            saver.title = about.value(QLatin1String("title")).toString(saver.id);
            QStringList authors;
            for (const QJsonValue &author : about.value(QLatin1String("authors")).toArray()) {
                authors << author.toString();
            }
            saver.authors = authors.join(QStringLiteral(", "));
            saver.stereo = true;
            saver.offered = !reasons.contains(saver.id) && m_problem.isEmpty();
            saver.reason = reasons.value(saver.id);
            stereo.insert(saver.id);
            m_savers.append(saver);
        }
    }

    // XScreenSaver's other programs: one description file each, beside the program
    static const QRegularExpression writtenBy(QStringLiteral("Written by ([^;.]+(?:\\.[^;.]+)*?)[;.]"));
    const QDir config(paths.config);
    for (const QString &file : config.entryList({QStringLiteral("*.xml")}, QDir::Files, QDir::Name)) {
        const QString id = QFileInfo(file).completeBaseName();
        if (stereo.contains(id) || !QFileInfo(paths.hacks + QLatin1Char('/') + id).isExecutable()) {
            continue;
        }
        QFile xml(config.filePath(file));
        if (!xml.open(QIODevice::ReadOnly)) {
            continue;
        }
        Saver saver;
        saver.id = id;
        saver.title = id;
        QXmlStreamReader reader(&xml);
        while (!reader.atEnd()) {
            if (reader.readNext() != QXmlStreamReader::StartElement) {
                continue;
            }
            if (reader.name() == QLatin1String("screensaver")) {
                saver.title = reader.attributes().value(QLatin1String("_label")).toString();
            } else if (reader.name() == QLatin1String("_description")) {
                const auto match = writtenBy.match(reader.readElementText().simplified());
                if (match.hasMatch()) {
                    saver.authors = match.captured(1);
                }
            }
        }
        if (saver.title.isEmpty()) {
            saver.title = id;
        }
        m_savers.append(saver);
    }
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(m_savers.begin(), m_savers.end(), [&collator](const Saver &a, const Saver &b) {
        return collator.compare(a.title, b.title) < 0;
    });
    endResetModel();
    Q_EMIT loaded();
}

void SaverModel::setStore(const QStringList &disabled, const QStringList &flat)
{
    QSet<QString> off(disabled.begin(), disabled.end()), on(flat.begin(), flat.end());
    QSet<QString> known;
    for (Saver &saver : m_savers) {
        known.insert(saver.id);
        saver.ticked = saver.stereo ? !off.contains(saver.id) : on.contains(saver.id);
    }
    m_unknownDisabled = off - known;
    m_unknownFlat = on - known;
    if (!m_savers.isEmpty()) {
        Q_EMIT dataChanged(index(0), index(m_savers.size() - 1), {TickedRole});
    }
    Q_EMIT ticksChanged();
}

QStringList SaverModel::disabled() const
{
    QStringList names(m_unknownDisabled.begin(), m_unknownDisabled.end());
    for (const Saver &saver : m_savers) {
        if (saver.stereo && !saver.ticked) {
            names << saver.id;
        }
    }
    names.sort();
    return names;
}

QStringList SaverModel::flat() const
{
    QStringList names(m_unknownFlat.begin(), m_unknownFlat.end());
    for (const Saver &saver : m_savers) {
        if (!saver.stereo && saver.ticked) {
            names << saver.id;
        }
    }
    names.sort();
    return names;
}

int SaverModel::stereoCount() const
{
    return std::count_if(m_savers.begin(), m_savers.end(), [](const Saver &saver) {
        return saver.stereo;
    });
}

int SaverModel::notOffered() const
{
    return std::count_if(m_savers.begin(), m_savers.end(), [](const Saver &saver) {
        return !saver.offered;
    });
}

int SaverModel::tickedCount() const
{
    return std::count_if(m_savers.begin(), m_savers.end(), [](const Saver &saver) {
        return saver.ticked && saver.offered;
    });
}

int SaverModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_savers.size();
}

QVariant SaverModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_savers.size()) {
        return {};
    }
    const Saver &saver = m_savers.at(index.row());
    switch (role) {
    case IdRole:
        return saver.id;
    case Qt::DisplayRole:
    case TitleRole:
        return saver.title;
    case StereoRole:
        return saver.stereo;
    case OfferedRole:
        return saver.offered;
    case ReasonRole:
        return saver.reason;
    case TickedRole:
        return saver.ticked;
    case AuthorsRole:
        return saver.authors;
    }
    return {};
}

QHash<int, QByteArray> SaverModel::roleNames() const
{
    return {{IdRole, "saverId"}, {TitleRole, "title"}, {StereoRole, "stereo"}, {OfferedRole, "offered"},
            {ReasonRole, "reason"}, {TickedRole, "ticked"}, {AuthorsRole, "authors"}};
}

QVariantMap SaverModel::get(int row) const
{
    if (row < 0 || row >= m_savers.size()) {
        return {};
    }
    const Saver &saver = m_savers.at(row);
    return {{QStringLiteral("saverId"), saver.id}, {QStringLiteral("title"), saver.title}, {QStringLiteral("stereo"), saver.stereo},
            {QStringLiteral("offered"), saver.offered}, {QStringLiteral("reason"), saver.reason}, {QStringLiteral("ticked"), saver.ticked},
            {QStringLiteral("authors"), saver.authors}};
}

int SaverModel::find(const QString &id) const
{
    for (int row = 0; row < m_savers.size(); ++row) {
        if (m_savers.at(row).id == id) {
            return row;
        }
    }
    return -1;
}

void SaverModel::setTicked(int row, bool ticked)
{
    if (row < 0 || row >= m_savers.size() || m_savers.at(row).ticked == ticked) {
        return;
    }
    m_savers[row].ticked = ticked;
    Q_EMIT dataChanged(index(row), index(row), {TickedRole});
    Q_EMIT ticksChanged();
}

void SaverModel::tickOnly(int row)
{
    if (row < 0 || row >= m_savers.size()) {
        return;
    }
    for (int i = 0; i < m_savers.size(); ++i) {
        m_savers[i].ticked = i == row;
    }
    Q_EMIT dataChanged(index(0), index(m_savers.size() - 1), {TickedRole});
    Q_EMIT ticksChanged();
}

void SaverModel::tickAllStereo()
{
    for (Saver &saver : m_savers) {
        saver.ticked = saver.stereo;
    }
    Q_EMIT dataChanged(index(0), index(m_savers.size() - 1), {TickedRole});
    Q_EMIT ticksChanged();
}
