// sbs2mpo: write a side-by-side picture (left eye first) as an MPO through Qt's image plugins
// (Sparky Stereo OS's KImageFormats stereo plugin reads the Stereo3DLayout key).
#include <QGuiApplication>
#include <QImage>
#include <QImageWriter>
#include <cstdio>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 3) {
        std::fprintf(stderr, "usage: sbs2mpo side-by-side.png out.mpo\n");
        return 2;
    }
    QImage sbs(QString::fromLocal8Bit(argv[1]));
    if (sbs.isNull() || sbs.width() % 2) {
        std::fprintf(stderr, "sbs2mpo: cannot read an even-width picture from %s\n", argv[1]);
        return 1;
    }
    sbs = sbs.convertToFormat(QImage::Format_RGB32);
    sbs.setText(QStringLiteral("Stereo3DLayout"), QStringLiteral("sideBySideLeftFirst"));
    QImageWriter writer(QString::fromLocal8Bit(argv[2]), "mpo");
    writer.setQuality(92);
    if (!writer.write(sbs)) {
        std::fprintf(stderr, "sbs2mpo: %s\n", qPrintable(writer.errorString()));
        return 1;
    }
    return 0;
}
