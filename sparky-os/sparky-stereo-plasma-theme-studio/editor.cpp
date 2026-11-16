// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include <stereo-layer/widgetlayer.h>
#include <stereo-layer/picture.h>
#include <KConfig>
#include <KConfigGroup>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QCommandLineParser>
#include <QCryptographicHash>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QHBoxLayout>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QMessageBox>
#include <QPainter>
#include <QProcess>
#include <QPushButton>
#include <QSettings>
#include <QSet>
#include <QSignalBlocker>
#include <QSpinBox>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTimer>
#include <QTreeWidget>
#include <QVBoxLayout>
#include <filesystem>
#include <functional>
#include <iostream>

#include "editor.h"
#include "identity.h"
#include <QDoubleSpinBox>
#include <QHeaderView>
#include <QCloseEvent>
#include <algorithm>
#include <QJsonArray>
Editor::Editor(bool part)
    : partMode(part)
{
    Stereo::WidgetLayer::prepareWindow(this);
    setWindowTitle(Identity::product() + "[*]");
    resize(1000, 680);
    history = new QUndoStack(this);
    auto *layout = new QVBoxLayout(this);
    auto *files = new QHBoxLayout;
    auto *open = new QPushButton(tr("Open icon theme…"));
    auto *save = new QPushButton(tr("Save a project copy…"));
    open->setShortcut(QKeySequence::Open); save->setShortcut(QKeySequence::Save);
    auto *undo = new QPushButton(tr("Undo"));
    auto *redo = new QPushButton(tr("Redo"));
    undo->setObjectName("undo"); redo->setObjectName("redo");
    undo->setShortcut(QKeySequence::Undo); redo->setShortcut(QKeySequence::Redo);
    undo->setEnabled(false); redo->setEnabled(false);
    for (auto *w : {open, save, undo, redo}) files->addWidget(w);
    auto *about = new QPushButton(tr("About…"));
    files->addWidget(about);
    connect(about, &QPushButton::clicked, this, [this] {
        QMessageBox::about(this, Identity::product(), Identity::product() + "\n" + Identity::version() + "\n" + Identity::edition() + "\nDaniel Campos Ramos");
    });
    layout->addLayout(files);
    if (partMode) { open->hide(); save->hide(); }
    if (!partMode) {
        setupParts(layout);
        pages = new QTabWidget;
        layout->addWidget(pages);
        auto *iconPage = new QWidget;
        pages->addTab(iconPage, tr("Icons"));
        layout = new QVBoxLayout(iconPage);
    }
    auto *actions = new QHBoxLayout;
    stereo = new QCheckBox(tr("Enable 3D"));
    stereo->setChecked(true);
    size = new QSpinBox;
    size->setRange(8, 2048); size->setValue(256);
    size->setPrefix(tr("Pixels per view: "));
    auto *settings = new QPushButton(tr("Display Settings…"));
    for (auto *w : QList<QWidget *>{stereo, size, settings}) actions->addWidget(w);
    layout->addLayout(actions);
    location = new QLabel(tr("Open a theme. Save creates a separate project copy."));
    location->setWordWrap(true); layout->addWidget(location);
    auto *body = new QHBoxLayout;
    groups = new QTreeWidget;
    groups->setObjectName("groups");
    groups->setHeaderLabels({tr("Part"), tr("Depth (% of limit)")});
    groups->setIconSize(QSize(40, 40));
    groups->setColumnWidth(0, 250);
    groups->setToolTip(tr("Select a part to highlight it in both views. Negative depth sinks; positive depth pops."));
    auto *details = new QVBoxLayout;
    selection = new QLabel; selection->setWordWrap(true);
    details->addWidget(selection);
    preview = new Preview;
    details->addWidget(preview, 0, Qt::AlignCenter);
    disparities = new QTableWidget(0, 2);
    disparities->setObjectName("disparities");
    disparities->setHorizontalHeaderLabels({tr("Size per view"), tr("Disparity")});
    disparities->horizontalHeader()->setSectionResizeMode(QHeaderView::Stretch);
    disparities->setEditTriggers(QAbstractItemView::NoEditTriggers);
    disparities->setSelectionMode(QAbstractItemView::NoSelection);
    details->addWidget(disparities);
    body->addWidget(groups, 1); body->addLayout(details, 1);
    layout->addLayout(body);
    connect(open, &QPushButton::clicked, this, [this] { guarded([&] {
        if (!mayDiscard()) return;
        auto root = QFileDialog::getExistingDirectory(this, tr("Icon theme folder"));
        if (root.isEmpty()) return;
        if (QFile::exists(root + "/project.json")) { loadProject(root); return; }
        auto icon = QFileDialog::getOpenFileName(this, tr("SVG source"), root, "SVG (*.svg *.svgz)");
        if (!icon.isEmpty()) load(root, icon);
    }); });
    connect(save, &QPushButton::clicked, this, [this] { guarded([&] {
        auto destination = QFileDialog::getSaveFileName(this, tr("New project folder"), QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/theme-project");
        if (!destination.isEmpty()) saveProject(destination);
    }); });
    connect(undo, &QPushButton::clicked, history, &QUndoStack::undo);
    connect(redo, &QPushButton::clicked, history, &QUndoStack::redo);
    connect(history, &QUndoStack::canUndoChanged, undo, &QPushButton::setEnabled);
    connect(history, &QUndoStack::canRedoChanged, redo, &QPushButton::setEnabled);
    connect(history, &QUndoStack::cleanChanged, this, [this](bool) { setWindowModified(!allClean()); });
    connect(groups, &QTreeWidget::currentItemChanged, this, [this] { guarded([&] { refresh(); }); });
    connect(stereo, &QCheckBox::toggled, this, [this] { guarded([&] { refresh(); }); });
    connect(size, &QSpinBox::valueChanged, this, [this] { guarded([&] { refresh(); }); });
    connect(settings, &QPushButton::clicked, this, [this] {
        if (!QProcess::startDetached("kcmshell6", {"kcm_kscreen"}))
            QMessageBox::critical(this, tr("Display Settings"), tr("Cannot start Display Settings (kcmshell6)."));
    });
    connect(preview->layer, &Stereo::WidgetLayer::failureChanged, this, [this] {
        if (!preview->layer->failure().isEmpty()) location->setText(preview->layer->failure());
    });
}

void Editor::guarded(const std::function<void()> &f)
{
    try { f(); } catch (const std::exception &e) {
        QMessageBox::critical(this, tr("Cannot complete the operation"), QString::fromUtf8(e.what()));
    }
}

void Editor::load(QString root, QString icon)
{
    ensurePeerClosed();
    root = QFileInfo(root).canonicalFilePath();
    icon = QFileInfo(icon).canonicalFilePath();
    if (root.isEmpty() || !QFile::exists(root + "/index.theme") || !icon.startsWith(root + "/"))
        throw std::runtime_error(tr("Choose an icon inside a readable theme with index.theme").toStdString());
    Drawing next; next.open(icon);
    drawing = next; themeRoot = root; iconPath = QDir(root).relativeFilePath(icon);
    history->clear();
    populateGroups();
    location->setText(tr("Read only source: %1. Save creates a separate project copy.").arg(root));
    if (projectLocation) projectLocation->setText(location->text());
    refresh();
}

void Editor::populateGroups()
{
    { QSignalBlocker block(groups); groups->clear(); }
    for (const QString &id : drawing.groups()) {
        auto *item = new QTreeWidgetItem(groups, {drawing.groupLabel(id)});
        item->setData(0, Qt::UserRole, id);
        item->setToolTip(0, id);
        auto thumbnail = drawing.eye(128, false, id);
        QRect bounds;
        for (int y = 0; y < thumbnail.height(); ++y)
            for (int x = 0; x < thumbnail.width(); ++x)
                if (qAlpha(thumbnail.pixel(x, y))) bounds |= QRect(x, y, 1, 1);
        if (!bounds.isEmpty()) thumbnail = thumbnail.copy(bounds).scaled(40, 40, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        item->setIcon(0, QPixmap::fromImage(thumbnail));
        auto *depth = new QDoubleSpinBox;
        depth->setRange(-100, 100); depth->setDecimals(1); depth->setSingleStep(5);
        depth->setSuffix(tr(" %"));
        depth->setObjectName(id);
        depth->setAccessibleName(tr("Depth of %1").arg(drawing.groupLabel(id)));
        groups->setItemWidget(item, 1, depth);
        connect(depth, &QDoubleSpinBox::valueChanged, this, [this, id, item](double value) {
            guarded([&] { groups->setCurrentItem(item); changeDepth(id, value / 100.0); });
            restorePlaces(drawing.places);
        });
    }
    if (groups->topLevelItemCount()) groups->setCurrentItem(groups->topLevelItem(0));
    refresh();
}

QString Editor::selectedGroup() const
{
    const auto *item = groups->currentItem();
    return item ? item->data(0, Qt::UserRole).toString() : QString();
}

QList<int> Editor::themeSizes() const
{
    if (partMode) return {size->value()};
    KConfig index(themeRoot + "/index.theme", KConfig::SimpleConfig);
    QSet<int> values;
    for (const auto &name : index.groupList()) {
        const int n = KConfigGroup(&index, name).readEntry("Size", 0);
        if (n > 0 && n <= 2048) values.insert(n);
    }
    auto sizes = values.values(); std::sort(sizes.begin(), sizes.end());
    return sizes;
}

static QImage highlight(QImage image, const QImage &mask)
{
    QImage tint(mask.size(), QImage::Format_ARGB32_Premultiplied);
    tint.fill(Qt::transparent);
    for (int y = 0; y < mask.height(); ++y)
        for (int x = 0; x < mask.width(); ++x)
            if (qAlpha(mask.pixel(x, y))) tint.setPixelColor(x, y, QColor(255, 190, 0, qAlpha(mask.pixel(x, y)) / 2));
    QPainter painter(&image); painter.drawImage(0, 0, tint);
    return image;
}

void Editor::refresh()
{
    if (drawing.source.isEmpty()) return;
    drawing.readLimits();
    const auto id = selectedGroup();
    auto left = drawing.eye(size->value(), false);
    auto right = drawing.eye(size->value(), true);
    if (!id.isEmpty()) {
        left = highlight(left, drawing.eye(size->value(), false, id));
        right = highlight(right, drawing.eye(size->value(), true, id));
    }
    preview->setViews(left, right, stereo->isChecked());
    disparities->setRowCount(0);
    if (id.isEmpty()) return;
    const qreal value = drawing.places.value(id);
    selection->setText(tr("Selected: %1 (%2)").arg(drawing.groupLabel(id), value < 0 ? tr("Sunk") : value > 0 ? tr("Popped") : tr("Screen")));
    for (int n : themeSizes()) {
        const int row = disparities->rowCount(); disparities->insertRow(row);
        const int pixels = drawing.disparity(id, n);
        disparities->setItem(row, 0, new QTableWidgetItem(tr("%1 px").arg(n)));
        const auto text = pixels ? tr("%1 px").arg(pixels) : value ? tr("0 px (no depth at this size)") : tr("0 px (screen)");
        disparities->setItem(row, 1, new QTableWidgetItem(text));
    }
}

void Editor::restorePlaces(const QMap<QString, qreal> &places)
{
    drawing.places = places;
    for (int i = 0; i < groups->topLevelItemCount(); ++i) {
        auto *item = groups->topLevelItem(i);
        auto *depth = static_cast<QDoubleSpinBox *>(groups->itemWidget(item, 1));
        QSignalBlocker block(depth);
        depth->setValue(100.0 * drawing.places.value(item->data(0, Qt::UserRole).toString()));
    }
    refresh();
}

class DepthCommand : public QUndoCommand
{
    Editor *editor;
    QMap<QString, qreal> before, after;
public:
    DepthCommand(Editor *e, QMap<QString, qreal> b, QMap<QString, qreal> a)
        : editor(e), before(std::move(b)), after(std::move(a)) {}
    void undo() override { editor->restorePlaces(before); }
    void redo() override { editor->restorePlaces(after); }
};

void Editor::changeDepth(const QString &id, qreal value)
{
    if (drawing.places.value(id) == value) return;
    Drawing next = drawing; next.setPlace(id, value);
    history->push(new DepthCommand(this, drawing.places, next.places));
}

void Editor::applyPlaces(const QJsonObject &object)
{
    Drawing candidate = drawing;
    for (auto i = candidate.places.begin(); i != candidate.places.end(); ++i) i.value() = 0;
    for (auto i = object.begin(); i != object.end(); ++i) {
        if (!i.value().isDouble()) throw std::runtime_error(tr("A group depth must be a number").toStdString());
        candidate.setPlace(i.key(), i.value().toDouble());
    }
    restorePlaces(candidate.places);
    history->clear();
}

bool Editor::mayDiscard()
{
    return allClean() || QMessageBox::question(this, tr("Unsaved changes"),
        tr("Discard unsaved changes?"), QMessageBox::Discard | QMessageBox::Cancel, QMessageBox::Cancel) == QMessageBox::Discard;
}

void Editor::closeEvent(QCloseEvent *event)
{
    if (peer && peer->state() != QProcess::NotRunning) {
        QMessageBox::information(this, tr("Theme editor"), tr("Close the KDE tool before closing this project."));
        event->ignore();
    } else if (mayDiscard()) event->accept(); else event->ignore();
}

bool Editor::selectPart(const QString &id)
{
    for (int i = 0; i < groups->topLevelItemCount(); ++i) {
        auto *item = groups->topLevelItem(i);
        if (item->data(0, Qt::UserRole).toString() == id) {
            groups->setCurrentItem(item);
            groups->scrollToItem(item);
            return true;
        }
    }
    return false;
}

QString Editor::setGroupDepth(const QString &id, double value)
{
    try {
        Drawing candidate = drawing;
        candidate.setPlace(id, value);
        if (!selectPart(id)) return tr("Invalid group or place");
        auto *control = static_cast<QDoubleSpinBox *>(groups->itemWidget(groups->currentItem(), 1));
        control->setValue(value * 100.0);
        return {};
    } catch (const std::exception &e) { return QString::fromUtf8(e.what()); }
}

QString Editor::sessionState() const
{
    QJsonObject depths;
    for (auto i = drawing.places.cbegin(); i != drawing.places.cend(); ++i) depths[i.key()] = i.value();
    QJsonArray rows;
    for (int row = 0; row < disparities->rowCount(); ++row)
        rows.append(QJsonArray{disparities->item(row, 0)->text(), disparities->item(row, 1)->text()});
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"selected", selectedGroup()}, {"depths", depths},
        {"disparities", rows}, {"canUndo", history->canUndo()}, {"canRedo", history->canRedo()},
        {"title", windowTitle()}, {"enable3d", stereo->text()}, {"pixelsPerView", size->prefix()},
        {"partHeader", groups->headerItem()->text(0)}}).toJson(QJsonDocument::Compact));
}

