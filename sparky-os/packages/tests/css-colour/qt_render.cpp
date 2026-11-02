// ORDER 348 measurement: renders the corpus with Qt SVG's QSvgRenderer into deep QImage targets and prints the raw
// stored values (no QColor round trip on readback) as JSON lines, with every message Qt SVG logged for that render.
// Usage: qt_render CORPUS_DIR > results.jsonl     (QT_QPA_PLATFORM=offscreen)
#include <QCoreApplication>
#include <QColorSpace>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPainter>
#include <QPalette>
#include <QSet>
#include <QSvgRenderer>
#include <QFloat16>
#include <cstdio>

static QStringList g_messages;

static void handler(QtMsgType, const QMessageLogContext &ctx, const QString &msg)
{
    g_messages << (QString::fromLatin1(ctx.category ? ctx.category : "default") + QLatin1String(": ") + msg);
}

static QImage::Format formatOf(const QString &name)
{
    if (name == QLatin1String("RGBA64"))
        return QImage::Format_RGBA64;
    if (name == QLatin1String("RGBA16FPx4"))
        return QImage::Format_RGBA16FPx4;
    if (name == QLatin1String("RGBA32FPx4"))
        return QImage::Format_RGBA32FPx4;
    return QImage::Format_ARGB32;
}

static QColorSpace spaceOf(const QString &name)
{
    if (name == QLatin1String("DisplayP3"))
        return QColorSpace(QColorSpace::DisplayP3);
    if (name == QLatin1String("Bt2020"))
        return QColorSpace(QColorSpace::Bt2020);
    if (name == QLatin1String("SRgbLinear"))
        return QColorSpace(QColorSpace::SRgbLinear);
    if (name == QLatin1String("Bt2100Pq"))
        return QColorSpace(QColorSpace::Bt2100Pq);
    return QColorSpace();
}

// the stored channel values at (x, y), as floats, exactly as the format holds them
static QJsonArray rawPixel(const QImage &img, int x, int y)
{
    QJsonArray a;
    const uchar *line = img.constScanLine(y);
    switch (img.format()) {
    case QImage::Format_RGBA64: {
        const quint16 *p = reinterpret_cast<const quint16 *>(line) + 4 * x;
        for (int i = 0; i < 4; ++i)
            a.append(p[i] / 65535.0);
        break;
    }
    case QImage::Format_RGBA16FPx4: {
        const qfloat16 *p = reinterpret_cast<const qfloat16 *>(line) + 4 * x;
        for (int i = 0; i < 4; ++i)
            a.append(double(float(p[i])));
        break;
    }
    case QImage::Format_RGBA32FPx4: {
        const float *p = reinterpret_cast<const float *>(line) + 4 * x;
        for (int i = 0; i < 4; ++i)
            a.append(double(p[i]));
        break;
    }
    default: {
        const QRgb v = reinterpret_cast<const QRgb *>(line)[x];
        a.append(qRed(v) / 255.0);
        a.append(qGreen(v) / 255.0);
        a.append(qBlue(v) / 255.0);
        a.append(qAlpha(v) / 255.0);
    }
    }
    return a;
}

