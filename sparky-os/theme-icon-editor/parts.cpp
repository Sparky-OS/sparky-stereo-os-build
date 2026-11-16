// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include <KConfig>
#include <KConfigGroup>
#include <QFileDialog>
#include <QCryptographicHash>
#include <QDirIterator>
#include <QSet>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QPushButton>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <filesystem>

static QByteArray readPart(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error(file.errorString().toStdString());
    if (file.size() > 1024 * 1024) throw std::runtime_error(Editor::tr("The colour scheme is too large").toStdString());
    return file.readAll();
}

bool Editor::allClean() const
{
    return !membersDirty && history->isClean() && (!plasmaEditor || plasmaEditor->history->isClean());
}

void Editor::setupParts(QVBoxLayout *layout)
{
    projectLocation = new QLabel(tr("Open a theme. Save creates a separate project copy."));
    projectLocation->setWordWrap(true); layout->addWidget(projectLocation);
    auto *row = new QHBoxLayout;
    auto *colours = new QPushButton(tr("Open colour scheme…"));
    auto *edit = new QPushButton(tr("Edit colours in KDE…"));
    auto *plasma = new QPushButton(tr("Open Plasma SVG part…"));
    auto *explore = new QPushButton(tr("Explore Plasma theme…"));
    for (auto *button : {colours, edit, plasma, explore}) row->addWidget(button);
    layout->addLayout(row);
    colourLabel = new QLabel(tr("No colour scheme in this project"));
    colourLabel->setWordWrap(true); layout->addWidget(colourLabel);
    connect(colours, &QPushButton::clicked, this, [this] { guarded([&] {
        auto path = QFileDialog::getOpenFileName(this, tr("Colour scheme"), QStandardPaths::locate(QStandardPaths::GenericDataLocation, "color-schemes", QStandardPaths::LocateDirectory), "KDE (*.colors)");
        if (!path.isEmpty()) addColour(path);
    }); });
    connect(edit, &QPushButton::clicked, this, [this] { guarded([&] { editColour(); }); });
    connect(plasma, &QPushButton::clicked, this, [this] { guarded([&] {
        if (plasmaEditor && !plasmaEditor->mayDiscard()) return;
        auto root = QFileDialog::getExistingDirectory(this, tr("Plasma theme folder"));
        if (root.isEmpty()) return;
        auto path = QFileDialog::getOpenFileName(this, tr("SVG source"), root, "SVG (*.svg *.svgz)");
        if (!path.isEmpty()) addPlasma(root, path);
    }); });
    connect(explore, &QPushButton::clicked, this, [this] { guarded([&] { explorePlasma(); }); });
}

void Editor::addPlasma(const QString &root, const QString &path)
{
    ensurePeerClosed();
    const auto canonicalRoot = QFileInfo(root).canonicalFilePath();
    const auto canonicalPath = QFileInfo(path).canonicalFilePath();
    if (canonicalRoot.isEmpty() || !QFile::exists(canonicalRoot + "/metadata.json") || !canonicalPath.startsWith(canonicalRoot + "/"))
        throw std::runtime_error(tr("Choose an SVG inside a Plasma theme with metadata.json").toStdString());
    Drawing candidate; candidate.open(canonicalPath, false);
    if (!plasmaEditor) {
        plasmaEditor = new Editor(true);
        plasmaEditor->stereo->setChecked(stereo->isChecked());
        connect(stereo, &QCheckBox::toggled, plasmaEditor->stereo, &QCheckBox::setChecked);
        connect(plasmaEditor->stereo, &QCheckBox::toggled, stereo, &QCheckBox::setChecked);
        pages->addTab(plasmaEditor, tr("Plasma parts"));
        connect(plasmaEditor->history, &QUndoStack::cleanChanged, this, [this] { setWindowModified(!allClean()); });
        auto *open = new QPushButton(tr("Open Plasma SVG part…"));
        plasmaEditor->layout()->addWidget(open);
        connect(open, &QPushButton::clicked, this, [this] { guarded([&] {
            if (!plasmaEditor->mayDiscard()) return;
            const auto path = QFileDialog::getOpenFileName(this, tr("SVG source"), plasmaRoot, "SVG (*.svg *.svgz)");
            if (!path.isEmpty()) addPlasma(plasmaRoot, path);
        }); });
    }
    plasmaRoot = canonicalRoot; plasmaPath = QDir(plasmaRoot).relativeFilePath(canonicalPath);
    plasmaEditor->drawing = candidate;
    plasmaEditor->history->clear(); plasmaEditor->populateGroups();
    plasmaEditor->location->setText(tr("Read only source: %1. Save creates a separate project copy.").arg(canonicalPath));
    pages->setCurrentWidget(plasmaEditor);
    membersDirty = true; setWindowModified(true);
}

