// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include "page.h"
#include <QApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QPainter>
#include <QSvgRenderer>
#include <QTemporaryDir>
#include <filesystem>
#include <iostream>
static void require(bool ok, const char* why)
{
    if (!ok)
        throw std::runtime_error(why);
}
static QByteArray read(const QString& path)
{
    QFile f(path);
    require(f.open(QIODevice::ReadOnly), "Cannot read proof file");
    return f.readAll();
}
int main(int argc, char** argv)
{
    QApplication app(argc, argv);
    if (argc != 3)
        return 2;
    try {
        const QString model = argv[1], base = argv[2];
        QDir().mkpath(base);
        QTemporaryDir run(base + "/run-XXXXXX");
        require(run.isValid(), "Cannot create proof output");
        const QString out = run.path();
        const auto original = read(model);
        Editor editor;
        editor.loadProject(QFileInfo(model).absolutePath() + "/../project");
        const QString copiedTheme = out + "/source-theme";
        std::filesystem::copy(editor.themeRoot.toStdString(), copiedTheme.toStdString(),
            std::filesystem::copy_options::recursive);
        editor.themeRoot = copiedTheme;
        QDir().mkpath(copiedTheme + "/16x16/apps");
        const QString sentinel = out + "/outside.png";
        saveBytes(sentinel, "original outside file");
        std::filesystem::create_symlink(sentinel.toStdString(),
            (copiedTheme + "/16x16/apps/" + QFileInfo(model).completeBaseName() + ".png").toStdString());
        require(editor.openModelFile(model).isEmpty(), "Open model failed");
        require(editor.setModelDepth(-.25).isEmpty(), "Depth failed");
        editor.history->undo();
        require(editor.modelPage->depth->value() == 0, "Model depth undo failed");
        editor.history->redo();
        require(editor.modelPage->depth->value() == -25, "Model depth redo failed");
        require(editor.exportModelPairs(out + "/pairs").isEmpty(), "Export failed");
        require(editor.saveCurrentProject(out + "/project").isEmpty(), "Project save failed");
        require(read(sentinel) == "original outside file", "Model save wrote through a copied theme alias");
        auto project = QJsonDocument::fromJson(read(out + "/project/project.json")).object();
        require(read(out + "/project/" + project["model"].toObject()["source"].toString()) == original,
            "Model copy is changed");
        require(read(model) == original, "Source model changed");
        Editor reopened;
        reopened.loadProject(out + "/project");
        require(reopened.modelPage->depth->value() == -25, "Project lost model placement");
        require(reopened.exportModelPairs(out + "/reopened").isEmpty(), "Reopened export failed");
        for (int n : { 8, 16, 22, 24, 32, 48, 64, 128, 256 }) {
            require(
                read(out + QString("/pairs/%1.pns").arg(n)) == read(out + QString("/reopened/%1.pns").arg(n)),
                "Round trip changed pair");
            const QString svg = out
                + QString("/project/icons/stereo-models/%1x%1/apps/%2.svg")
                      .arg(n)
                      .arg(QFileInfo(model).completeBaseName());
            QSvgRenderer renderer(svg);
            require(renderer.isValid(), "Theme pair SVG invalid");
            QImage actual(2 * n, n, QImage::Format_ARGB32_Premultiplied);
            actual.fill(Qt::transparent);
            QPainter p(&actual);
            renderer.render(&p);
            p.end();
            QImage a, b;
            editor.modelPage->render(n, true, false, &a, &b);
            for (int y = 0; y < n; ++y)
                for (int x = 0; x < 2 * n; ++x)
                    require(actual.pixelColor(x, y) == (x < n ? a : b).pixelColor(x % n, y),
                        "Embedded theme views differ from native views");
        }
        QImage a, b;
        editor.stereo->setChecked(false);
        editor.modelPage->render(64, false, true, &a, &b);
        require(a == b, "Flat model control differs");
        const auto kept = editor.modelPage->source;
        saveBytes(out + "/bad.gltf", "not JSON");
        require(!editor.openModelFile(out + "/bad.gltf").isEmpty(), "Invalid JSON accepted");
        require(editor.modelPage->source == kept, "Invalid JSON lost the prior model");

        if (model.endsWith(".glb")) {
            auto damaged = original;
            damaged[8] = damaged[8] ^ 1;
            saveBytes(out + "/bad.glb", damaged);
            require(!editor.openModelFile(out + "/bad.glb").isEmpty(), "Invalid GLB container accepted");
            require(editor.modelPage->source == kept, "Invalid container lost prior model");
        }
        require(!editor.openModelFile(out + "/missing.gltf").isEmpty(), "Missing model hidden");
        require(editor.modelPage->source == kept, "Rejected model lost prior source");
        QTemporaryDir changed(out + "/changed-XXXXXX");
        require(changed.isValid(), "Cannot create changed-model fixture");
        std::filesystem::copy(QFileInfo(model).absolutePath().toStdString(), changed.path().toStdString(),
            std::filesystem::copy_options::recursive);
        const QString changedModel = changed.path() + "/" + QFileInfo(model).fileName();
        require(editor.openModelFile(changedModel).isEmpty(), "Cannot load independent model fixture");
        auto different = original;
        if (model.endsWith(".gltf"))
            different += "\n";
        else
            different[different.size() - 1] = different[different.size() - 1] ^ 1;
        saveBytes(changedModel, different);
        require(!editor.saveCurrentProject(out + "/changed-project").isEmpty(),
            "Changed model silently saved against cached views");
        require(!QFileInfo::exists(out + "/changed-project"), "Failed model save left a project behind");
        saveBytes(changedModel, original);
        qputenv("STUDIO_MODEL_RENDERER", "/missing/model-helper");
        editor.modelPage->metadata.clear();
        editor.modelPage->images.clear();
        bool refused = false;
        try {
            editor.modelPage->render(256, false, false);
        } catch (const std::exception& e) {
            refused = QString::fromUtf8(e.what()).contains("Cannot start");
        }
        qunsetenv("STUDIO_MODEL_RENDERER");
        require(refused, "Missing renderer hidden");
        std::cout << "PASS: glTF load/depth, nine native marked exports, immutable source, project round "
                     "trip, embedded SVG exact, flat control, missing source/helper said\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