void Editor::loadProject(const QString &path)
{
    QFile file(path + "/project.json");
    if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error(tr("Cannot read the project").toStdString());
    QJsonParseError error;
    auto data = QJsonDocument::fromJson(file.readAll(), &error);
    auto project = data.object();
    if (error.error != QJsonParseError::NoError || project.value("version").toInt() != 1
        || !project.value("icon").isString() || !project.value("groups").isObject())
        throw std::runtime_error(tr("Invalid or unsupported theme project").toStdString());
    load(path + "/icons", path + "/icons/" + project.value("icon").toString());
    applyPlaces(project.value("groups").toObject());
    loadParts(path, project);
    location->setText(tr("Project copy: %1").arg(path));
    if (projectLocation) projectLocation->setText(location->text());
}
void Editor::saveProject(const QString &destination)
{
    ensurePeerClosed();
    if (drawing.source.isEmpty()) throw std::runtime_error(tr("Open a source first").toStdString());
    drawing.readLimits();
    if (QFileInfo::exists(destination)) throw std::runtime_error(tr("The project destination already exists; choose a new folder").toStdString());
    const auto parent = QFileInfo(destination).absolutePath();
    const QString canonicalParent = QFileInfo(parent).canonicalFilePath();
    if (canonicalParent == themeRoot || canonicalParent.startsWith(themeRoot + "/"))
        throw std::runtime_error(tr("Save the copy outside its source theme").toStdString());
    QTemporaryDir stage(parent + "/.theme-editor-XXXXXX");
    if (!stage.isValid()) throw std::runtime_error(tr("Cannot create the project beside its destination").toStdString());
    namespace fs = std::filesystem;
    fs::copy(themeRoot.toStdString(), (stage.path() + "/icons").toStdString(), fs::copy_options::recursive | fs::copy_options::copy_symlinks);
    if (QFileInfo(stage.path() + "/icons/index.theme").isSymLink())
        throw std::runtime_error(tr("A project index must be a regular file").toStdString());
    const QString copiedIndex = stage.path() + "/icons/index.theme";
    if (!QFile::setPermissions(copiedIndex, QFile::permissions(copiedIndex) | QFileDevice::WriteOwner))
        throw std::runtime_error(tr("Cannot make the copied index writable").toStdString());
    fs::permissions((stage.path() + "/icons").toStdString(), fs::perms::owner_write | fs::perms::owner_exec, fs::perm_options::add);
    QString outputRoot = "stereo-authored";
    for (int generation = 2; QFileInfo::exists(stage.path() + "/icons/" + outputRoot)
        || QFileInfo(stage.path() + "/icons/" + outputRoot).isSymLink(); ++generation)
        outputRoot = QString("stereo-authored-%1").arg(generation);
    KConfig sourceIndex(themeRoot + "/index.theme", KConfig::SimpleConfig);
    QSet<int> sizes;
    QMap<QString, QString> contexts;
    for (const QString &section : sourceIndex.groupList()) {
        KConfigGroup group(&sourceIndex, section);
        const int n = group.readEntry("Size", 0);
        if (n > 2048) throw std::runtime_error(tr("Declared icon size exceeds the supported 2048 pixels per view").toStdString());
        if (n > 0) sizes.insert(n);
        const auto context = group.readEntry("Context", QString());
        if (!context.isEmpty()) contexts[section.section('/', -1)] = context;
    }
    if (sizes.isEmpty()) throw std::runtime_error(tr("The theme declares no usable sizes").toStdString());
    QString contextDirectory;
    const auto parts = iconPath.split('/');
    for (int i = parts.size() - 2; i >= 0; --i)
        if (contexts.contains(parts[i])) { contextDirectory = parts[i]; break; }
    if (contextDirectory.isEmpty()) throw std::runtime_error(tr("Choose an SVG source inside a context declared in index.theme").toStdString());
    QJsonObject levels;
    for (auto i = drawing.places.cbegin(); i != drawing.places.cend(); ++i) levels[i.key()] = i.value();
    QJsonObject project{{"version", 1}, {"icon", iconPath}, {"groups", levels},
        {"export-limits", QJsonObject{{"sunk", drawing.sunk()}, {"popped", drawing.popped()}}},
        {"source-sha256", QString::fromLatin1(QCryptographicHash::hash(drawing.original, QCryptographicHash::Sha256).toHex())}};
    QStringList stereoDirectories;
    for (int n : sizes) {
        const QString directory = QString("%1/%2x%2/%3").arg(outputRoot).arg(n).arg(contextDirectory);
        stereoDirectories << directory;
        QDir().mkpath(stage.path() + "/icons/" + directory);
        QDir().mkpath(stage.path() + "/pairs");
        saveBytes(stage.path() + "/icons/" + directory + "/" + QFileInfo(iconPath).completeBaseName() + ".svg", drawing.pairSvg(n));
        savePns(stage.path() + QString("/pairs/%1.pns").arg(n), drawing.eye(n, false), drawing.eye(n, true));
    }
    {
        KConfig index(stage.path() + "/icons/index.theme", KConfig::SimpleConfig);
        KConfigGroup theme(&index, "Icon Theme");
        const auto oldDirectories = theme.readEntry("X-StereoDirectories", QStringList());
        theme.writeEntry("X-StereoDirectories", stereoDirectories + oldDirectories);
        for (int n : sizes) {
            KConfigGroup group(&index, QString("%1/%2x%2/%3").arg(outputRoot).arg(n).arg(contextDirectory));
            group.writeEntry("X-StereoSize", n);
            group.writeEntry("X-StereoLayout", "sbs-left-first");
            group.writeEntry("Type", "Fixed");
            group.writeEntry("Context", contexts.value(contextDirectory));
        }
        if (!index.sync()) throw std::runtime_error(tr("Cannot save the copied theme index").toStdString());
    }
    saveParts(stage.path(), project);
    saveBytes(stage.path() + "/project.json", QJsonDocument(project).toJson());
    if (!QDir().rename(stage.path(), destination)) throw std::runtime_error(tr("Cannot commit the project folder").toStdString());
    stage.setAutoRemove(false);
    history->setClean();
    if (plasmaEditor) plasmaEditor->history->setClean();
    membersDirty = false; setWindowModified(false);
    location->setText(tr("Saved project copy: %1").arg(destination));
    if (projectLocation) projectLocation->setText(location->text());
}