static QImage render(const QString &path, int w, int h, const QString &fmt, const QString &cs)
{
    QImage img(w, h, formatOf(fmt));
    const QColorSpace space = spaceOf(cs);
    if (space.isValid())
        img.setColorSpace(space);
    img.fill(Qt::transparent);
    QSvgRenderer r(path);
    QPainter p(&img);
    r.render(&p);
    p.end();
    return img;
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    const QString dir = QString::fromLocal8Bit(argv[1]);
    QFile f(dir + QLatin1String("/cases.json"));
    f.open(QIODevice::ReadOnly);
    const QJsonObject doc = QJsonDocument::fromJson(f.readAll()).object();
    const int W = doc.value(QLatin1String("width")).toInt();
    const int H = doc.value(QLatin1String("height")).toInt();
    qInstallMessageHandler(handler);
    {
        // a palette whose text colours are not black, so that a system colour drawn as black shows
        QPalette pal = QGuiApplication::palette();
        pal.setColor(QPalette::Text, QColor(0x2b, 0x5a, 0x87));
        pal.setColor(QPalette::WindowText, QColor(0x2b, 0x5a, 0x87));
        pal.setColor(QPalette::Base, QColor(0xf4, 0xf1, 0xe8));
        pal.setColor(QPalette::Window, QColor(0xf4, 0xf1, 0xe8));
        QGuiApplication::setPalette(pal);
    }
    {
        // the palette system colours resolve from (CSS Color 4 section 6.2): printed once for the comparison
        const QPalette pal = QGuiApplication::palette();
        QJsonObject o;
        o[QLatin1String("palette_text")] = pal.color(QPalette::Text).name(QColor::HexArgb);
        o[QLatin1String("palette_window_text")] = pal.color(QPalette::WindowText).name(QColor::HexArgb);
        o[QLatin1String("qt_version")] = QLatin1String(qVersion());
        std::printf("%s\n", QJsonDocument(o).toJson(QJsonDocument::Compact).constData());
    }
    for (const QJsonValue &cv : doc.value(QLatin1String("cases")).toArray()) {
        const QJsonObject c = cv.toObject();
        const QString path = dir + QLatin1String("/svg/") + c.value(QLatin1String("id")).toString() + QLatin1String(".svg");
        for (const QJsonValue &tv : doc.value(QLatin1String("qt_targets")).toArray()) {
            const QJsonArray t = tv.toArray();
            const QString fmt = t.at(0).toString();
            const QString cs = t.at(1).isNull() ? QString() : t.at(1).toString();
            g_messages.clear();
            const QImage img = render(path, W, H, fmt, cs);
            QJsonObject o;
            o[QLatin1String("id")] = c.value(QLatin1String("id"));
            o[QLatin1String("target")] = QLatin1String("qt:") + fmt + QLatin1Char(':') + (cs.isEmpty() ? QLatin1String("none") : cs);
            QJsonArray px;
            for (const QJsonValue &pv : c.value(QLatin1String("points")).toArray())
                px.append(rawPixel(img, pv.toArray().at(0).toInt(), pv.toArray().at(1).toInt()));
            o[QLatin1String("pixels")] = px;
            o[QLatin1String("messages")] = QJsonArray::fromStringList(g_messages);
            std::printf("%s\n", QJsonDocument(o).toJson(QJsonDocument::Compact).constData());
        }
    }
    for (const QJsonValue &pv : doc.value(QLatin1String("precision")).toArray()) {
        const QJsonObject p = pv.toObject();
        const QString path = dir + QLatin1String("/svg/") + p.value(QLatin1String("id")).toString() + QLatin1String(".svg");
        for (const char *fmt : {"RGBA64", "RGBA16FPx4", "RGBA32FPx4", "ARGB32"}) {
            g_messages.clear();
            const QImage img = render(path, p.value(QLatin1String("width")).toInt(), p.value(QLatin1String("height")).toInt(),
                                      QLatin1String(fmt), QString());
            QSet<double> levels;
            QJsonArray row;
            for (int x = 0; x < img.width(); ++x) {
                const double g = rawPixel(img, x, 1).at(1).toDouble();
                levels.insert(g);
                if (x % 64 == 0)
                    row.append(g);
            }
            QJsonObject o;
            o[QLatin1String("precision")] = p.value(QLatin1String("id"));
            o[QLatin1String("target")] = QLatin1String("qt:") + QLatin1String(fmt) + QLatin1String(":none");
            o[QLatin1String("distinct")] = levels.size();
            o[QLatin1String("sample")] = row;
            o[QLatin1String("messages")] = QJsonArray::fromStringList(g_messages);
            std::printf("%s\n", QJsonDocument(o).toJson(QJsonDocument::Compact).constData());
        }
    }
    return 0;
}
