// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include "depth-interface.h"
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
#include <QSet>
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
    // Loose painted elements alongside groups must also be selectable authoring parts.
    // Neutral wrappers exist only in the working DOM; original bytes and element IDs stay intact.
    QSet<QString> usedIds;
    std::function<void(QDomElement)> collectIds = [&](QDomElement e) {
        if (e.hasAttribute("id")) usedIds.insert(e.attribute("id"));
        for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) collectIds(c);
    };
    collectIds(next.documentElement());
    int anonymous = 0;
    std::function<void(QDomElement)> groupLoose = [&](QDomElement parent) {
        bool mixed = parent == next.documentElement();
        for (auto c = parent.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) mixed |= c.tagName() == "g";
        QList<QDomElement> children;
        for (auto c = parent.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) children << c;
        for (auto e : children) {
            if (e.tagName() == "g") { groupLoose(e); continue; }
            if (!mixed || !QStringList{"path","rect","circle","ellipse","polygon","polyline","line","text","image","use"}.contains(e.tagName())) continue;
            QString sourceId = e.attribute("id");
            if (sourceId.isEmpty()) sourceId = e.tagName() + QString::number(++anonymous);
            QString id = "studio-part-" + sourceId;
            while (usedIds.contains(id)) id += "-part";
            usedIds.insert(id);
            auto wrapper = next.createElement("g"); wrapper.setAttribute("id", id); wrapper.setAttribute("data-source-id", sourceId);
            auto title = e.firstChildElement("title");
            if (!title.isNull()) wrapper.appendChild(title.cloneNode(true));
            const auto attributes = e.attributes();
            for (int a = 0; a < attributes.size(); ++a) {
                const auto attribute = attributes.item(a).toAttr();
                if (attribute.name().section(':', -1) == "label") wrapper.setAttribute(attribute.name(), attribute.value());
            }
            parent.replaceChild(wrapper, e); wrapper.appendChild(e);
        }
    };
    groupLoose(next.documentElement());
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
    const auto limits = Depth::desktopLimits();
    const qreal sunk = limits.sunk, popped = limits.popped;
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
    return Depth::authoredDisparity(value, {sunkLimit, poppedLimit}, size);
}

QString Drawing::groupLabel(const QString &id) const
{
    const auto groups = document.elementsByTagName("g");
    for (int i = 0; i < groups.size(); ++i) {
        const auto group = groups.at(i).toElement();
        if (group.attribute("id") != id) continue;
        const auto attributes = group.attributes();
        for (int a = 0; a < attributes.size(); ++a) {
            const auto attribute = attributes.item(a).toAttr();
            if (attribute.name().section(':', -1) == "label" && !attribute.value().isEmpty()) return attribute.value();
        }
        const auto title = group.firstChildElement("title").text();
        if (!title.isEmpty()) return title;
    }
    const auto all = document.elementsByTagName("g");
    for (int i=0;i<all.size();++i) { auto e=all.at(i).toElement(); if(e.attribute("id")==id && e.hasAttribute("data-source-id")) return e.attribute("data-source-id"); }
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
    QSvgRenderer sourceRenderer(document.toByteArray());
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
        const int shift = Depth::eyeShift(disparity(id, size), right);
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

void saveBytes(const QString &path, const QByteArray &bytes)
{
    QSaveFile file(path);
    check(file.open(QIODevice::WriteOnly), file.errorString());
    check(file.write(bytes) == bytes.size(), file.errorString());
    check(file.commit(), file.errorString());
}


QStringList Drawing::hitGroups(const QPoint &pixel, int width) const
{
    QStringList hits;
    const auto nodes = document.elementsByTagName("g");
    // Reverse document order is the SVG paint stack. Alpha tests share the rendered view geometry.
    for (int i = nodes.size() - 1; i >= 0; --i) {
        const auto id = nodes.at(i).toElement().attribute("id");
        if (!places.contains(id)) continue;
        const auto image = eye(width, false, id);
        if (image.rect().contains(pixel) && qAlpha(image.pixel(pixel)) > 0) hits << id;
    }
    return hits;
}
