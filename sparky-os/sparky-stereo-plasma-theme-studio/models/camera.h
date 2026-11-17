// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include "depth-interface.h"
#include <QChar>
#include <QJsonArray>
#include <QJsonObject>
#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace ModelCamera {
struct Pair {
    double distance, focalPixels, separation = 0, translation = 0;
    double nearDepth = 0, farDepth = 0, centreDepth = 0;
    int sunk = 0, popped = 0;
    QString reason;
    double disparity(double z) const
    {
        return focalPixels * separation * (1.0 / (distance - z - translation) - 1.0 / distance);
    }
    QJsonObject json() const
    {
        return { { "distance", distance }, { "focalPixels", focalPixels }, { "separation", separation },
            { "translation", translation }, { "near", nearDepth }, { "far", farDepth },
            { "centre", centreDepth }, { "sunk", sunk }, { "popped", popped }, { "reason", reason },
            { "plane", 0 } };
    }
};
inline Pair fit(
    const double* bounds, int n, double value, Depth::Limits limits, int output, int presentation, bool flat)
{
    Pair p {};
    const double rx = (bounds[1] - bounds[0]) / 2, ry = (bounds[3] - bounds[2]) / 2,
                 rz = (bounds[5] - bounds[4]) / 2;
    const double radius = std::max({ rx, ry, rz });
    if (!(radius > 0) || !std::isfinite(radius))
        throw std::runtime_error("empty-model");
    const double extent = std::max(rz, radius * .25);
    p.distance = 8 * radius;
    p.focalPixels = .28 * n * (p.distance - 3 * extent) / radius;
    const double pixelRatio = presentation > 0 ? double(n) / presentation : 1.;
    p.sunk = std::abs(Depth::parallax(limits.sunk, output));
    p.popped = std::abs(Depth::parallax(limits.popped, output));
    auto candidate = [&](double t) {
        p.translation = t;
        double kmax = std::numeric_limits<double>::infinity();
        for (double z : { -rz, rz }) {
            const double Z = p.distance - z - t, k = 1 / Z - 1 / p.distance;
            if (Z <= 0)
                throw std::runtime_error("invalid-camera");
            if (std::abs(k) < 1e-14)
                continue;
            kmax = std::min(kmax, (k > 0 ? p.popped : p.sunk) * pixelRatio / std::abs(k));
            for (double x : { -rx, rx }) {
                const double u = n / 2.0 + p.focalPixels * x / Z;
                kmax = std::min(kmax, 2 * std::max(0., std::min(u - .5, n - .5 - u)) / std::abs(k));
            }
        }
        p.separation = std::isfinite(kmax) ? std::max(0., kmax) / p.focalPixels : 0;
        p.nearDepth = p.disparity(rz) / pixelRatio;
        p.farDepth = p.disparity(-rz) / pixelRatio;
        p.centreDepth = p.disparity(0) / pixelRatio;
    };
    candidate(2 * extent * value);
    if (value && (value < 0 ? p.sunk : p.popped) == 0) {
        p.separation = 0;
        p.reason = "zero-limit";
    } else if (value && std::abs(std::round(p.centreDepth)) < 1) {
        const double start = p.translation, end = std::copysign(2 * extent, value);
        bool found = false;
        for (int i = 1; i <= 256; ++i) {
            candidate(start + (end - start) * i / 256.);
            if (std::abs(std::round(p.centreDepth)) >= 1) {
                found = true;
                break;
            }
        }
        if (!found) {
            p.separation = 0;
            p.reason = "no-room";
        }
    }
    if (flat || !p.reason.isEmpty())
        p.separation = 0;
    p.nearDepth = p.disparity(rz) / pixelRatio;
    p.farDepth = p.disparity(-rz) / pixelRatio;
    p.centreDepth = p.disparity(0) / pixelRatio;
    return p;
}
}
