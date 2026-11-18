// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// sparky-stereo-headset-battery: the battery of a USB headset, in the list every program reads.
//
// Plasma's Power and Battery applet, the Info Centre's Energy page and PowerDevil's low-battery notice read UPower, and UPower reads the kernel's
// power_supply class. For some headsets the kernel's own driver makes that entry (hid-corsair-void, hid-steelseries-arctis, hid-logitech-hidpp);
// for the others only HeadsetControl can read the charge. This service, a system service because /dev/uhid is the superuser's, gives the kernel a
// small virtual HID device whose only content is the headset's charge, so that hid-input makes the power_supply entry and UPower, Plasma and PowerDevil
// treat it like any other. The device exists while the headset says its charge; when the headset is off, unplugged or silent the device is destroyed at
// once, so no stale percentage is ever shown. A headset for which the kernel already has a power_supply is left to the kernel (no second entry).
// The device never sends a key: it declares the two volume keys only because UPower learns what a battery belongs to from the input node beside it,
// and the udev rule 72-sparky-stereo-headset-battery.rules names that node a headset's.
//
// Usage: sparky-stereo-headset-battery [--once]   (--once: one pass, for the tests)

#include "headsetengine.h"

#include <KLocalizedString>

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QSocketNotifier>
#include <QTextStream>
#include <QTimer>

#include <fcntl.h>
#include <linux/uhid.h>
#include <unistd.h>

using namespace Sparky::Headset;

static QTextStream err(stderr);
static QTextStream out(stdout);

// The report descriptor: ONE application collection (Consumer Control), so the kernel names the input node as the device is named (with two collections
// it appends " Consumer Control", and UPower takes that name for the headset). Report 1 is the battery (Battery System page: Absolute State Of Charge
// 0..100 as hid-input reads it, and Charging); report 2 the two volume keys, which only give the device an input node (never sent).
static const unsigned char kDescriptor[] = {
    0x05, 0x0C, 0x09, 0x01, 0xA1, 0x01, // Usage Page (Consumer), Usage (Consumer Control), Collection (Application)
    0x85, 0x02, //   Report ID 2
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x02, //   Logical 0..1, 1 bit, 2 fields
    0x09, 0xE9, 0x09, 0xEA, 0x81, 0x02, //   Volume Increment, Volume Decrement, Input (Data, Variable, Absolute)
    0x95, 0x06, 0x81, 0x03, //   6 bits of padding
    0x85, 0x01, //   Report ID 1
    0x05, 0x85, //   Usage Page (Battery System)
    0x09, 0x65, //   Usage (Absolute State Of Charge)
    0x15, 0x00, 0x25, 0x64, 0x75, 0x08, 0x95, 0x01, 0x81, 0x02, //   0..100, 8 bits, Input
    0x09, 0x44, //   Usage (Charging)
    0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02, //   0..1, 1 bit, Input
    0x95, 0x07, 0x81, 0x03, //   7 bits of padding
    0xC0, // End Collection
};

// One virtual device: one headset
class Device : public QObject
{
public:
    Device(int fd, const QString &id, const QString &name, QObject *parent)
        : QObject(parent)
        , m_fd(fd)
        , m_id(id)
    {
        uhid_event ev{};
        ev.type = UHID_CREATE2;
        const QByteArray n = name.toUtf8().left(127);
        const QByteArray u = QByteArray("sparky-stereo-headset:") + id.toLatin1();
        memcpy(ev.u.create2.name, n.constData(), static_cast<size_t>(n.size()));
        memcpy(ev.u.create2.uniq, u.constData(), static_cast<size_t>(qMin<qsizetype>(u.size(), 63)));
        ev.u.create2.rd_size = sizeof(kDescriptor);
        ev.u.create2.bus = 0x06; // BUS_VIRTUAL: the real headset's own drivers never bind to it
        const QList<QByteArray> parts = id.toLatin1().split(':');
        ev.u.create2.vendor = parts.value(0).toUInt(nullptr, 16);
        ev.u.create2.product = parts.value(1).toUInt(nullptr, 16);
        memcpy(ev.u.create2.rd_data, kDescriptor, sizeof(kDescriptor));
        m_ok = ::write(m_fd, &ev, sizeof(ev)) == static_cast<ssize_t>(sizeof(ev));
        if (!m_ok) {
            err << "sparky-stereo-headset-battery: " << id << ": the kernel refused the device: " << strerror(errno) << '\n';
            return;
        }
        m_notifier = new QSocketNotifier(m_fd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, [this] {
            handleEvents();
        });
    }
    ~Device() override
    {
        if (m_ok) {
            uhid_event ev{};
            ev.type = UHID_DESTROY;
            [[maybe_unused]] const ssize_t r = ::write(m_fd, &ev, sizeof(ev));
        }
        ::close(m_fd);
    }
    bool ok() const
    {
        return m_ok;
    }
    void set(int level, bool charging)
    {
        m_level = level;
        m_charging = charging;
        if (m_started) {
            sendReport();
        }
    }

private:
    void handleEvents()
    {
        uhid_event ev;
        while (::read(m_fd, &ev, sizeof(ev)) == static_cast<ssize_t>(sizeof(ev))) {
            switch (ev.type) {
            case UHID_START:
            case UHID_OPEN:
                m_started = true;
                sendReport();
                break;
            case UHID_GET_REPORT: {
                // the kernel asks for the charge when something reads the entry before the first report: answer with the current one
                uhid_event rep{};
                rep.type = UHID_GET_REPORT_REPLY;
                rep.u.get_report_reply.id = ev.u.get_report.id;
                if (ev.u.get_report.rnum == 1) {
                    rep.u.get_report_reply.err = 0;
                    rep.u.get_report_reply.size = 3;
                    rep.u.get_report_reply.data[0] = 1;
                    rep.u.get_report_reply.data[1] = static_cast<unsigned char>(m_level);
                    rep.u.get_report_reply.data[2] = m_charging ? 1 : 0;
                } else {
                    rep.u.get_report_reply.err = EIO;
                }
                [[maybe_unused]] const ssize_t r = ::write(m_fd, &rep, sizeof(rep));
                break;
            }
            case UHID_SET_REPORT: {
                uhid_event rep{};
                rep.type = UHID_SET_REPORT_REPLY;
                rep.u.set_report_reply.id = ev.u.set_report.id;
                rep.u.set_report_reply.err = EIO; // nothing here is settable
                [[maybe_unused]] const ssize_t r = ::write(m_fd, &rep, sizeof(rep));
                break;
            }
            case UHID_STOP:
                m_started = false;
                break;
            default:
                break;
            }
        }
    }
    void sendReport()
    {
        uhid_event ev{};
        ev.type = UHID_INPUT2;
        ev.u.input2.size = 3;
        ev.u.input2.data[0] = 1;
        ev.u.input2.data[1] = static_cast<unsigned char>(m_level);
        ev.u.input2.data[2] = m_charging ? 1 : 0;
        [[maybe_unused]] const ssize_t r = ::write(m_fd, &ev, sizeof(ev));
    }

