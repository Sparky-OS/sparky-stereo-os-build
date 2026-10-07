// Test aid: the perspective eye cameras of the vertical perspective projection checked against a closed-form pinhole camera, no window needed.
// For points on the visible surface: the eye camera at (+-e, 0, P) in the frame of the view axis (X right, Y up, Z to the camera, the globe a unit
// sphere at the origin), parallel axes, off-axis so that the plane Z = 0 through the globe's center stays in place:
//   x = cx + s * ((P-1)(X-e)/(P-Z) + e(P-1)/P),  y = cy - s * (P-1) Y/(P-Z),  s = R * sqrt((P+1)/(P-1)),  P = 1.5 + 1200/R/tan(55 deg)
// with e = P sin(h), h = half of the separation. Also the pixel -> geographic inverse against the forward projection.
#include <ViewportParams.h>
#include <GeoDataCoordinates.h>
#include <AbstractProjection.h>
#include <MarbleGlobal.h>
#include <cstdio>
#include <cmath>
using namespace Marble;
int main(int argc, char **argv)
{
    const double sepDeg = argc > 1 ? atof(argv[1]) : 2.0;
    const int R = argc > 2 ? atoi(argv[2]) : 300;
    const double lon0 = 10, lat0 = 20;
    const double h = sepDeg * M_PI / 180 / 2;
    const double P = 1.5 + 3 * 1000 * 0.4 / R / tan(0.5 * 110 * M_PI / 180);
    const double s = R * sqrt((P + 1) / (P - 1));
    const double cx = 400, cy = 300;
    ViewportParams vp(VerticalPerspective, lon0 * DEG2RAD, lat0 * DEG2RAD, R, QSize(800, 600));
    const double sp = sin(lat0 * DEG2RAD), cp = cos(lat0 * DEG2RAD);
    double maxErr[3] = {0, 0, 0}, maxDy = 0, maxInv = 0, maxZero = 0;
    int n = 0, nearCrossed = 0, nearCount = 0, hiddenDisagree = 0, hid2d = 0;
    const double eyes[3] = {0, -h, h};  // centre, left, right
    for (double lon = -120; lon <= 140; lon += 3) for (double lat = -80; lat <= 85; lat += 3) {
        const double la = lat * DEG2RAD, dl = (lon - lon0) * DEG2RAD;
        const double X = cos(la) * sin(dl), Y = cp * sin(la) - sp * cos(la) * cos(dl), Z = sp * sin(la) + cp * cos(la) * cos(dl);
        GeoDataCoordinates c(lon * DEG2RAD, lat * DEG2RAD, 0);
        double xs[3], ys[3]; bool vis[3], pvis[3];
        for (int k = 0; k < 3; ++k) {
            vp.setEyeAngle(eyes[k]);
            qreal x, y; bool hides;
            vis[k] = vp.currentProjection()->screenCoordinates(c, &vp, x, y, hides) || !hides;  // on screen or not hidden
            xs[k] = x; ys[k] = y;
            const double e = P * sin(eyes[k]);
            pvis[k] = (e * X + P * Z) > 1;               // the point faces the camera
            if (hides == pvis[k]) ++hiddenDisagree;
            if (!hides) {
                const double px = cx + s * ((P - 1) * (X - e) / (P - Z) + e * (P - 1) / P);
                const double py = cy - s * (P - 1) * Y / (P - Z);
                maxErr[k] = fmax(maxErr[k], fabs(x - px));
                maxDy = fmax(maxDy, fabs(y - py));
                // the inverse: pixel back to the same point
                qreal lo, la2;
                if (Z > 0.4 && x >= 0 && y >= 0 && x < 800 && y < 600) {
                    if (vp.currentProjection()->geoCoordinates(int(round(x)), int(round(y)), &vp, lo, la2, GeoDataCoordinates::Degree)) {
                        // the pixel was rounded: compare through the forward projection of the answer
                        qreal x2, y2; bool h2;
                        vp.currentProjection()->screenCoordinates(GeoDataCoordinates(lo * DEG2RAD, la2 * DEG2RAD, 0), &vp, x2, y2, h2);
                        maxInv = fmax(maxInv, hypot(x2 - round(x), y2 - round(y)));
                    } else { maxInv = 1e9; if (getenv("DBG")) printf("inverse failed eye %d lon %g lat %g Z %g pix %g %g\n", k, lon, lat, Z, x, y); }
                }
            }
        }
        if (!(vis[0] || vis[1] || vis[2])) continue;
        // the plane through the centre of the globe: a point with Z = 0 has no disparity (any lon/lat with |Z| tiny)
        if (fabs(Z) < 0.01) maxZero = fmax(maxZero, fabs(xs[1] - xs[2]));
        if (pvis[0] && pvis[1] && pvis[2] && xs[1] != 0 && xs[2] != 0) {
            ++n;
            if (Z > 0.5) { ++nearCount; if (xs[1] > xs[2]) ++nearCrossed; }
        }
        (void)hid2d;
    }
    printf("separation %.1f deg, radius %d, P=%.4f, s=%.3f px, eye offset e=%.5f radii\n", sepDeg, R, P, s, P * sin(h));
    printf("points=%d max|x-pred| centre=%.6f left=%.6f right=%.6f px, max|y-pred|=%.6f px\n", n, maxErr[0], maxErr[1], maxErr[2], maxDy);
    printf("near points (Z>0.5) with x_left > x_right (crossed): %d of %d\n", nearCrossed, nearCount);
    printf("points with Z~0 (the zero-parallax plane): max |x_left-x_right| = %.4f px\n", maxZero);
    printf("inverse (pixel -> geo -> pixel) max error %.4f px; visibility disagreements with the closed form: %d\n", maxInv, hiddenDisagree);
    vp.setEyeAngle(0);
    printf("eye angle restored: %d\n", (int)(vp.eyeAngle() == 0));
}
