// SPDX-License-Identifier: GPL-2.0-or-later
#include "assets.h"
#include "editor.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QUrl>
#include <QtEndian>
#include <stdexcept>
static void require(bool ok, const QString& why)
{
    if (!ok)
        throw std::runtime_error(why.toStdString());
}
static QByteArray read(const QString& path)
{
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), Editor::tr("Cannot read model: %1").arg(path));
    return file.readAll();
}
QString copyModelAssets(const QString& source, const QString& project)
{
    auto data = read(source);
    if (source.endsWith(".glb", Qt::CaseInsensitive)) {
        require(data.size() >= 20 && data.left(4) == "glTF", Editor::tr("Cannot read model: %1").arg(source));
        const auto size = qFromLittleEndian<quint32>(data.constData() + 12);
        require(size <= quint32(data.size() - 20) && data.mid(16, 4) == "JSON",
            Editor::tr("Cannot read model: %1").arg(source));
        data = data.mid(20, size);
    }
    QJsonParseError error;
    const auto gltf = QJsonDocument::fromJson(data, &error).object();
    require(error.error == QJsonParseError::NoError && !gltf.isEmpty(),
        Editor::tr("Cannot read model: %1").arg(source));
    const QString base = QFileInfo(source).absolutePath();
    QStringList files { source };
    for (const QString& kind : { QString("buffers"), QString("images") }) {
        for (auto value : gltf[kind].toArray()) {
            const QString uri = value.toObject()["uri"].toString();
            if (uri.isEmpty() || uri.startsWith("data:"))
                continue;
            const QUrl url(uri);
            require(url.isRelative() && !QDir::isAbsolutePath(url.path()) && !url.hasQuery()
                    && !url.hasFragment(),
                Editor::tr("Model assets must be local files beside the glTF model."));
            files << QDir::cleanPath(base + "/" + url.path());
        }
    }
    QString common = base;
    auto contains = [](const QString& dir, const QString& path) {
        return path.startsWith(dir == "/" ? dir : dir + "/");
    };
    for (const auto& file : files) {
        while (!contains(common, file))
            common = QFileInfo(common).absolutePath();
    }
    files.removeDuplicates();
    for (const auto& file : files) {
        const auto relative = QDir(common).relativeFilePath(file);
        const QString target = project + "/models/" + relative;
        QDir().mkpath(QFileInfo(target).absolutePath());
        saveBytes(target, read(file));
    }
    return "models/" + QDir(common).relativeFilePath(source);
}
