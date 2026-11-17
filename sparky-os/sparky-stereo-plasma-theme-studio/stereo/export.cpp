// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include <QSvgRenderer>
#include <QPainter>
#include <QBuffer>
#include <QtEndian>
#include <functional>
#include <stdexcept>
static void check(bool ok, const QString &why) { if (!ok) throw std::runtime_error(why.toStdString()); }
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
