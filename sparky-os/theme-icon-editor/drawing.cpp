// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include "desktop-depth.h"
#include <KConfig>
#include <KConfigGroup>
#include <QBuffer>
#include <QFile>
#include <QPainter>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSvgRenderer>
#include <QtEndian>
#include <stdexcept>
#include <functional>

static void check(bool ok, const QString &reason)
{
    if (!ok) throw std::runtime_error(reason.toStdString());
}

void Drawing::open(const QString &path, bool square)
{
    QFile file(path);
    check(file.open(QIODevice::ReadOnly), file.errorString());
    auto bytes = file.readAll();
    if (bytes.startsWith("\x1f\x8b")) {
        QProcess gzip;
        gzip.start("gzip", {"-dc", "--", path});
        if (!gzip.waitForFinished(10000)) { gzip.kill(); gzip.waitForFinished(); check(false, Drawing::tr("SVGZ decompression failed or timed out")); }
        bytes = gzip.readAllStandardOutput();
        check(gzip.exitCode() == 0 && bytes.size() <= 32 * 1024 * 1024, Drawing::tr("Invalid or excessive SVGZ input"));
    }
    QDomDocument next;
    check(bool(next.setContent(bytes)), Drawing::tr("Cannot parse SVG"));
    check(next.elementsByTagName("script").isEmpty(), Drawing::tr("Scripted SVG is not supported"));
    check(next.elementsByTagName("style").isEmpty(), Drawing::tr("Use inline SVG paint attributes; CSS stylesheets are not supported"));
    QSvgRenderer renderer(bytes);
    check(renderer.isValid(), Drawing::tr("SVG renderer rejected the drawing"));
    check(renderer.viewBoxF().width() > 0 && renderer.viewBoxF().height() > 0, Drawing::tr("The SVG has no usable view box"));
    check(!square || qAbs(renderer.viewBoxF().width() - renderer.viewBoxF().height()) < 0.001,
          Drawing::tr("Choose a square, single-view SVG source"));
    QMap<QString, qreal> nextPlaces;
    const auto groups = next.elementsByTagName("g");
    for (int i = 0; i < groups.size(); ++i) {
        const QString id = groups.at(i).toElement().attribute("id");
        if (id.isEmpty()) continue;
        check(!nextPlaces.contains(id), Drawing::tr("Duplicate SVG group id: ") + id);
        nextPlaces[id] = 0;
    }
    check(!nextPlaces.isEmpty(), Drawing::tr("This SVG has no named groups to author"));
    document = next;
    original = bytes;
    places = nextPlaces;
    source = path;
    readLimits();
}

void Drawing::readLimits()
{
    KConfig config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) + "/kwinrc", KConfig::SimpleConfig);
    KConfigGroup group(&config, "StereoDepth");
    const qreal sunk = group.readEntry("SunkLimit", DesktopGeometry::StereoSunkLimit);
    const qreal popped = group.readEntry("PoppedLimit", DesktopGeometry::StereoPoppedLimit);
    check(std::isfinite(sunk) && std::isfinite(popped) && sunk >= 0 && popped >= 0, Drawing::tr("Invalid desktop depth limits"));
    sunkLimit = sunk;
    poppedLimit = popped;
}

int Drawing::height(int width) const
{
    QSvgRenderer renderer(original);
    return qMax(1, qRound(width * renderer.viewBoxF().height() / renderer.viewBoxF().width()));
}

QStringList Drawing::groups() const { return places.keys(); }

int Drawing::disparity(const QString &id, int size) const
{
    check(places.contains(id), Drawing::tr("Invalid group or place"));
    const qreal value = places.value(id);
    const qreal reference = value * (value < 0 ? sunkLimit : poppedLimit);
    return DesktopGeometry::StereoDepth::parallax(reference, size);
}

QString Drawing::groupLabel(const QString &id) const
{
    const auto groups = document.elementsByTagName("g");
    for (int i = 0; i < groups.size(); ++i) {
        const auto group = groups.at(i).toElement();
        if (group.attribute("id") != id) continue;
        const auto label = group.attribute("inkscape:label");
        if (!label.isEmpty()) return label;
        const auto title = group.firstChildElement("title").text();
        if (!title.isEmpty()) return title;
    }
    return id;
}

