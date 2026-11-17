// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"


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
#if STUDIO_MODELS
#include "models/page.h"
#endif
#include "identity.h"
#include <QDoubleSpinBox>
#include <QHeaderView>
#include <QtMath>
#include <QCloseEvent>
#include <algorithm>
#include <cmath>
#include <QScreen>
#include <QWindow>
#include <QShowEvent>
#include <QTimer>
#include <QJsonArray>
static QImage highlight(QImage image, const QImage &mask);

Editor::Editor(bool part)
    : partMode(part)
{
    Preview::prepareWindow(this);
    setWindowTitle(Identity::product() + "[*]");
    resize(1120, 720);
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
    auto *sharedLayout = layout;
    if (!partMode) {
        setupParts(layout);
        pages = new QTabWidget;
        layout->addWidget(pages);
        auto *iconPage = new QWidget;
        pages->addTab(iconPage, tr("Icons"));
        layout = new QVBoxLayout(iconPage);
#if STUDIO_MODELS
        modelPage = new ModelPage(this);
        pages->addTab(modelPage, tr("Models"));
        auto *openModel = new QPushButton(tr("Open model…"));
        files->addWidget(openModel);
        connect(openModel, &QPushButton::clicked, this, [this] { guarded([&] {
            const auto path = QFileDialog::getOpenFileName(this,tr("Open model…"),{},"glTF (*.gltf *.glb)");
            if (!path.isEmpty()) { const auto error=openModelFile(path); if(!error.isEmpty())throw std::runtime_error(error.toStdString()); }
        }); });
#endif
    }
    auto *actions = new QHBoxLayout;
    stereo = new QCheckBox(tr("Enable 3D"));
    stereo->setChecked(STUDIO_STEREO);
    if (!STUDIO_STEREO) stereo->hide();
    size = new QSpinBox;
    size->setRange(8, 2048); size->setValue(256);
    size->setPrefix(tr("Pixels per view: "));
    auto *settings = new QPushButton(tr("Display Settings…"));
    for (auto *w : QList<QWidget *>{stereo, size, settings}) actions->addWidget(w);
    if (!STUDIO_STEREO) settings->hide();
    sharedLayout->insertLayout(partMode ? 1 : 2, actions);
    location = new QLabel(tr("Open a theme. Save creates a separate project copy."));
    location->setWordWrap(true); layout->addWidget(location);
    auto *body = new QHBoxLayout;
    groups = new QTreeWidget;
    groups->setObjectName("groups");
    groups->setHeaderLabels({tr("Part"), tr("Depth (% of limit)")});
    if (!STUDIO_STEREO) groups->hideColumn(1);
    groups->setIconSize(QSize(112, 88));
    groups->setColumnWidth(0, 320);
    groups->setToolTip(tr("Select a part to highlight it in both views. Negative depth sinks; positive depth pops."));
    auto *details = new QVBoxLayout;
    selection = new QLabel; selection->setWordWrap(true); selection->setTextFormat(Qt::PlainText);
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
    if (!STUDIO_STEREO) disparities->hide();
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
    preview->picked = [this](QPointF point) { guarded([&] { pickAt(point); }); };
    preview->failed = [this] { if (!preview->failure().isEmpty()) location->setText(preview->failure()); };

}

void Editor::guarded(const std::function<void()> &f)
{
    try { f(); } catch (const std::exception &e) {
        QMessageBox::critical(this, tr("Cannot complete the operation"), QString::fromUtf8(e.what()));
    }
}

