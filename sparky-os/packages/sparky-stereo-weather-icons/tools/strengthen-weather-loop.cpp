// SPDX-License-Identifier: GPL-3.0-or-later
// Strengthen modulation of existing stereo artwork without changing either projection.
#include <QColorSpace>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QRgba64>
#include <jxl/encode.h>
#include <stereo-layer/animatedpicture.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <numbers>
#include <vector>

namespace {
void require(bool ok, const char *operation)
{
    if (!ok) {
        std::fprintf(stderr, "%s\n", operation);
        std::exit(EXIT_FAILURE);
    }
}

QImage compose(Stereo::Picture pair, double phase, bool moon, bool symbolic)
{
    require(pair.isStereo() && pair.left.format() == QImage::Format_RGBA64
            && pair.right.format() == QImage::Format_RGBA64, "Expected two straight-alpha 16-bit views");
    const int side = pair.left.width();
    require(pair.left.size() == QSize(side, side) && pair.right.size() == pair.left.size(), "Expected equal square views");
    require(pair.left.colorSpace() == pair.right.colorSpace(), "The eyes disagree on colour space");
    QImage result(2 * side, side, QImage::Format_RGBA64);
    result.setColorSpace(pair.left.colorSpace());
    const double beat = (1.0 - std::cos(phase)) / 2.0;
    for (int y = 0; y < side; ++y) {
        const auto *left = reinterpret_cast<const QRgba64 *>(pair.left.constScanLine(y));
        const auto *right = reinterpret_cast<const QRgba64 *>(pair.right.constScanLine(y));
        auto *row = reinterpret_cast<QRgba64 *>(result.scanLine(y));
        for (int x = 0; x < 2 * side; ++x) {
            QRgba64 pixel = x < side ? left[x] : right[x - side];
            if (moon && !symbolic) {
                // Let the existing lunar relief catch a band of light as the Moon turns.
                // Full disc coverage, crater positions and the existing star silhouettes are preserved.
                const double u = (x % side + 0.5) / side;
                const double band = 1.0 - std::min(1.0, std::abs(u - (0.5 + 0.18 * std::sin(phase))) / 0.48);
                const double exposure = 1.0 - 0.38 * beat * band;
                const auto shade = [exposure](quint16 sample) {
                    return quint16(std::lround(sample * exposure));
                };
                pixel = QRgba64::fromRgba64(shade(pixel.red()), shade(pixel.green()),
                                          shade(pixel.blue()), pixel.alpha());
            } else {
                // Opacity remains visible when Kirigami recolours a symbolic icon.
                const double exposure = 1.0 - 0.72 * beat;
                const auto shade = [exposure](quint16 sample) {
                    return quint16(std::lround(sample * exposure));
                };
                pixel = QRgba64::fromRgba64(shade(pixel.red()), shade(pixel.green()), shade(pixel.blue()),
                                          quint16(std::lround(pixel.alpha() * (1.0 - 0.58 * beat))));
            }
            row[x] = pixel;
        }
    }
    return result;
}

void encode(const QString &path, const QString &xmlPath, Stereo::AnimatedPicture &animation, bool moon, bool symbolic)
{
    std::unique_ptr<JxlEncoder, decltype(&JxlEncoderDestroy)> encoder(JxlEncoderCreate(nullptr), JxlEncoderDestroy);
    auto *enc = encoder.get();
    require(enc && JxlEncoderUseBoxes(enc) == JXL_ENC_SUCCESS, "Enable JPEG XL container boxes");
    const auto size = animation.pairAt(0).left.size();
    JxlBasicInfo info;
    JxlEncoderInitBasicInfo(&info);
    info.xsize = size.width() * 2;
    info.ysize = size.height();
    info.bits_per_sample = 16;
    info.num_extra_channels = 1;
    info.alpha_bits = 16;
    info.uses_original_profile = JXL_TRUE;
    info.have_animation = JXL_TRUE;
    info.animation.tps_numerator = 1000;
    info.animation.tps_denominator = 1;
    info.animation.num_loops = 0;
    require(JxlEncoderSetBasicInfo(enc, &info) == JXL_ENC_SUCCESS, "Set JPEG XL basic info");
    const QByteArray profile = animation.pairAt(0).left.colorSpace().iccProfile();
    if (!profile.isEmpty()) {
        require(JxlEncoderSetICCProfile(enc, reinterpret_cast<const uint8_t *>(profile.constData()),
                                        profile.size()) == JXL_ENC_SUCCESS, "Keep the source ICC profile");
    } else {
        JxlColorEncoding colour;
        JxlColorEncodingSetToSRGB(&colour, JXL_FALSE);
        require(JxlEncoderSetColorEncoding(enc, &colour) == JXL_ENC_SUCCESS, "Keep source sRGB");
    }
    auto *settings = JxlEncoderFrameSettingsCreate(enc, nullptr);
    require(JxlEncoderSetFrameLossless(settings, JXL_TRUE) == JXL_ENC_SUCCESS, "Set lossless JPEG XL mode");
    require(JxlEncoderFrameSettingsSetOption(settings, JXL_ENC_FRAME_SETTING_EFFORT, 3) == JXL_ENC_SUCCESS, "Set encoder effort");
    const JxlPixelFormat format{4, JXL_TYPE_UINT16, JXL_NATIVE_ENDIAN, 0};
    for (qint64 time = 0; time < animation.duration();) {
        const qint64 next = animation.nextFrameTime(time);
        require(next > time && next <= animation.duration(), "Expected an infinite native loop");
        const double phase = 2 * std::numbers::pi * double(time) / double(animation.duration());
        const auto frame = compose(animation.pairAt(time), phase, moon, symbolic);
        JxlFrameHeader header;
        JxlEncoderInitFrameHeader(&header);
        header.duration = next - time;
        require(JxlEncoderSetFrameHeader(settings, &header) == JXL_ENC_SUCCESS, "Keep source frame duration");
        require(JxlEncoderAddImageFrame(settings, &format, frame.constBits(), frame.sizeInBytes()) == JXL_ENC_SUCCESS, "Add JPEG XL frame");
        time = next;
    }
    QFile xml(xmlPath);
    require(xml.open(QIODevice::ReadOnly), "Open original JXLStereo packet");
    const auto metadata = xml.readAll();
    require(!metadata.isEmpty() && JxlEncoderAddBox(enc, "xml ",
            reinterpret_cast<const uint8_t *>(metadata.constData()), metadata.size(), JXL_FALSE) == JXL_ENC_SUCCESS,
            "Copy the original JXLStereo packet");
    JxlEncoderCloseInput(enc);
    QFile output(path);
    require(output.open(QIODevice::WriteOnly), "Open output file");
    uint8_t bytes[65536];
    for (;;) {
        auto *next = bytes;
        size_t available = sizeof(bytes);
        const auto status = JxlEncoderProcessOutput(enc, &next, &available);
        const auto length = next - bytes;
        require(output.write(reinterpret_cast<const char *>(bytes), length) == length, "Write JPEG XL");
        if (status == JXL_ENC_SUCCESS) {
            return;
        }
        require(status == JXL_ENC_NEED_MORE_OUTPUT, "Finish JPEG XL");
    }
}

void evidence(const QString &directory, Stereo::AnimatedPicture &animation)
{
    require(QDir().mkpath(directory), "Create evidence directory");
    for (int phase : {0, 4, 8}) {
        const auto views = animation.pairAt(animation.duration() * phase / 12);
        const auto frame = compose(views, 0, false, false);
        require(frame.save(directory + '/' + QString::number(phase) + ".png"), "Save native 16-bit evidence");
    }
}
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    if (argc != 6) {
        return 64;
    }
    const QString source = QString::fromLocal8Bit(argv[1]);
    const QString target = QString::fromLocal8Bit(argv[2]);
    const QString mode = QString::fromLatin1(argv[4]);
    Stereo::AnimatedPicture animation(source);
    require(animation.duration() > 0 && animation.reason().isEmpty(), "Read predecessor loop");
    const QString proof = QString::fromLocal8Bit(argv[5]);
    if (!proof.isEmpty()) {
        evidence(proof + "/before", animation);
    }
    encode(target, QString::fromLocal8Bit(argv[3]), animation, mode == "moon", mode == "symbolic");
    if (!proof.isEmpty()) {
        Stereo::AnimatedPicture result(target);
        require(result.duration() == animation.duration() && result.reason().isEmpty(), "Verify the finished loop");
        evidence(proof + "/after", result);
    }
}