QString Editor::importColour(const QByteArray &bytes)
{
    QTemporaryFile file;
    if (!file.open() || file.write(bytes) != bytes.size() || !file.flush())
        throw std::runtime_error(tr("Cannot inspect the colour scheme").toStdString());
    KConfig config(file.fileName(), KConfig::SimpleConfig);
    if (!config.hasGroup("Colors:Window") || !config.hasGroup("General"))
        throw std::runtime_error(tr("Not a KDE colour scheme").toStdString());
    const auto name = KConfigGroup(&config, "General").readEntry("Name", QString());
    if (name.isEmpty()) throw std::runtime_error(tr("The colour scheme has no name").toStdString());
    colourBytes = bytes; colourName = name;
    colourLabel->setText(tr("Colour scheme: %1. KDE edits a private copy; Save keeps it in this project.").arg(name));
    membersDirty = true; setWindowModified(true);
    return name;
}

void Editor::addColour(const QString &path) { ensurePeerClosed(); importColour(readPart(path)); }

QString Editor::makePeerWork()
{
    if (peer && peer->state() != QProcess::NotRunning)
        throw std::runtime_error(tr("Close the KDE tool before opening another one.").toStdString());
    const auto root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/sparky-stereo-theme-editor/work";
    if (!QDir().mkpath(root)) throw std::runtime_error(tr("Cannot create a private working copy").toStdString());
    peerWork = std::make_unique<QTemporaryDir>(root + "/project-XXXXXX");
    if (!peerWork->isValid()) throw std::runtime_error(tr("Cannot create a private working copy").toStdString());
    return peerWork->path();
}

