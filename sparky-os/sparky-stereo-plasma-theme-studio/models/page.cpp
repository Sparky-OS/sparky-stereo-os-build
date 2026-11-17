// SPDX-License-Identifier: GPL-2.0-or-later
#include "page.h"
#include "assets.h"
#include "camera.h"
#include "depth-interface.h"
#include "editor.h"
#include <KConfig>
#include <KConfigGroup>
#include <QBuffer>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QPushButton>
#include <QScreen>
#include <QSignalBlocker>
#include <QStandardPaths>
#include <QTabWidget>
#include <QWindow>
#include <filesystem>
#include <stdexcept>

static void require(bool ok, const QString& why)
{
    if (!ok)
        throw std::runtime_error(why.toStdString());
}
static QByteArray bytes(const QString& path)
{
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), Editor::tr("Cannot read model: %1").arg(path));
    return file.readAll();
}
static QList<int> sizes(Editor* editor)
{
    return editor->themeRoot.isEmpty() ? QList<int> { 8, 16, 22, 24, 32, 48, 64, 128, 256 }
                                       : editor->themeSizes();
}
class ModelDepthCommand : public QUndoCommand {
    ModelPage* page;
    double before, after;

public:
    ModelDepthCommand(ModelPage* p, double b, double a)
        : QUndoCommand(Editor::tr("Depth (% of limit)"))
        , page(p)
        , before(b)
        , after(a)
    {
    }
    void undo() override { page->restoreDepth(before); }
    void redo() override { page->restoreDepth(after); }
};
void ModelPage::restoreDepth(double value)
{
    {
        QSignalBlocker block(depth);
        depth->setValue(value);
    }
    committedDepth = value;
    metadata.clear();
    images.clear();
    refresh();
}
ModelPage::ModelPage(Editor* owner)
    : QWidget(owner)
    , editor(owner)
{
    auto* layout = new QVBoxLayout(this);
    sourceLabel = new QLabel(Editor::tr("Open a glTF model. The source is read only."));
    sourceLabel->setWordWrap(true);
    layout->addWidget(sourceLabel);
    auto* row = new QHBoxLayout;
    row->addWidget(new QLabel(Editor::tr("Depth (% of limit)")));
    depth = new QDoubleSpinBox;
    depth->setRange(-100, 100);
    depth->setDecimals(1);
    depth->setSingleStep(5);
    row->addWidget(depth);
    auto* exporter = new QPushButton(Editor::tr("Export model pairs…"));
    row->addWidget(exporter);
    layout->addLayout(row);
    preview = new Preview;
    layout->addWidget(preview, 0, Qt::AlignCenter);
    summary = new QLabel;
    summary->setWordWrap(true);
    summary->setTextFormat(Qt::PlainText);
    layout->addWidget(summary);
    layout->addStretch();
    connect(depth, &QDoubleSpinBox::valueChanged, this, [this](double value) {
        editor->guarded([&] {
            metadata.clear();
            images.clear();
            try {
                if (!source.isEmpty())
                    render(editor->size->value(), false, !editor->stereo->isChecked());
            } catch (...) {
                QSignalBlocker block(depth);
                depth->setValue(committedDepth);
                throw;
            }
            if (value != committedDepth)
                editor->history->push(new ModelDepthCommand(this, committedDepth, value));
        });
    });
    connect(exporter, &QPushButton::clicked, this, [this] {
        editor->guarded([&] {
            auto path = QFileDialog::getSaveFileName(this, Editor::tr("New project folder"));
            if (!path.isEmpty())
                exportPairs(path);
        });
    });
    preview->failed = [this] {
        if (!preview->failure().isEmpty())
            summary->setText(preview->failure());
    };
}
QJsonObject ModelPage::render(int n, bool common, bool flat, QImage* left, QImage* right)
{
    require(!source.isEmpty(), Editor::tr("Open a source first"));
    auto* screen
        = editor->windowHandle() ? editor->windowHandle()->screen() : QGuiApplication::primaryScreen();
    require(screen, Editor::tr("Cannot read the preview output"));
    const double ratio
        = editor->windowHandle() ? editor->windowHandle()->devicePixelRatio() : editor->devicePixelRatioF();
    const auto limits = common ? Depth::defaultLimits() : Depth::desktopLimits();
    const int width = common ? Depth::referenceWidth() : qRound(screen->geometry().width() * ratio);
    const int presentation = common ? 0 : qRound(preview->width() * ratio);
    const QString key = QString("%1/%2/%3/%4/%5/%6/%7")
                            .arg(n)
                            .arg(width)
                            .arg(presentation)
                            .arg(limits.sunk)
                            .arg(limits.popped)
                            .arg(depth->value())
                            .arg(flat);
    if (!metadata.contains(key)) {
        QTemporaryDir output;
        require(output.isValid(), Editor::tr("Cannot create model render files."));
        QProcess process;
        QString executable = QCoreApplication::applicationDirPath() + "/studio-model-renderer";
        const auto override = qEnvironmentVariable("STUDIO_MODEL_RENDERER");
        if (!override.isEmpty())
            executable = override;
        process.start(executable,
            { source, output.path(), QString::number(n), QString::number(depth->value() / 100, 'g', 17),
                QString::number(limits.sunk), QString::number(limits.popped), QString::number(width),
                QString::number(presentation), flat ? "1" : "0", "0" });
        require(process.waitForStarted(),
            Editor::tr("Cannot start the model renderer. Install the model helper and its dependencies."));
        if (!process.waitForFinished(60000)) {
            process.kill();
            process.waitForFinished();
            throw std::runtime_error(Editor::tr("The model renderer did not finish.").toStdString());
        }
        require(process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0,
            Editor::tr("Cannot render model: %1")
                .arg(QString::fromUtf8(process.readAllStandardError()).trimmed()));
        QJsonParseError error;
        auto result = QJsonDocument::fromJson(process.readAllStandardOutput(), &error).object();
        require(error.error == QJsonParseError::NoError && !result.isEmpty(),
            Editor::tr("The model renderer returned invalid data."));
        QImage a(output.path() + "/left.png"), b(output.path() + "/right.png");
        require(a.size() == QSize(n, n) && b.size() == a.size(),
            Editor::tr("The model renderer returned invalid data."));
        metadata[key] = result;
        images[key] = { a, b };
    }
    if (left)
        *left = images[key].first;
    if (right)
        *right = images[key].second;
    return metadata[key];
}
void ModelPage::open(const QString& path)
{
    const auto canonical = QFileInfo(path).canonicalFilePath();
    require(!canonical.isEmpty()
            && (canonical.endsWith(".gltf", Qt::CaseInsensitive)
                || canonical.endsWith(".glb", Qt::CaseInsensitive)),
        Editor::tr("Choose a readable glTF (.gltf or .glb) model."));
    const auto previous = source;
    source = canonical;
    metadata.clear();
    images.clear();
    try {
        render(editor->size->value(), false, !editor->stereo->isChecked());
    } catch (...) {
        source = previous;
        metadata.clear();
        images.clear();
        throw;
    }
    committedDepth = depth->value();
    editor->history->clear();
    editor->setWindowTitle(QFileInfo(source).completeBaseName() + "[*]");
    sourceLabel->setText(Editor::tr("Read only model: %1").arg(source));
    editor->membersDirty = true;
    editor->setWindowModified(true);
    refresh();
}
void ModelPage::refresh()
{
    if (source.isEmpty())
        return;
    QImage a, b;
    const auto live = render(editor->size->value(), false, !editor->stereo->isChecked(), &a, &b);
    preview->setViews(a, b, editor->stereo->isChecked());
    QStringList rows;
    const auto box = live["bounds"].toArray();
    double bounds[6];
    for (int i = 0; i < 6; ++i)
        bounds[i] = box[i].toDouble();
    auto* screen
        = editor->windowHandle() ? editor->windowHandle()->screen() : QGuiApplication::primaryScreen();
    const double ratio
        = editor->windowHandle() ? editor->windowHandle()->devicePixelRatio() : editor->devicePixelRatioF();
    const int output = qRound(screen->geometry().width() * ratio),
              presentation = qRound(preview->width() * ratio);
    for (int n : sizes(editor)) {
        const auto common = ModelCamera::fit(
            bounds, n, depth->value() / 100, Depth::defaultLimits(), Depth::referenceWidth(), 0, false)
                                .json();
        const auto personal = ModelCamera::fit(bounds, n, depth->value() / 100, Depth::desktopLimits(),
            output, presentation, !editor->stereo->isChecked())
                                  .json();
        auto values = [](const QJsonObject& o) {
            return QString("%1, %2").arg(o["far"].toDouble(), 0, 'f', 2).arg(o["near"].toDouble(), 0, 'f', 2);
        };
        QString text
            = Editor::tr("%1 px: far / near %2; preview %3").arg(n).arg(values(common), values(personal));
        const QString reason = common["reason"].toString().isEmpty() ? personal["reason"].toString()
                                                                     : common["reason"].toString();
        if (reason == "zero-limit")
            text += "; " + Editor::tr("the desktop's limit is zero");
        if (reason == "no-room")
            text += "; " + Editor::tr("no room in the drawing at this size");
        rows << text;
    }
    summary->setText(rows.join('\n'));
}
void ModelPage::exportPairs(const QString& destination)
{
    require(!QFileInfo::exists(destination),
        Editor::tr("The project destination already exists; choose a new folder"));
    const auto parent = QFileInfo(destination).absolutePath();
    QTemporaryDir stage(parent + "/.model-export-XXXXXX");
    require(stage.isValid(), Editor::tr("Cannot create model render files."));
    QJsonArray records;
    for (int n : sizes(editor)) {
        QImage a, b;
        auto record = render(n, true, false, &a, &b);
        savePns(stage.path() + QString("/%1.pns").arg(n), a, b);
        record["size"] = n;
        records << record;
    }
    saveBytes(stage.path() + "/cameras.json", QJsonDocument(records).toJson());
    require(QDir().rename(stage.path(), destination), Editor::tr("Cannot commit the project folder"));
    stage.setAutoRemove(false);
}
static QByteArray pairSvg(const QImage& a, const QImage& b)
{
    auto encoded = [](const QImage& im) {
        QByteArray data;
        QBuffer buffer(&data);
        buffer.open(QIODevice::WriteOnly);
        require(im.save(&buffer, "PNG"), Editor::tr("Cannot save the copied theme index"));
        return data.toBase64();
    };
    const int n = a.width();
    return QString("<svg xmlns=\"http://www.w3.org/2000/svg\" "
                   "xmlns:svgstereo=\"https://github.com/Sparky-OS/svgstereo\" "
                   "svgstereo:layout=\"sideBySideLeftFirst\" width=\"%1\" height=\"%2\" viewBox=\"0 0 %1 "
                   "%2\"><image width=\"%2\" height=\"%2\" href=\"data:image/png;base64,%3\"/><image "
                   "x=\"%2\" width=\"%2\" height=\"%2\" href=\"data:image/png;base64,%4\"/></svg>")
        .arg(2 * n)
        .arg(n)
        .arg(QString::fromLatin1(encoded(a)), QString::fromLatin1(encoded(b)))
        .toUtf8();
}
void ModelPage::saveProject(const QString& destination)
{
    editor->ensurePeerClosed();
    require(!QFileInfo::exists(destination),
        Editor::tr("The project destination already exists; choose a new folder"));
    const QString parent = QFileInfo(QFileInfo(destination).absolutePath()).canonicalFilePath();
    require(!parent.isEmpty(), Editor::tr("Cannot create model render files."));
    require(editor->themeRoot.isEmpty()
            || (parent != editor->themeRoot && !parent.startsWith(editor->themeRoot + "/")),
        Editor::tr("Save the copy outside its source theme"));
    QTemporaryDir stage(parent + "/.model-project-XXXXXX");
    require(stage.isValid(), Editor::tr("Cannot create model render files."));
    namespace fs = std::filesystem;
    if (!editor->themeRoot.isEmpty())
        fs::copy(editor->themeRoot.toStdString(), (stage.path() + "/icons").toStdString(),
            fs::copy_options::recursive | fs::copy_options::copy_symlinks);
    else
        QDir().mkpath(stage.path() + "/icons");
    const QString indexPath = stage.path() + "/icons/index.theme";
    require(!QFileInfo(indexPath).isSymLink(), Editor::tr("A project index must be a regular file"));
    if (QFile::exists(indexPath))
        QFile::setPermissions(indexPath, QFile::permissions(indexPath) | QFileDevice::WriteOwner);
    KConfig index(indexPath, KConfig::SimpleConfig);
    KConfigGroup theme(&index, "Icon Theme");
    if (editor->themeRoot.isEmpty()) {
        theme.writeEntry("Name", QFileInfo(destination).fileName());
        theme.writeEntry("Inherits", QStringList { "hicolor" });
    }
    QString name = QFileInfo(source).completeBaseName();
    QString root = "stereo-models";
    for (int i = 2; QFileInfo::exists(stage.path() + "/icons/" + root); ++i)
        root = QString("stereo-models-%1").arg(i);
    QStringList stereoDirs, ordinaryDirs;
    QJsonArray cameras;
    for (int n : sizes(editor)) {
        QImage a, b;
        auto meta = render(n, true, false, &a, &b);
        meta["size"] = n;
        cameras << meta;
        const QString dir = root + QString("/%1x%1/apps").arg(n), ordinary = QString("%1x%1/apps").arg(n);
        QDir().mkpath(stage.path() + "/icons/" + dir);
        QDir().mkpath(stage.path() + "/icons/" + ordinary);
        QDir().mkpath(stage.path() + "/pairs");
        savePns(stage.path() + QString("/pairs/%1.pns").arg(n), a, b);
        saveBytes(stage.path() + "/icons/" + dir + "/" + name + ".svg", pairSvg(a, b));
        require(a.save(stage.path() + "/icons/" + ordinary + "/" + name + ".png"),
            Editor::tr("Cannot save the copied theme index"));
        stereoDirs << dir;
        ordinaryDirs << ordinary;
        KConfigGroup group(&index, dir);
        group.writeEntry("X-StereoSize", n);
        group.writeEntry("X-StereoLayout", "sbs-left-first");
        group.writeEntry("Type", "Fixed");
        group.writeEntry("Context", "Applications");
        KConfigGroup plain(&index, ordinary);
        plain.writeEntry("Size", n);
        plain.writeEntry("Type", "Fixed");
        plain.writeEntry("Context", "Applications");
    }
    theme.writeEntry(
        "X-StereoDirectories", stereoDirs + theme.readEntry("X-StereoDirectories", QStringList()));
    theme.writeEntry("Directories", ordinaryDirs + theme.readEntry("Directories", QStringList()));
    require(index.sync(), Editor::tr("Cannot save the copied theme index"));
    const auto modelCopy = copyModelAssets(source, stage.path());
    QJsonObject groups;
    for (auto i = editor->drawing.places.cbegin(); i != editor->drawing.places.cend(); ++i)
        groups[i.key()] = i.value();
    QJsonObject project { { "version", 1 },
        { "icon", editor->iconPath.isEmpty() ? QString("256x256/apps/%1.png").arg(name) : editor->iconPath },
        { "groups", groups },
        { "model",
            QJsonObject { { "source", modelCopy }, { "depth", depth->value() / 100 },
                { "sha256",
                    QString::fromLatin1(
                        QCryptographicHash::hash(bytes(source), QCryptographicHash::Sha256).toHex()) } } } };
    editor->saveParts(stage.path(), project);
    saveBytes(stage.path() + "/model-cameras.json", QJsonDocument(cameras).toJson());
    saveBytes(stage.path() + "/project.json", QJsonDocument(project).toJson());
    require(QDir().rename(stage.path(), destination), Editor::tr("Cannot commit the project folder"));
    stage.setAutoRemove(false);
    editor->membersDirty = false;
    editor->history->setClean();
    editor->setWindowModified(false);
    editor->setWindowTitle(QFileInfo(destination).fileName() + "[*]");
    sourceLabel->setText(Editor::tr("Saved project copy: %1").arg(destination));
}
void ModelPage::loadProject(const QString& path, const QJsonObject& project)
{
    const auto model = project["model"].toObject();
    const QString rel = model["source"].toString();
    const auto canonical = QFileInfo(path + "/" + rel).canonicalFilePath();
    require(canonical.startsWith(QFileInfo(path).canonicalFilePath() + "/models/"),
        Editor::tr("Invalid or unsupported theme project"));
    require(model["depth"].isDouble() && std::abs(model["depth"].toDouble()) <= 1,
        Editor::tr("Invalid group or place"));
    const auto icon = project["icon"].toString();
    if (icon.endsWith(".svg") || icon.endsWith(".svgz")) {
        editor->load(path + "/icons", path + "/icons/" + icon);
        editor->applyPlaces(project["groups"].toObject());
    } else {
        editor->themeRoot = path + "/icons";
        editor->iconPath = icon;
    }
    {
        QSignalBlocker block(depth);
        depth->setValue(model["depth"].toDouble() * 100);
    }
    open(canonical);
    editor->loadParts(path, project);
    editor->pages->setCurrentWidget(this);
    editor->membersDirty = false;
    editor->setWindowModified(false);
    editor->setWindowTitle(QFileInfo(path).fileName() + "[*]");
}
QString ModelPage::state() const
{
    const auto pos = preview->mapToGlobal(QPoint());
    auto* self = const_cast<ModelPage*>(this);
    auto state = source.isEmpty() ? QJsonObject()
                                  : self->render(editor->size->value(), false, !editor->stereo->isChecked());
    state["source"] = source;
    state["depth"] = depth->value() / 100;
    state["previewRect"] = QJsonArray { pos.x(), pos.y(), preview->width(), preview->height() };
    const auto control = depth->mapToGlobal(QPoint());
    state["depthRect"] = QJsonArray { control.x(), control.y(), depth->width(), depth->height() };
    state["summary"] = summary->text();
    return QString::fromUtf8(QJsonDocument(state).toJson(QJsonDocument::Compact));
}
