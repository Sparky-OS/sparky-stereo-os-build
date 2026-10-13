// SPDX-License-Identifier: GPL-2.0-or-later
#include "frameclient.h"
#include <QTest>
#include <QDir>
#include <QtEndian>
#include <sys/socket.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <array>

class NativeFrameTest : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void malformed_data()
    {
        QTest::addColumn<int>("fault");
        for (int i = 0; i < 9; ++i) QTest::newRow(qPrintable(QString::number(i))) << i;
    }
    void malformed()
    {
        QFETCH(int, fault);
        FrameClient client;
        int pair[2];
        QVERIFY(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) == 0);
        client.m_pixels = pair[0];
        client.m_notifier = new QSocketNotifier(pair[0], QSocketNotifier::Read, &client);
        client.m_running = true;
        int fd = memfd_create("test-frame", MFD_CLOEXEC | MFD_ALLOW_SEALING);
        QVERIFY(fd >= 0);
        QVERIFY(ftruncate(fd, 32) == 0);
        std::array<unsigned char,32> pixels;
        pixels.fill(255);
        QCOMPARE(write(fd, pixels.data(), pixels.size()), 32);
        if (fault != 4) QVERIFY(fcntl(fd, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) == 0);
        std::array<quint32,8> header{0x46334453,1,4,2,16,1,32,1};
        if (fault == 1) header[2] = 8194;
        if (fault == 2) header[2] = 3;
        if (fault == 3) header[6] = 67108865;
        if (fault == 5) client.m_sequence = 1;
        if (fault == 6) header[7] = 7;
        for (auto &word : header) word = qToLittleEndian(word);
        std::array<char,CMSG_SPACE(20*sizeof(int))> ancillary{};
        iovec vector{header.data(), fault == 7 ? 4u : sizeof(header)};
        msghdr message{};
        message.msg_iov = &vector; message.msg_iovlen = 1;
        message.msg_control = ancillary.data();
        const int count = fault == 8 ? 20 : 1;
        message.msg_controllen = CMSG_SPACE(count*sizeof(int));
        auto *item = CMSG_FIRSTHDR(&message);
        item->cmsg_level = SOL_SOCKET; item->cmsg_type = SCM_RIGHTS; item->cmsg_len = CMSG_LEN(count*sizeof(int));
        for (int i = 0; i < count; ++i) reinterpret_cast<int *>(CMSG_DATA(item))[i] = fd;
        const auto openFiles = [] { return QDir(QStringLiteral("/proc/self/fd")).entryList(QDir::AllEntries | QDir::NoDotAndDotDot).size(); };
        const auto before = openFiles();
        QCOMPARE(sendmsg(pair[1], &message, 0), ssize_t(vector.iov_len));
        client.readFrame();
        QCOMPARE(openFiles(), before);
        if (fault == 0) {
            QCOMPARE(client.frame().size(), QSize(4,2));
            QCOMPARE(client.frame().pixelColor(0,0), QColor(Qt::white));
            quint32 ack = 0;
            QCOMPARE(recv(pair[1], &ack, 4, MSG_DONTWAIT), 4);
            QCOMPARE(qFromLittleEndian(ack), 1u);
            client.setRunning(false);
            QVERIFY(client.frame().isNull());
        } else {
            QVERIFY(client.frame().isNull());
            QVERIFY(!client.m_notifier->isEnabled());
        }
        close(fd); close(pair[1]);
    }
};
QTEST_GUILESS_MAIN(NativeFrameTest)
#include "nativeframetest.moc"
