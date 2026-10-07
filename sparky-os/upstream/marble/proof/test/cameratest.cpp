// Test aid: the orbit of the stereo cameras checked against the geometry, no window needed.
// For points on the visible hemisphere: screen x of the point with the original axis (x0, z0 from the sphere), with the axis turned
// for the left eye (+half) and the right eye (-half), against x0*cos(h) + z0*sin(h) (left) and x0*cos(h) - z0*sin(h) (right).
#include <ViewportParams.h>
#include <GeoDataCoordinates.h>
#include <AbstractProjection.h>
#include <Quaternion.h>
#include <cstdio>
#include <cmath>
using namespace Marble;
int main(int argc, char **argv)
{
    const double sepDeg = argc > 1 ? atof(argv[1]) : 2.0;
    const double h = sepDeg * M_PI / 180 / 2;
    ViewportParams vp(Spherical, 10.0 * DEG2RAD, 20.0 * DEG2RAD, 300, QSize(800, 600));
    const Quaternion axis = vp.planetAxis();
    double maxErrL = 0, maxErrR = 0; int n = 0; int nearRightInLeft = 0, nearCount = 0;
    for (double lon = -80; lon <= 100; lon += 7) for (double lat = -60; lat <= 80; lat += 7) {
        GeoDataCoordinates c(lon * DEG2RAD, lat * DEG2RAD, 0);
        qreal x0, y0; bool hid;
        vp.setPlanetAxis(axis);
        if (!vp.currentProjection()->screenCoordinates(c, &vp, x0, y0, hid)) continue;
        const double X = (x0 - 400) / 300.0, Y = -(y0 - 300) / 300.0;
        const double Z = sqrt(1 - X * X - Y * Y);
        qreal xl, yl, xr, yr;
        vp.setPlanetAxis(axis * Quaternion::fromEuler(0, -h, 0));
        const bool okl = vp.currentProjection()->screenCoordinates(c, &vp, xl, yl, hid);
        vp.setPlanetAxis(axis * Quaternion::fromEuler(0, h, 0));
        const bool okr = vp.currentProjection()->screenCoordinates(c, &vp, xr, yr, hid);
        if (!okl || !okr) continue;
        const double predL = 400 + 300 * (X * cos(h) + Z * sin(h)), predR = 400 + 300 * (X * cos(h) - Z * sin(h));
        maxErrL = fmax(maxErrL, fabs(xl - predL)); maxErrR = fmax(maxErrR, fabs(xr - predR));
        if (Z > 0.5) { ++nearCount; if (xl > xr) ++nearRightInLeft; }
        if (fabs(yl - y0) > 1e-6 || fabs(yr - y0) > 1e-6) printf("vertical change at %f %f\n", lon, lat);
        ++n;
    }
    printf("points=%d max|x-pred| left=%.6f right=%.6f px; near points with x_left > x_right: %d of %d\n", n, maxErrL, maxErrR, nearRightInLeft, nearCount);
    vp.setPlanetAxis(axis);
    printf("restored axis equal: %d\n", (int)(fabs(vp.planetAxis().v[1] - axis.v[1]) < 1e-12));
}
