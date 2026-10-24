#include "kdenlivesettings.h"
#include <QCoreApplication>
#include <QDebug>
int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("order223-config-proof"));
    const auto value = KdenliveSettings::hwDecoding();
    qInfo() << "Read" << value;
    if (argc == 2 && QByteArray(argv[1]) == "off")
        return value.isEmpty() ? 0 : 5;
    if (value != QStringLiteral("auto")) return 1;
    KdenliveSettings::setHwDecoding(QStringLiteral("vaapi"));
    if (KdenliveSettings::hwDecoding() != QStringLiteral("vaapi")) return 4;
    KdenliveSettings::setHwDecoding(QString());
    if (!KdenliveSettings::hwDecoding().isEmpty()) return 2;
    if (!KdenliveSettings::self()->save()) return 3;
    qInfo() << "PASS default auto, explicit decoder and persisted software override";
}
