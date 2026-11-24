// SPDX-License-Identifier: GPL-3.0-or-later
#include "packings.h"
#include <stereo-policy.h>
#include <QCoreApplication>
#include <QSet>
#include <QtTest>

class PackingListTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void completeSharedList()
    {
        const auto list = Sparky::Camera::packings();
        QCOMPARE(size_t(list.size()), stereo_policy_input_format_count());
        QSet<QString> ids;
        for (size_t i = 0; i < stereo_policy_input_format_count(); ++i) {
            const auto *entry = stereo_policy_input_format_at(i);
            QCOMPARE(list[qsizetype(i)].id, QString::fromLatin1(entry->id));
            QVERIFY(!ids.contains(list[qsizetype(i)].id));
            ids.insert(list[qsizetype(i)].id);
            QCOMPARE(Sparky::Camera::packingById(list[qsizetype(i)].id).id, list[qsizetype(i)].id);
        }
    }
    void previewAndUnknown()
    {
        using Sparky::Camera::packingById;
        QCOMPARE(packingById(QStringLiteral("mono")).videoOutput, QStringLiteral("StereoNone"));
        QVERIFY(packingById(QStringLiteral("frameSequentialRightFirst")).videoOutput.isEmpty());
        QVERIFY(packingById(QStringLiteral("frameSequentialRightFirst")).swapEyes);
        QVERIFY(packingById(QStringLiteral("blockLacedLeftFirst")).videoOutput.isEmpty());
        QVERIFY(packingById(QStringLiteral("unknown-future-format")).id.isEmpty());
        QVERIFY(!packingById(QStringLiteral("depthSideBySideDepthFirst")).swapEyes);
    }
};
QTEST_GUILESS_MAIN(PackingListTest)
#include "packing-list-test.moc"