    int m_fd;
    QString m_id;
    bool m_ok = false;
    bool m_started = false;
    int m_level = 0;
    bool m_charging = false;
    QSocketNotifier *m_notifier = nullptr;
};

// Is there a power_supply under the USB device with these numbers that is not ours: the kernel's own driver makes the entry
static bool kernelHasBattery(const QString &id)
{
    const QStringList parts = id.split(QLatin1Char(':'));
    if (parts.size() != 2) {
        return false;
    }
    const QDir supplies(QStringLiteral("/sys/class/power_supply"));
    for (const QString &name : supplies.entryList(QDir::NoDotAndDotDot | QDir::AllEntries)) {
        QString path = QFileInfo(supplies.filePath(name)).canonicalFilePath();
        if (path.contains(QLatin1String("/devices/virtual/"))) {
            continue; // ours, or another virtual device
        }
        for (QDir d(path); d.cdUp() && d.path().startsWith(QLatin1String("/sys/devices")); ) {
            auto read = [&d](const char *file) {
                QFile f(d.filePath(QLatin1String(file)));
                return f.open(QIODevice::ReadOnly) ? QString::fromLatin1(f.readAll()).trimmed().toLower() : QString();
            };
            const QString v = read("idVendor");
            if (!v.isEmpty()) {
                if (v == parts.at(0).toLower() && read("idProduct") == parts.at(1).toLower()) {
                    return true;
                }
                break;
            }
        }
    }
    return false;
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("sparky-stereo-headset-battery"));
    KLocalizedString::setApplicationDomain("kcm_sparkystereo_headset");
    const bool once = app.arguments().contains(QLatin1String("--once"));

    QHash<QString, Device *> devices;
    QSet<QString> leftToKernel;

    auto poll = [&] {
        QList<Headset> list;
        QString error;
        QSet<QString> wanted;
        if (query(list, error)) {
            QHash<QString, int> count;
            for (const Headset &h : std::as_const(list)) {
                if (!h.batteryKnown()) {
                    continue; // off, or silent: no entry (a number from before would be a lie)
                }
                const int n = ++count[h.id];
                const QString key = n == 1 ? h.id : h.id + QLatin1Char('-') + QString::number(n);
                if (kernelHasBattery(h.id)) {
                    if (!leftToKernel.contains(key)) {
                        leftToKernel.insert(key);
                        out << key << ": the kernel's own driver gives this headset's battery; nothing is added\n";
                        out.flush();
                    }
                    continue;
                }
                wanted.insert(key);
                Device *d = devices.value(key);
                if (!d) {
                    const int fd = ::open("/dev/uhid", O_RDWR | O_CLOEXEC | O_NONBLOCK);
                    if (fd < 0) {
                        err << "sparky-stereo-headset-battery: cannot open /dev/uhid: " << strerror(errno) << " (is the uhid module loaded?)\n";
                        err.flush();
                        QCoreApplication::exit(1);
                        return;
                    }
                    d = new Device(fd, h.id, h.name, &app);
                    if (!d->ok()) {
                        delete d;
                        QCoreApplication::exit(1);
                        return;
                    }
                    devices.insert(key, d);
                    out << key << ": " << h.name << ": the battery is in the list\n";
                    out.flush();
                }
                d->set(h.battery, h.charging());
            }
        }
        for (auto it = devices.begin(); it != devices.end();) {
            if (!wanted.contains(it.key())) {
                out << it.key() << ": the headset does not say its charge; the entry is taken away\n";
                out.flush();
                delete it.value();
                it = devices.erase(it);
            } else {
                ++it;
            }
        }
        for (auto it = leftToKernel.begin(); it != leftToKernel.end();) {
            it = wanted.contains(*it) || devices.contains(*it) ? ++it : leftToKernel.erase(it);
        }
        if (once) {
            QTimer::singleShot(1500, &app, [] {
                QCoreApplication::quit();
            });
        }
    };
    QTimer timer;
    timer.setInterval(30000);
    QObject::connect(&timer, &QTimer::timeout, &app, poll);
    if (!once) {
        timer.start();
    }
    QTimer::singleShot(0, &app, poll);
    return app.exec();
}