void Editor::load(QString root, QString icon)
{
    setWindowTitle(QFileInfo(root).fileName() + "[*]");
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
    pickStack.clear(); lastPick = {-1000, -1000};
    { QSignalBlocker block(groups); groups->clear(); }
    for (const QString &id : drawing.groups()) {
        auto *item = new QTreeWidgetItem(groups, {drawing.groupLabel(id)});
        item->setData(0, Qt::UserRole, id);
        item->setToolTip(0, id);
        auto isolated = drawing.eye(512, false, id);
        QRect bounds;
        for (int y = 0; y < isolated.height(); ++y)
            for (int x = 0; x < isolated.width(); ++x)
                if (qAlpha(isolated.pixel(x, y))) bounds |= QRect(x, y, 1, 1);
        QImage thumbnail(112, 88, QImage::Format_ARGB32_Premultiplied);
        QPainter painter(&thumbnail);
        for (int y = 0; y < 88; y += 8) for (int x = 0; x < 112; x += 8)
            painter.fillRect(x, y, 8, 8, ((x/8+y/8)%2) ? QColor(185,185,185) : QColor(235,235,235));
        if (!bounds.isEmpty()) {
            const auto part = isolated.copy(bounds).scaled(100, 56, Qt::KeepAspectRatio, Qt::SmoothTransformation);
            painter.drawImage((112-part.width())/2, (60-part.height())/2, part);
        }
        // A context inset locates very thin highlights and outlines without deforming their isolated drawing.
        auto context = drawing.eye(56, false);
        context = highlight(context, drawing.eye(56, false, id));
        painter.drawImage(28, 60, context.scaled(56, 28, Qt::KeepAspectRatio, Qt::SmoothTransformation));
        painter.end();
        item->setIcon(0, QPixmap::fromImage(thumbnail));
        item->setSizeHint(0, QSize(112, 92));
        if (!STUDIO_STEREO) continue;
        auto *depth = new QDoubleSpinBox;
        depth->setRange(-100, 100); depth->setDecimals(1); depth->setSingleStep(5);
        depth->setSuffix(tr(" %"));
        depth->setObjectName(id);
        depth->setAccessibleName(tr("Depth of %1").arg(drawing.groupLabel(id)));
        auto *control = new QWidget;
        auto *controlLayout = new QHBoxLayout(control);
        controlLayout->setContentsMargins(0,0,0,0);
        controlLayout->addWidget(depth, 0, Qt::AlignVCenter);
        groups->setItemWidget(item, 1, control);
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
#if STUDIO_MODELS
    if(modelPage) modelPage->refresh();
#endif
    if (drawing.source.isEmpty()) return;
    auto *screen = windowHandle() ? windowHandle()->screen() : QGuiApplication::primaryScreen();
    if (!screen) throw std::runtime_error(tr("Cannot read the preview output").toStdString());
    if (observedScreen != screen) {
        disconnect(observedGeometry);
        observedScreen = screen;
        observedGeometry = connect(screen, &QScreen::geometryChanged, this, [this] { guarded([&] { refresh(); }); });
    }
    // On fractional Wayland outputs QScreen can report a rounded buffer scale.
    // The actual window's preferred fractional ratio gives physical output/presentation pixels.
    const qreal ratio = windowHandle() ? windowHandle()->devicePixelRatio() : devicePixelRatioF();
    drawing.readLimits(qRound(screen->geometry().width() * ratio), qRound(preview->width() * ratio));
    const auto id = selectedGroup();
    auto left = drawing.eye(size->value(), false);
    QImage right;
    if (STUDIO_STEREO) right = drawing.eye(size->value(), true);
    if (!id.isEmpty()) {
        left = highlight(left, drawing.eye(size->value(), false, id));
        if (STUDIO_STEREO) right = highlight(right, drawing.eye(size->value(), true, id));
    }
    preview->setViews(left, right, stereo->isChecked());
    disparities->setRowCount(0);
    if (id.isEmpty()) return;
    const qreal value = drawing.places.value(id);
    const auto exported = drawing.forExport();
    disparities->setColumnCount(3);
    disparities->setHorizontalHeaderLabels({tr("Size per view"), tr("Export (defaults)"), tr("Preview (desktop)")});
    selection->setText(tr("Selected: %1 (%2)").arg(drawing.groupLabel(id), value < 0 ? tr("Sunk") : value > 0 ? tr("Popped") : tr("Screen")));
    for (int n : themeSizes()) {
        const int row = disparities->rowCount(); disparities->insertRow(row);
        disparities->setItem(row, 0, new QTableWidgetItem(tr("%1 px").arg(n)));
        auto describe = [&](const Drawing &part) {
            const int pixels = part.disparity(id,n);
            QString text = pixels ? tr("%1 px").arg(pixels) : value ? tr("0 px (%1)").arg(part.depthNotice(id,n)) : tr("0 px (screen)");
            const auto ties = part.collapsedWith(id,n);
            if (!ties.isEmpty()) text += tr("; same pixel as %1").arg(ties.join(", "));
            return text;
        };
        auto *common = new QTableWidgetItem(describe(exported)); common->setToolTip(common->text());
        auto *personal = new QTableWidgetItem(describe(drawing)); personal->setToolTip(personal->text());
        disparities->setItem(row, 1, common);
        disparities->setItem(row, 2, personal);
    }
}

void Editor::restorePlaces(const QMap<QString, qreal> &places)
{
    drawing.places = places;
    for (int i = 0; i < groups->topLevelItemCount(); ++i) {
        auto *item = groups->topLevelItem(i);
        auto *control = groups->itemWidget(item, 1);
        auto *depth = control ? control->findChild<QDoubleSpinBox *>() : nullptr;
        if (!depth) continue;
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
        QMessageBox::information(this, Identity::product(), tr("Close the KDE tool before closing this project."));
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
        if (!STUDIO_STEREO) return tr("Enable 3D");
        auto *control = groups->itemWidget(groups->currentItem(), 1)->findChild<QDoubleSpinBox *>();
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
        rows.append(QJsonArray{disparities->item(row, 0)->text(), disparities->item(row, 1)->text(), disparities->columnCount()>2 && disparities->item(row,2) ? disparities->item(row,2)->text() : QString()});
    const QPoint global = preview->mapToGlobal(QPoint());
    auto *screen = windowHandle() ? windowHandle()->screen() : QGuiApplication::primaryScreen();
    QJsonObject metrics;
    if (screen) metrics = {{"screenDpr",screen->devicePixelRatio()}, {"widgetDpr",preview->devicePixelRatioF()}, {"windowDpr",windowHandle()?windowHandle()->devicePixelRatio():devicePixelRatioF()},
        {"screenWidth",screen->geometry().width()}, {"presentationPixels",qRound(preview->width()*(windowHandle()?windowHandle()->devicePixelRatio():devicePixelRatioF()))}};
    return QString::fromUtf8(QJsonDocument(QJsonObject{{"previewRect", QJsonArray{global.x(), global.y(), preview->width(), preview->height()}}, {"renderWidth", size->value()}, {"stereoAvailable", bool(STUDIO_STEREO)}, {"selected", selectedGroup()}, {"depths", depths},
        {"disparities", rows}, {"canUndo", history->canUndo()}, {"canRedo", history->canRedo()},
        {"desktopMetrics", metrics}, {"title", windowTitle()}, {"enable3d", stereo->text()}, {"pixelsPerView", size->prefix()},
        {"partHeader", groups->headerItem()->text(0)}}).toJson(QJsonDocument::Compact));
}

void Editor::loadProject(const QString &path)
{
    setWindowTitle(QFileInfo(path).fileName() + "[*]");
    QFile file(path + "/project.json");
    if (!file.open(QIODevice::ReadOnly)) throw std::runtime_error(tr("Cannot read the project").toStdString());
    QJsonParseError error;
    auto data = QJsonDocument::fromJson(file.readAll(), &error);
    auto project = data.object();
    if (error.error != QJsonParseError::NoError || project.value("version").toInt() != 1
        || !project.value("icon").isString() || !project.value("groups").isObject())
        throw std::runtime_error(tr("Invalid or unsupported theme project").toStdString());
#if STUDIO_MODELS
    if(modelPage && project.contains("model")) { modelPage->loadProject(path,project); return; }
#endif
    load(path + "/icons", path + "/icons/" + project.value("icon").toString());
    applyPlaces(project.value("groups").toObject());
    loadParts(path, project);
    setWindowTitle(QFileInfo(path).fileName() + "[*]");
    location->setText(tr("Project copy: %1").arg(path));
    if (projectLocation) projectLocation->setText(location->text());
}
void Editor::saveProject(const QString &destination)
{
#if STUDIO_MODELS
    if(modelPage && pages->currentWidget()==modelPage && !modelPage->source.isEmpty()) {modelPage->saveProject(destination);return;}
#endif
    ensurePeerClosed();
    if (drawing.source.isEmpty()) throw std::runtime_error(tr("Open a source first").toStdString());
    const auto exported = drawing.forExport();
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
        {"export-limits", QJsonObject{{"sunk", exported.sunk()}, {"popped", exported.popped()}}},
        {"source-sha256", QString::fromLatin1(QCryptographicHash::hash(drawing.original, QCryptographicHash::Sha256).toHex())}};
    QStringList stereoDirectories;
#if STUDIO_STEREO
    for (int n : sizes) {
        const QString directory = QString("%1/%2x%2/%3").arg(outputRoot).arg(n).arg(contextDirectory);
        stereoDirectories << directory;
        QDir().mkpath(stage.path() + "/icons/" + directory);
        QDir().mkpath(stage.path() + "/pairs");
        saveBytes(stage.path() + "/icons/" + directory + "/" + QFileInfo(iconPath).completeBaseName() + ".svg", exported.pairSvg(n));
        savePns(stage.path() + QString("/pairs/%1.pns").arg(n), exported.eye(n, false), exported.eye(n, true));
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

#endif
    saveParts(stage.path(), project);
    saveBytes(stage.path() + "/project.json", QJsonDocument(project).toJson());
    if (!QDir().rename(stage.path(), destination)) throw std::runtime_error(tr("Cannot commit the project folder").toStdString());
    stage.setAutoRemove(false);
    setWindowTitle(QFileInfo(destination).fileName() + "[*]");
    history->setClean();
    if (plasmaEditor) plasmaEditor->history->setClean();
    membersDirty = false; setWindowModified(false);
    location->setText(tr("Saved project copy: %1").arg(destination));
    if (projectLocation) projectLocation->setText(location->text());
}

bool Editor::setRenderWidth(int width)
{
    if (width < size->minimum() || width > size->maximum()) return false;
    size->setValue(width); return true;
}

void Editor::pickAt(QPointF point)
{
    if (drawing.source.isEmpty()) return;
    const QPoint pixel(qFloor(point.x() * size->value() / preview->width()),
                       qFloor(point.y() * drawing.height(size->value()) / preview->height()));
    if ((pixel-lastPick).manhattanLength() > 2 || pickStack.isEmpty()) {
        pickStack = drawing.hitGroups(pixel, size->value());
        pickIndex = 0; lastPick = pixel;
    } else { pickIndex = (pickIndex+1) % pickStack.size(); }
    if (!pickStack.isEmpty()) selectPart(pickStack[pickIndex]);
}

void Editor::showEvent(QShowEvent *event)
{
    QWidget::showEvent(event);
    guarded([&] { refresh(); });
    if (windowHandle() && observedWindow != windowHandle()) {
        observedWindow = windowHandle();
        connect(windowHandle(), &QWindow::screenChanged, this, [this] { guarded([&] { refresh(); }); });
    }
}

bool Editor::event(QEvent *event)
{
    const bool result = QWidget::event(event);
    if (event->type() == QEvent::DevicePixelRatioChange)
        QTimer::singleShot(0, this, [this] { guarded([&] { refresh(); }); });
    return result;
}

QString Editor::openModelFile(const QString &path)
{
#if STUDIO_MODELS
    try {if(!modelPage) return tr("The model helper is unavailable in this build.");modelPage->open(path);pages->setCurrentWidget(modelPage);return {};}catch(const std::exception &e){return QString::fromUtf8(e.what());}
#else
    Q_UNUSED(path);return tr("The model helper is unavailable in this build.");
#endif
}
QString Editor::setModelDepth(double value)
{
#if STUDIO_MODELS
    if(!modelPage || !std::isfinite(value) || value < -1 || value > 1) return tr("Invalid group or place");
    modelPage->depth->setValue(value*100);return {};
#else
    Q_UNUSED(value);return tr("The model helper is unavailable in this build.");
#endif
}
QString Editor::modelState() const
{
#if STUDIO_MODELS
    return modelPage?modelPage->state():QString();
#else
    return {};
#endif
}
QString Editor::exportModelPairs(const QString &path)
{
#if STUDIO_MODELS
    try{modelPage->exportPairs(path);return {};}catch(const std::exception &e){return QString::fromUtf8(e.what());}
#else
    Q_UNUSED(path);return tr("The model helper is unavailable in this build.");
#endif
}
QString Editor::saveCurrentProject(const QString &path)
{
    try{saveProject(path);return {};}catch(const std::exception &e){return QString::fromUtf8(e.what());}
}