static QMap<QString, QByteArray> themeDigest(const QString &root)
{
    QMap<QString, QByteArray> result;
    QDirIterator files(root, QDir::Files | QDir::Hidden | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (files.hasNext()) {
        const auto path = files.next();
        const auto key = QDir(root).relativeFilePath(path);
        if (files.fileInfo().isSymLink()) {
            result[key] = QByteArray("link:") + QByteArray::fromStdString(std::filesystem::read_symlink(path.toStdString()).string());
        } else {
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error(file.errorString().toStdString());
            QCryptographicHash hash(QCryptographicHash::Sha256);
            if (!hash.addData(&file)) throw std::runtime_error(file.errorString().toStdString());
            result[key] = hash.result();
        }
    }
    return result;
}

void Editor::startPeer(const QString &program, const QStringList &arguments, bool colour, const QString &workingTheme)
{
    const auto before = colour ? QMap<QString, QByteArray>() : themeDigest(plasmaRoot);
    if (peer) peer->deleteLater();
    peer = new QProcess(this);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("XDG_DATA_HOME", peerWork->path() + "/data");
    env.insert("XDG_CONFIG_HOME", peerWork->path() + "/config");
    env.insert("XDG_CACHE_HOME", peerWork->path() + "/cache");
    peer->setProcessEnvironment(env);
    connect(peer, &QProcess::finished, this, [this, colour, before, workingTheme](int code, QProcess::ExitStatus status) { guarded([&] {
        if (code || status != QProcess::NormalExit)
            throw std::runtime_error(tr("The KDE tool failed: %1").arg(QString::fromUtf8(peer->readAllStandardError())).toStdString());
        if (colour) {
            auto stem = QString::fromUtf8(peer->readAllStandardOutput()).trimmed().split('\n').last();
            if (!stem.isEmpty()) {
                if (stem != QFileInfo(stem).fileName() || stem == "." || stem == "..")
                    throw std::runtime_error(tr("The KDE tool returned an invalid file name").toStdString());
                const auto bytes = readPart(peerWork->path() + "/data/color-schemes/" + stem + ".colors");
                if (bytes != colourBytes) importColour(bytes);
            }
        }
        if (!colour && themeDigest(workingTheme) != before) {
            Drawing next; next.open(workingTheme + "/" + plasmaPath, false);
            for (auto it = plasmaEditor->drawing.places.cbegin(); it != plasmaEditor->drawing.places.cend(); ++it)
                if (it.value()) next.setPlace(it.key(), it.value());
            plasmaWork = std::move(peerWork);
            plasmaRoot = workingTheme;
            plasmaEditor->drawing = next;
            plasmaEditor->populateGroups(); plasmaEditor->restorePlaces(next.places);
            membersDirty = true; setWindowModified(true);
        }
        peerWork.reset();
    }); });
    peer->start(program, arguments);
    if (!peer->waitForStarted(5000)) throw std::runtime_error(tr("Cannot start %1: %2").arg(program, peer->errorString()).toStdString());
}

void Editor::editColour()
{
    if (colourBytes.isEmpty()) throw std::runtime_error(tr("Open a colour scheme first").toStdString());
    auto path = makePeerWork();
    QDir().mkpath(path + "/data/color-schemes");
    saveBytes(path + "/data/color-schemes/ThemeEditorWorkingCopy.colors", colourBytes);
    startPeer("kcolorschemeeditor", {"ThemeEditorWorkingCopy", "--overwrite"}, true);
}

static void copyEditableTheme(const QString &source, const QString &destination)
{
    const auto root = QFileInfo(source).canonicalFilePath();
    QSet<QString> ancestors;
    std::function<void(const QString &, const QString &)> copy = [&](const QString &from, const QString &to) {
        QFileInfo info(from);
        const auto resolved = info.canonicalFilePath();
        if (resolved.isEmpty() || (resolved != root && !resolved.startsWith(root + "/")) || ancestors.contains(resolved))
            throw std::runtime_error(Editor::tr("The Plasma working copy contains an outside or cyclic link: %1").arg(from).toStdString());
        if (info.isDir()) {
            ancestors.insert(resolved);
            if (!QDir().mkpath(to)) throw std::runtime_error(Editor::tr("Cannot create a private working copy").toStdString());
            for (const auto &entry : QDir(from).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System))
                copy(entry.filePath(), to + "/" + entry.fileName());
            ancestors.remove(resolved);
        } else if (info.isFile()) {
            QFile file(resolved);
            if (!file.copy(to) || !QFile::setPermissions(to, info.permissions() | QFileDevice::ReadOwner | QFileDevice::WriteOwner))
                throw std::runtime_error(file.errorString().toStdString());
        } else {
            throw std::runtime_error(Editor::tr("Invalid or unsupported theme project").toStdString());
        }
    };
    copy(root, destination);
}

void Editor::explorePlasma()
{
    if (!plasmaEditor) throw std::runtime_error(tr("Open a Plasma theme part first").toStdString());
    auto path = makePeerWork();
    const auto metadata = QJsonDocument::fromJson(readPart(plasmaRoot + "/metadata.json")).object();
    const auto id = metadata.value("KPlugin").toObject().value("Id").toString();
    if (id.isEmpty() || QFileInfo(id).fileName() != id || id == "." || id == "..")
        throw std::runtime_error(tr("The Plasma theme has no valid identifier").toStdString());
    QDir().mkpath(path + "/data/plasma/desktoptheme");
    copyEditableTheme(plasmaRoot, path + "/data/plasma/desktoptheme/" + id);
    // The explorer receives the ordinary source; paired exports remain separate until Plasma consumes them.
    startPeer("plasmathemeexplorer", {"--theme", id}, false, path + "/data/plasma/desktoptheme/" + id);
}