void Drawing::setPlace(const QString &id, qreal place)
{
    check(places.contains(id) && std::isfinite(place) && place >= -1 && place <= 1, Drawing::tr("Invalid group or place"));
    auto candidate = places;
    candidate[id] = place;
    const auto groups = document.elementsByTagName("g");
    for (int i = 0; i < groups.size(); ++i) {
        auto e = groups.at(i).toElement();
        if (!candidate.value(e.attribute("id"))) continue;
        for (auto p = e.parentNode(); !p.isNull(); p = p.parentNode()) {
            check(!candidate.value(p.toElement().attribute("id")),
                  Drawing::tr("Select disjoint groups for depth; clear the parent or child depth first"));
        }
    }
    places = candidate;
}

QByteArray Drawing::viewSvg(int size, bool right, QString only) const
{
    auto view = document.cloneNode(true).toDocument();
    QSvgRenderer sourceRenderer(original);
    const qreal unitsPerPixel = sourceRenderer.viewBoxF().width() / size;
    if (!only.isEmpty()) {
        std::function<void(QDomElement, bool)> isolate = [&](QDomElement e, bool inside) {
            if (QStringList{"defs", "metadata", "title", "desc", "style"}.contains(e.tagName())) return;
            inside |= e.attribute("id") == only;
            bool contains = inside;
            auto descendants = e.elementsByTagName("g");
            for (int i = 0; i < descendants.size(); ++i)
                contains |= descendants.at(i).toElement().attribute("id") == only;
            if (!contains) { e.setAttribute("display", "none"); return; }
            for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) isolate(c, inside);
        };
        isolate(view.documentElement(), false);
    }
    auto groups = view.elementsByTagName("g");
    QList<QDomElement> chosen;
    for (int i = 0; i < groups.size(); ++i) chosen << groups.at(i).toElement();
    for (auto e : chosen) {
        const QString id = e.attribute("id");
        const qreal place = places.value(id);
        if (!place) continue;
        using namespace DesktopGeometry;
        const int shift = StereoDepth::eyeShift(disparity(id, size), right ? StereoEye::Right : StereoEye::Left);
        bool invertible = false;
        auto inverse = sourceRenderer.transformForElement(id).inverted(&invertible);
        check(invertible, Drawing::tr("Singular parent transform for ") + id);
        auto delta = inverse.map(QPointF(shift * unitsPerPixel, 0)) - inverse.map(QPointF());
        e.setAttribute("transform", QString("translate(%1 %2) ").arg(delta.x(), 0, 'g', 17).arg(delta.y(), 0, 'g', 17) + e.attribute("transform"));
    }
    auto root = view.documentElement();
    const QRectF box = sourceRenderer.viewBoxF();
    root.setAttribute("viewBox", QString("%1 %2 %3 %4").arg(box.x(), 0, 'g', 17).arg(box.y(), 0, 'g', 17).arg(box.width(), 0, 'g', 17).arg(box.height(), 0, 'g', 17));
    root.setAttribute("width", size);
    root.setAttribute("height", height(size));
    return view.toByteArray();
}

QImage Drawing::eye(int size, bool right, QString only) const
{
    QSvgRenderer renderer(viewSvg(size, right, only));
    check(renderer.isValid(), Drawing::tr("Cannot render the authored view"));
    QImage image(size, height(size), QImage::Format_ARGB32_Premultiplied);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    renderer.render(&painter);
    return image;
}