void Editor::saveParts(const QString &stage, QJsonObject &project)
{
    if (!colourBytes.isEmpty()) {
        QDir().mkpath(stage + "/color-schemes");
        saveBytes(stage + "/color-schemes/Project.colors", colourBytes);
        project["colour"] = "color-schemes/Project.colors";
    }
    if (plasmaEditor) {
        std::filesystem::copy(plasmaRoot.toStdString(), (stage + "/plasma").toStdString(),
            std::filesystem::copy_options::recursive | std::filesystem::copy_options::copy_symlinks);
        auto &part = plasmaEditor->drawing;
        part.readLimits();
        QJsonObject levels;
        for (auto it = part.places.cbegin(); it != part.places.cend(); ++it) levels[it.key()] = it.value();
        project["plasma"] = QJsonObject{{"source", plasmaPath}, {"groups", levels},
            {"sunk", part.sunk()}, {"popped", part.popped()}};
        QDir().mkpath(stage + "/plasma-pairs");
        const int n = plasmaEditor->size->value();
        saveBytes(stage + "/plasma-pairs/part.svg", part.pairSvg(n));
        savePns(stage + "/plasma-pairs/part.pns", part.eye(n, false), part.eye(n, true));
        project["plasma-width"] = n;
    }
}

void Editor::loadParts(const QString &path, const QJsonObject &project)
{
    if (plasmaEditor) { pages->removeTab(pages->indexOf(plasmaEditor)); delete plasmaEditor; plasmaEditor = nullptr; }
    plasmaWork.reset();
    colourBytes.clear(); colourName.clear();
    colourLabel->setText(tr("No colour scheme in this project"));
    if (project.contains("colour")) {
        if (project.value("colour").toString() != "color-schemes/Project.colors")
            throw std::runtime_error(tr("Invalid or unsupported theme project").toStdString());
        addColour(path + "/color-schemes/Project.colors");
    }
    if (project.contains("plasma")) {
        const auto part = project.value("plasma").toObject();
        addPlasma(path + "/plasma", path + "/plasma/" + part.value("source").toString());
        plasmaEditor->applyPlaces(part.value("groups").toObject());
        plasmaEditor->size->setValue(project.value("plasma-width").toInt(256));
    }
    membersDirty = false; setWindowModified(false);
}

QString Editor::addColourFile(const QString &path)
{
    try { addColour(path); return {}; } catch (const std::exception &e) { return QString::fromUtf8(e.what()); }
}
QString Editor::addPlasmaFile(const QString &path)
{
    try {
        QDir root(QFileInfo(path).absolutePath());
        while (!root.exists("metadata.json")) if (!root.cdUp()) throw std::runtime_error(tr("Plasma theme folder").toStdString());
        addPlasma(root.path(), path); return {};
    } catch (const std::exception &e) { return QString::fromUtf8(e.what()); }
}
QString Editor::peerState() const
{
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"colour", colourName}, {"plasma", plasmaPath},
        {"workingCopy", peerWork ? peerWork->path() : QString()}, {"running", peer && peer->state() != QProcess::NotRunning},
        {"part", plasmaEditor ? QJsonDocument::fromJson(plasmaEditor->sessionState().toUtf8()).object() : QJsonObject()}}).toJson(QJsonDocument::Compact));
}
QString Editor::launchColourEditor()
{
    try { editColour(); return {}; } catch (const std::exception &e) { return QString::fromUtf8(e.what()); }
}
QString Editor::launchThemeExplorer()
{
    try { explorePlasma(); return {}; } catch (const std::exception &e) { return QString::fromUtf8(e.what()); }
}

QString Editor::setPlasmaDepth(const QString &id, double value)
{
    if (!plasmaEditor) return tr("Open a Plasma theme part first");
    pages->setCurrentWidget(plasmaEditor);
    return plasmaEditor->setGroupDepth(id, value);
}

void Editor::ensurePeerClosed() const
{
    if (peer && peer->state() != QProcess::NotRunning)
        throw std::runtime_error(tr("Close the KDE tool before opening another one.").toStdString());
}