QByteArray Drawing::pairSvg(int size) const
{
    // Flatten each source root to a group because Qt's SVG Tiny reader rejects nested SVG roots.
    const auto left = viewSvg(size, false);
    const auto right = viewSvg(size, true);
    QDomDocument pair;
    auto root = pair.createElement("svg");
    root.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    root.setAttribute("xmlns:svgstereo", "https://github.com/Sparky-OS/svgstereo");
    root.setAttribute("svgstereo:layout", "sideBySideLeftFirst");
    root.setAttribute("viewBox", QString("0 0 %1 %2").arg(size * 2).arg(height(size)));
    root.setAttribute("width", size * 2);
    root.setAttribute("height", height(size));
    pair.appendChild(root);
    auto defs = pair.createElement("defs");
    auto clip = pair.createElement("clipPath");
    clip.setAttribute("id", "eye-bound");
    auto clipRect = pair.createElement("rect");
    clipRect.setAttribute("width", size);
    clipRect.setAttribute("height", height(size));
    clip.appendChild(clipRect);
    defs.appendChild(clip);
    root.appendChild(defs);
    QSvgRenderer sourceRenderer(original);
    const auto box = sourceRenderer.viewBoxF();
    for (int i = 0; i < 2; ++i) {
        QDomDocument view;
        check(bool(view.setContent(i ? right : left)), Drawing::tr("Cannot encode pair"));
        const QString prefix = i ? "right_" : "left_";
        QMap<QString, QString> ids;
        QList<QDomElement> elements;
        std::function<void(QDomElement)> collect = [&](QDomElement e) {
            elements << e;
            for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) collect(c);
        };
        collect(view.documentElement());
        for (int j = 0; j < elements.size(); ++j) {
            auto e = elements.at(j);
            if (e.hasAttribute("id")) ids[e.attribute("id")] = prefix + e.attribute("id");
        }
        for (int j = 0; j < elements.size(); ++j) {
            auto e = elements.at(j);
            auto attributes = e.attributes();
            for (int k = 0; k < attributes.size(); ++k) {
                auto attribute = attributes.item(k).toAttr();
                QString value = attribute.value();
                for (auto id = ids.cbegin(); id != ids.cend(); ++id) {
                    value.replace("url(#" + id.key() + ")", "url(#" + id.value() + ")");
                    if ((attribute.name() == "href" || attribute.name() == "xlink:href") && value == "#" + id.key()) value = "#" + id.value();
                }
                if (attribute.name() == "id") value = ids.value(value, value);
                e.setAttribute(attribute.name(), value);
            }
        }
        auto imported = pair.importNode(view.documentElement(), true).toElement();
        imported.setTagName("g");
        imported.removeAttribute("width");
        imported.removeAttribute("height");
        imported.removeAttribute("viewBox");
        imported.setAttribute("transform", QString("scale(%1 %2) translate(%3 %4)")
            .arg(size / box.width(), 0, 'g', 17).arg(height(size) / box.height(), 0, 'g', 17)
            .arg(-box.x(), 0, 'g', 17).arg(-box.y(), 0, 'g', 17));
        auto eye = pair.createElement("g");
        eye.setAttribute("transform", QString("translate(%1 0)").arg(i * size));
        eye.setAttribute("clip-path", "url(#eye-bound)");
        eye.appendChild(imported);
        root.appendChild(eye);
    }
    return pair.toByteArray();
}

void saveBytes(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    check(file.open(QIODevice::WriteOnly), file.errorString());
    check(file.write(bytes) == bytes.size(), file.errorString());
    check(file.commit(), file.errorString());
}

void savePns(const QString &path, const QImage &left, const QImage &right)
{
    check(left.size() == right.size(), Drawing::tr("The views have different dimensions"));
    const int padding = (8 - left.width() % 8) % 8;
    QImage pair(2 * left.width() + padding, left.height(), left.format());
    pair.fill(Qt::transparent);
    { QPainter p(&pair); p.setCompositionMode(QPainter::CompositionMode_Source); p.drawImage(0, 0, left); p.drawImage(left.width() + padding, 0, right); }
    QByteArray png;
    QBuffer buffer(&png);
    check(buffer.open(QIODevice::WriteOnly) && pair.save(&buffer, "PNG"), Drawing::tr("Cannot encode PNG"));
    QByteArray chunk("sTER", 4);
    chunk.append(char(1));
    quint32 crcValue = 0xffffffff;
    for (unsigned char byte : chunk) {
        crcValue ^= byte;
        for (int bit = 0; bit < 8; ++bit) crcValue = (crcValue >> 1) ^ ((crcValue & 1) ? 0xedb88320 : 0);
    }
    const quint32 crc = qToBigEndian(crcValue ^ 0xffffffff);
    const quint32 length = qToBigEndian(quint32(1));
    QByteArray encoded(reinterpret_cast<const char *>(&length), 4);
    encoded += chunk;
    encoded.append(reinterpret_cast<const char *>(&crc), 4);
    png.insert(33, encoded);
    saveBytes(path, png);
}
