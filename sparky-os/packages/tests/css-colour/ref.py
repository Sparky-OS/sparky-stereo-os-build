"""Reference CSS colour engine for ORDER 348's measurements.

Every conversion is a port of the specifications' own sample code:
CSS Color 4 (CRD 1 November 2026) section 19 and sections 7.1, 7.2, 8.1, 8.2, 20.3,
CSS Color HDR 1 (WD 26 October 2026) section 11, and CSS Color 5 (WD 29 October 2026) section 6.1.
The grammar follows CSS Color 4 sections 4 to 10, CSS Color 5 sections 2 to 8 and CSS Color HDR sections 4 to 8.
Gamut mapping is CSS Color 4 section 14.2.2 (binary search with local MINDE).
Interpolation is CSS Color 4 section 13 and CSS Color 5 section 3.3.
This is the test oracle: it is written for clarity, not speed, and it is not shipped.
"""

import math
import re

# ---------------------------------------------------------------- matrices and sample code, CSS Color 4 section 19

D50 = [0.3457 / 0.3585, 1.00000, (1.0 - 0.3457 - 0.3585) / 0.3585]
D65 = [0.3127 / 0.3290, 1.00000, (1.0 - 0.3127 - 0.3290) / 0.3290]


def mul(M, v):
    return [M[0][0] * v[0] + M[0][1] * v[1] + M[0][2] * v[2],
            M[1][0] * v[0] + M[1][1] * v[1] + M[1][2] * v[2],
            M[2][0] * v[0] + M[2][1] * v[1] + M[2][2] * v[2]]


def spow(base, e):
    return math.copysign(abs(base) ** e, base)


def lin_sRGB(rgb):
    out = []
    for val in rgb:
        sign = -1 if val < 0 else 1
        a = abs(val)
        out.append(val / 12.92 if a <= 0.04045 else sign * ((a + 0.055) / 1.055) ** 2.4)
    return out


def gam_sRGB(rgb):
    out = []
    for val in rgb:
        sign = -1 if val < 0 else 1
        a = abs(val)
        out.append(sign * (1.055 * a ** (1 / 2.4) - 0.055) if a > 0.0031308 else 12.92 * val)
    return out


M_SRGB_TO_XYZ = [[506752 / 1228815, 87881 / 245763, 12673 / 70218],
                 [87098 / 409605, 175762 / 245763, 12673 / 175545],
                 [7918 / 409605, 87881 / 737289, 1001167 / 1053270]]
M_XYZ_TO_SRGB = [[12831 / 3959, -329 / 214, -1974 / 3959],
                 [-851781 / 878810, 1648619 / 878810, 36519 / 878810],
                 [705 / 12673, -2585 / 12673, 705 / 667]]
M_P3_TO_XYZ = [[608311 / 1250200, 189793 / 714400, 198249 / 1000160],
               [35783 / 156275, 247089 / 357200, 198249 / 2500400],
               [0 / 1, 32229 / 714400, 5220557 / 5000800]]
M_XYZ_TO_P3 = [[446124 / 178915, -333277 / 357830, -72051 / 178915],
               [-14852 / 17905, 63121 / 35810, 423 / 17905],
               [11844 / 330415, -50337 / 660830, 316169 / 330415]]
M_PROPHOTO_TO_XYZ = [[0.79776664490064230, 0.13518129740053308, 0.03134773412839220],
                     [0.28807482881940130, 0.71183523424187300, 0.00008993693872564],
                     [0.00000000000000000, 0.00000000000000000, 0.82510460251046020]]
M_XYZ_TO_PROPHOTO = [[1.34578688164715830, -0.25557208737979464, -0.05110186497554526],
                     [-0.54463070512490190, 1.50824774284514680, 0.02052744743642139],
                     [0.00000000000000000, 0.00000000000000000, 1.21196754563894520]]
M_A98_TO_XYZ = [[573536 / 994567, 263643 / 1420810, 187206 / 994567],
                [591459 / 1989134, 6239551 / 9945670, 374412 / 4972835],
                [53769 / 1989134, 351524 / 4972835, 4929758 / 4972835]]
M_XYZ_TO_A98 = [[1829569 / 896150, -506331 / 896150, -308931 / 896150],
                [-851781 / 878810, 1648619 / 878810, 36519 / 878810],
                [16779 / 1248040, -147721 / 1248040, 1266979 / 1248040]]
M_2020_TO_XYZ = [[63426534 / 99577255, 20160776 / 139408157, 47086771 / 278816314],
                 [26158966 / 99577255, 472592308 / 697040785, 8267143 / 139408157],
                 [0 / 1, 19567812 / 697040785, 295819943 / 278816314]]
M_XYZ_TO_2020 = [[30757411 / 17917100, -6372589 / 17917100, -4539589 / 17917100],
                 [-19765991 / 29648200, 47925759 / 29648200, 467509 / 29648200],
                 [792561 / 44930125, -1921689 / 44930125, 42328811 / 44930125]]
M_D65_TO_D50 = [[1.0479297925449969, 0.022946870601609652, -0.05019226628920524],
                [0.02962780877005599, 0.9904344267538799, -0.017073799063418826],
                [-0.009243040646204504, 0.015055191490298152, 0.7518742814281371]]
M_D50_TO_D65 = [[0.955473421488075, -0.02309845494876471, 0.06325924320057072],
                [-0.0283697093338637, 1.0099953980813041, 0.021041441191917323],
                [0.012314014864481998, -0.020507649298898964, 1.330365926242124]]


def lin_ProPhoto(rgb):
    Et2 = 16 / 512
    return [v / 16 if abs(v) <= Et2 else spow(v, 1.8) for v in rgb]


def gam_ProPhoto(rgb):
    Et = 1 / 512
    return [spow(v, 1 / 1.8) if abs(v) >= Et else 16 * v for v in rgb]


def lin_a98rgb(rgb):
    return [spow(v, 563 / 256) for v in rgb]


def gam_a98rgb(rgb):
    return [spow(v, 256 / 563) for v in rgb]


def lin_2020(rgb):
    return [spow(v, 2.4) for v in rgb]


def gam_2020(rgb):
    return [spow(v, 1 / 2.4) for v in rgb]


def XYZ_to_Lab(XYZ):
    eps = 216 / 24389
    kappa = 24389 / 27
    xyz = [v / D50[i] for i, v in enumerate(XYZ)]
    f = [math.copysign(abs(v) ** (1 / 3), v) if v > eps else (kappa * v + 16) / 116 for v in xyz]
    return [116 * f[1] - 16, 500 * (f[0] - f[1]), 200 * (f[1] - f[2])]


def Lab_to_XYZ(Lab):
    kappa = 24389 / 27
    eps = 216 / 24389
    l116 = Lab[0] / 116
    a500 = Lab[1] / 500
    b200 = Lab[2] / 200
    f1 = l116 + 16 / 116
    f0 = f1 + a500
    f2 = f1 - b200
    xyz = [f0 ** 3 if f0 ** 3 > eps else (l116 + a500) * (116 / kappa),
           ((Lab[0] + 16) / 116) ** 3 if Lab[0] > kappa * eps else Lab[0] / kappa,
           f2 ** 3 if f2 ** 3 > eps else (l116 - b200) * (116 / kappa)]
    return [v * D50[i] for i, v in enumerate(xyz)]


def to_polar(lab, epsilon):
    chroma = math.hypot(lab[1], lab[2])
    hue = math.degrees(math.atan2(lab[2], lab[1]))
    if hue < 0:
        hue += 360
    if chroma <= epsilon:
        hue = None
    return [lab[0], chroma, hue]


def from_polar(lch):
    h = 0.0 if lch[2] is None else lch[2]
    return [lch[0], lch[1] * math.cos(math.radians(h)), lch[1] * math.sin(math.radians(h))]


M_XYZ_TO_LMS = [[0.8190224379967030, 0.3619062600528904, -0.1288737815209879],
                [0.0329836539323885, 0.9292868615863434, 0.0361446663506424],
                [0.0481771893596242, 0.2642395317527308, 0.6335478284694309]]
M_LMS_TO_OKLAB = [[0.2104542683093140, 0.7936177747023054, -0.0040720430116193],
                  [1.9779985324311684, -2.4285922420485799, 0.4505937096174110],
                  [0.0259040424655478, 0.7827717124575296, -0.8086757549230774]]
M_LMS_TO_XYZ = [[1.2268798758459243, -0.5578149944602171, 0.2813910456659647],
                [-0.0405757452148008, 1.1122868032803170, -0.0717110580655164],
                [-0.0763729366746601, -0.4214933324022432, 1.5869240198367816]]
M_OKLAB_TO_LMS = [[1.0000000000000000, 0.3963377773761749, 0.2158037573099136],
                  [1.0000000000000000, -0.1055613458156586, -0.0638541728258133],
                  [1.0000000000000000, -0.0894841775298119, -1.2914855480194092]]


def XYZ_to_OKLab(XYZ):
    lms = mul(M_XYZ_TO_LMS, XYZ)
    return mul(M_LMS_TO_OKLAB, [math.copysign(abs(c) ** (1 / 3), c) for c in lms])


def OKLab_to_XYZ(OKLab):
    lms = mul(M_OKLAB_TO_LMS, OKLab)
    return mul(M_LMS_TO_XYZ, [c ** 3 for c in lms])


# ---------------------------------------------------------------- CSS Color HDR section 11

YW = 203.0


def pq_encode(rgb):
    n = 2610 / 2 ** 14
    m = 2523 / 2 ** 5
    c1 = 3424 / 2 ** 12
    c2 = 2413 / 2 ** 7
    c3 = 2392 / 2 ** 7
    out = []
    for val in rgb:
        x = max(val * YW / 10000, 0)
        out.append(((c1 + c2 * x ** n) / (1 + c3 * x ** n)) ** m)
    return out


def pq_decode(rgb):
    ninv = 2 ** 14 / 2610
    minv = 2 ** 5 / 2523
    c1 = 3424 / 2 ** 12
    c2 = 2413 / 2 ** 7
    c3 = 2392 / 2 ** 7
    out = []
    for val in rgb:
        vm = spow(val, minv)
        x = (max(vm - c1, 0) / (c2 - c3 * vm)) ** ninv
        out.append(x * 10000 / YW)
    return out


HLG_A = 0.17883277
HLG_B = 0.28466892
HLG_C = 0.55991073
HLG_SCALE = 3.7743


def hlg_encode(rgb):
    out = []
    for val in rgb:
        val /= HLG_SCALE
        if val <= 1 / 12:
            out.append(spow(3 * val, 0.5))
        else:
            out.append(HLG_A * math.log(12 * val - HLG_B) + HLG_C)
    return out


def hlg_decode(rgb):
    out = []
    for val in rgb:
        if val <= 0.5:
            out.append(val ** 2 / 3 * HLG_SCALE)
        else:
            out.append((math.exp((val - HLG_C) / HLG_A) + HLG_B) / 12 * HLG_SCALE)
    return out


JZ_M = [[0.41478972, 0.579999, 0.0146480], [-0.2015100, 1.120649, 0.0531008], [-0.0166008, 0.264800, 0.6684799]]
JZ_LMS_TO_IAB = [[0.5, 0.5, 0], [3.524000, -4.066708, 0.542708], [0.199076, 1.096799, -1.295875]]
JZ_LMS_TO_XYZ = [[1.9242264357876067, -1.0047923125953657, 0.037651404030618],
                 [0.35031676209499907, 0.7264811939316552, -0.06538442294808501],
                 [-0.09098281098284752, -0.3127282905230739, 1.5227665613052603]]
JZ_IAB_TO_LMS = [[1, 0.13860504327153927, 0.05804731615611883],
                 [1, -0.1386050432715393, -0.058047316156118904],
                 [1, -0.09601924202631895, -0.81189189605603900]]
JZ_B = 1.15
JZ_G = 0.66
JZ_D = -0.56
JZ_D0 = 1.6295499532821566e-11
PQ_C1 = 3424 / 2 ** 12
PQ_C2 = 2413 / 2 ** 7
PQ_C3 = 2392 / 2 ** 7
PQ_N = 2610 / 2 ** 14
JZ_P = 1.7 * 2523 / 2 ** 5


def XYZ_to_Jzazbz(XYZ):
    Xa, Ya, Za = [v * YW for v in XYZ]
    Xm = JZ_B * Xa - (JZ_B - 1) * Za
    Ym = JZ_G * Ya - (JZ_G - 1) * Xa
    lms = mul(JZ_M, [Xm, Ym, Za])
    pq = []
    for val in lms:
        num = PQ_C1 + PQ_C2 * spow(val / 10000, PQ_N)
        den = 1 + PQ_C3 * spow(val / 10000, PQ_N)
        pq.append(spow(num / den, JZ_P))
    Iz, az, bz = mul(JZ_LMS_TO_IAB, pq)
    Jz = (1 + JZ_D) * Iz / (1 + JZ_D * Iz) - JZ_D0
    return [Jz, az, bz]


def Jzazbz_to_XYZ(J):
    # The sample code returns absolute XYZ although its comment says relative; divided by Yw here
    # so that jzazbz(0.22207 -0.00016 -0.00012) is diffuse white, as section 6.4 says.
    Jz, az, bz = J
    Iz = (Jz + JZ_D0) / (1 + JZ_D - JZ_D * (Jz + JZ_D0))
    pq = mul(JZ_IAB_TO_LMS, [Iz, az, bz])
    pinv = 2 ** 5 / (1.7 * 2523)
    ninv = 2 ** 14 / 2610
    lms = []
    for val in pq:
        num = PQ_C1 - spow(val, pinv)
        den = PQ_C3 * spow(val, pinv) - PQ_C2
        lms.append(10000 * spow(num / den, ninv))
    Xm, Ym, Za = mul(JZ_LMS_TO_XYZ, lms)
    Xa = (Xm + (JZ_B - 1) * Za) / JZ_B
    Ya = (Ym + (JZ_G - 1) * Xa) / JZ_G
    return [Xa / YW, Ya / YW, Za / YW]


ICTCP_XYZ_TO_LMS = [[0.3592832590121217, 0.6976051147779502, -0.0358915932320290],
                    [-0.1920808463704993, 1.1004767970374321, 0.0753748658519118],
                    [0.0070797844607479, 0.0748396662186362, 0.8433265453898765]]
ICTCP_LMS_TO_ICTCP = [[2048 / 4096, 2048 / 4096, 0], [6610 / 4096, -13613 / 4096, 7003 / 4096],
                      [17933 / 4096, -17390 / 4096, -543 / 4096]]
ICTCP_LMS_TO_XYZ = [[2.0701522183894223, -1.3263473389671563, 0.2066510476294053],
                    [0.3647385209748072, 0.6805660249472273, -0.0453045459220347],
                    [-0.0497472075358123, -0.0492609666966131, 1.1880659249923042]]
ICTCP_TO_LMS = [[0.9999999999999998, 0.0086090370379328, 0.1110296250030260],
                [0.9999999999999998, -0.0086090370379328, -0.1110296250030259],
                [0.9999999999999998, 0.5600313357106791, -0.3206271749873188]]


def XYZ_to_ICtCp(XYZ):
    lms = mul(ICTCP_XYZ_TO_LMS, [v * YW for v in XYZ])
    m1 = 2610 / 16384
    m2 = 2523 / 32
    pq = []
    for val in lms:
        x = max(val, 0) / 10000
        pq.append(((PQ_C1 + PQ_C2 * x ** m1) / (1 + PQ_C3 * x ** m1)) ** m2)
    return mul(ICTCP_LMS_TO_ICTCP, pq)


def ICtCp_to_XYZ(I):
    # The sample code returns absolute XYZ; divided by Yw here (ictcp(0.58069 0 0) is diffuse white, section 6.3).
    pq = mul(ICTCP_TO_LMS, I)
    im1 = 16384 / 2610
    im2 = 32 / 2523
    lms = []
    for val in pq:
        vm = spow(val, im2)
        lms.append(10000 * (max(vm - PQ_C1, 0) / (PQ_C2 - PQ_C3 * vm)) ** im1)
    return [v / YW for v in mul(ICTCP_LMS_TO_XYZ, lms)]


# ---------------------------------------------------------------- HSL and HWB, CSS Color 4 sections 7 and 8

def hslToRgb(hue, sat, light):
    sat /= 100
    light /= 100

    def f(n):
        k = (n + hue / 30) % 12
        a = sat * min(light, 1 - light)
        return light - a * max(-1, min(k - 3, 9 - k, 1))
    return [f(0), f(8), f(4)]


def rgbToHsl(r, g, b):
    mx = max(r, g, b)
    mn = min(r, g, b)
    hue, sat, light = None, 0.0, (mn + mx) / 2
    d = mx - mn
    epsilon = 1 / 100000
    if d != 0:
        sat = 0 if (abs(light) <= epsilon or abs(1 - light) < epsilon) else (mx - light) / min(light, 1 - light)
        if mx == r:
            hue = (g - b) / d + (6 if g < b else 0)
        elif mx == g:
            hue = (b - r) / d + 2
        else:
            hue = (r - g) / d + 4
        hue *= 60
    if sat < 0:
        hue = (hue or 0) + 180
        sat = abs(sat)
    if hue is not None and hue >= 360:
        hue -= 360
    if sat <= epsilon:
        hue = None
        sat = 0
    return [hue, sat * 100, light * 100]


def hwbToRgb(hue, white, black):
    white /= 100
    black /= 100
    if white + black >= 1:
        gray = white / (white + black)
        return [gray, gray, gray]
    rgb = hslToRgb(hue, 100, 50)
    return [c * (1 - white - black) + white for c in rgb]


def rgbToHue(r, g, b):
    mx = max(r, g, b)
    mn = min(r, g, b)
    hue = None
    d = mx - mn
    if d != 0:
        if mx == r:
            hue = (g - b) / d + (6 if g < b else 0)
        elif mx == g:
            hue = (b - r) / d + 2
        else:
            hue = (r - g) / d + 4
        hue *= 60
    if hue is not None and hue >= 360:
        hue -= 360
    return hue


def rgbToHwb(r, g, b):
    epsilon = 1 / 100000
    hue = rgbToHue(r, g, b)
    white = min(r, g, b)
    black = 1 - max(r, g, b)
    if white + black >= 1 - epsilon:
        hue = None
    return [hue, white * 100, black * 100]


# ---------------------------------------------------------------- colour spaces

RGB_SPACES = ['srgb', 'srgb-linear', 'display-p3', 'display-p3-linear', 'a98-rgb', 'prophoto-rgb', 'rec2020',
              'rec2100-pq', 'rec2100-hlg', 'rec2100-linear']
XYZ_SPACES = ['xyz-d50', 'xyz-d65']
POLAR = {'hsl': 0, 'hwb': 0, 'lch': 2, 'oklch': 2, 'jzczhz': 2}
# CSS Color 4 section 13.3: analogous components, by category (Reds, Greens, Blues, Lightness, Colorfulness, Hue,
# Opponent a, Opponent b); HWB's whiteness and blackness have none.  CSS Color HDR names no analogs for its spaces.
_RGB = ['R', 'G', 'B']
ANALOG = {
    'srgb': _RGB, 'srgb-linear': _RGB, 'display-p3': _RGB, 'display-p3-linear': _RGB, 'a98-rgb': _RGB,
    'prophoto-rgb': _RGB, 'rec2020': _RGB, 'rec2100-pq': _RGB, 'rec2100-hlg': _RGB, 'rec2100-linear': _RGB,
    'xyz-d50': _RGB, 'xyz-d65': _RGB,
    'hsl': ['H', 'C', 'L'], 'hwb': ['H', None, None], 'lab': ['L', 'oa', 'ob'], 'lch': ['L', 'C', 'H'],
    'oklab': ['L', 'oa', 'ob'], 'oklch': ['L', 'C', 'H'],
    'jzazbz': [None, None, None], 'jzczhz': [None, None, None], 'ictcp': [None, None, None],
}


def to_xyz_d65(space, c):
    c = [0.0 if v is None else v for v in c]
    if space == 'srgb':
        return mul(M_SRGB_TO_XYZ, lin_sRGB(c))
    if space == 'srgb-linear':
        return mul(M_SRGB_TO_XYZ, c)
    if space == 'display-p3':
        return mul(M_P3_TO_XYZ, lin_sRGB(c))
    if space == 'display-p3-linear':
        return mul(M_P3_TO_XYZ, c)
    if space == 'a98-rgb':
        return mul(M_A98_TO_XYZ, lin_a98rgb(c))
    if space == 'prophoto-rgb':
        return mul(M_D50_TO_D65, mul(M_PROPHOTO_TO_XYZ, lin_ProPhoto(c)))
    if space == 'rec2020':
        return mul(M_2020_TO_XYZ, lin_2020(c))
    if space == 'rec2100-linear':
        return mul(M_2020_TO_XYZ, c)
    if space == 'rec2100-pq':
        return mul(M_2020_TO_XYZ, pq_decode(c))
    if space == 'rec2100-hlg':
        return mul(M_2020_TO_XYZ, hlg_decode(c))
    if space == 'xyz-d65':
        return list(c)
    if space == 'xyz-d50':
        return mul(M_D50_TO_D65, c)
    if space == 'hsl':
        return to_xyz_d65('srgb', hslToRgb(c[0] % 360, c[1], c[2]))
    if space == 'hwb':
        return to_xyz_d65('srgb', hwbToRgb(c[0] % 360, c[1], c[2]))
    if space == 'lab':
        return mul(M_D50_TO_D65, Lab_to_XYZ(c))
    if space == 'lch':
        return to_xyz_d65('lab', from_polar(c))
    if space == 'oklab':
        return OKLab_to_XYZ(c)
    if space == 'oklch':
        return OKLab_to_XYZ(from_polar(c))
    if space == 'jzazbz':
        return Jzazbz_to_XYZ(c)
    if space == 'jzczhz':
        return Jzazbz_to_XYZ(from_polar(c))
    if space == 'ictcp':
        return ICtCp_to_XYZ(c)
    raise ValueError(space)


def from_xyz_d65(space, xyz):
    if space == 'srgb':
        return gam_sRGB(mul(M_XYZ_TO_SRGB, xyz))
    if space == 'srgb-linear':
        return mul(M_XYZ_TO_SRGB, xyz)
    if space == 'display-p3':
        return gam_sRGB(mul(M_XYZ_TO_P3, xyz))
    if space == 'display-p3-linear':
        return mul(M_XYZ_TO_P3, xyz)
    if space == 'a98-rgb':
        return gam_a98rgb(mul(M_XYZ_TO_A98, xyz))
    if space == 'prophoto-rgb':
        return gam_ProPhoto(mul(M_XYZ_TO_PROPHOTO, mul(M_D65_TO_D50, xyz)))
    if space == 'rec2020':
        return gam_2020(mul(M_XYZ_TO_2020, xyz))
    if space == 'rec2100-linear':
        return mul(M_XYZ_TO_2020, xyz)
    if space == 'rec2100-pq':
        return pq_encode(mul(M_XYZ_TO_2020, xyz))
    if space == 'rec2100-hlg':
        return hlg_encode(mul(M_XYZ_TO_2020, xyz))
    if space == 'xyz-d65':
        return list(xyz)
    if space == 'xyz-d50':
        return mul(M_D65_TO_D50, xyz)
    if space == 'hsl':
        return rgbToHsl(*from_xyz_d65('srgb', xyz))
    if space == 'hwb':
        return rgbToHwb(*from_xyz_d65('srgb', xyz))
    if space == 'lab':
        return XYZ_to_Lab(mul(M_D65_TO_D50, xyz))
    if space == 'lch':
        return to_polar(XYZ_to_Lab(mul(M_D65_TO_D50, xyz)), 0.0015)
    if space == 'oklab':
        return XYZ_to_OKLab(xyz)
    if space == 'oklch':
        return to_polar(XYZ_to_OKLab(xyz), 0.000004)
    if space == 'jzazbz':
        return XYZ_to_Jzazbz(xyz)
    if space == 'jzczhz':
        return to_polar(XYZ_to_Jzazbz(xyz), 0.0000026)
    if space == 'ictcp':
        return XYZ_to_ICtCp(xyz)
    raise ValueError(space)


def powerless_to_missing(space, c):
    # CSS Color 4 section 19, powerlessToMissing; jzczhz from CSS Color HDR section 6.5
    out = list(c)
    if space == 'hsl':
        sat = 0 if out[1] is None else out[1]
        if sat <= 0.001:
            out[0] = None
            if out[1] is not None and out[1] > 0:
                out[1] = 0
    elif space == 'hwb':
        w = 0 if out[1] is None else out[1]
        b = 0 if out[2] is None else out[2]
        if w + b >= 99.999:
            out[0] = None
            if w + b < 100:
                if out[1] is None:
                    out[2] = 100
                elif out[2] is None:
                    out[1] = 100
                else:
                    out[2] = 100 - out[1]
    elif space in ('lch', 'oklch', 'jzczhz'):
        eps = {'lch': 0.0015, 'oklch': 0.000004, 'jzczhz': 0.0000026}[space]
        ch = 0 if out[1] is None else out[1]
        if ch <= eps:
            out[2] = None
            if out[1] is not None and out[1] > 0:
                out[1] = 0
    return out


class Color:
    __slots__ = ('space', 'c', 'alpha', 'legacy')

    def __init__(self, space, c, alpha=1.0, legacy=False):
        self.space = space
        self.c = list(c)
        self.alpha = alpha
        self.legacy = legacy

    def __repr__(self):
        return 'Color(%s %s / %s%s)' % (self.space, self.c, self.alpha, ' legacy' if self.legacy else '')

    def xyz(self):
        return to_xyz_d65(self.space, self.c)

    def to(self, space):
        """CSS Color 4 section 11.2, without gamut mapping; missing analogous components carried forward."""
        if space == self.space:
            return Color(space, self.c, self.alpha)
        src = powerless_to_missing(self.space, self.c)
        out = from_xyz_d65(space, to_xyz_d65(self.space, src))
        if space in POLAR:
            out = powerless_to_missing(space, out)
        out = carry_missing(self.space, src, space, out)
        return Color(space, out, self.alpha)


def carry_missing(src_space, src, dst_space, dst):
    """CSS Color 4 section 13.3: analogous components that are missing in the source stay missing, and when every
    component of the analogous set (the components left after removing the analogous ones) is missing, the
    destination's analogous set is missing too."""
    sa = ANALOG.get(src_space, [None] * 3)
    da = ANALOG.get(dst_space, [None] * 3)
    out = list(dst)
    shared = [cat for cat in sa if cat is not None and cat in da]
    for i, cat in enumerate(sa):
        if src[i] is None and cat in shared:
            out[da.index(cat)] = None
    src_set = [i for i, cat in enumerate(sa) if cat not in shared]
    dst_set = [i for i, cat in enumerate(da) if cat not in shared]
    if src_set and dst_set and all(src[i] is None for i in src_set):
        for i in dst_set:
            out[i] = None
    return out


# ---------------------------------------------------------------- gamut mapping, CSS Color 4 section 14.2.2

def delta_eok(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def in_gamut_values(vals, eps=1e-9):
    # eps absorbs the rounding of the matrix round trip (about 1e-15), so that a colour on the gamut boundary,
    # such as white, is not reported as gamut mapped
    return all(-eps <= v <= 1 + eps for v in vals)


def display_values(color, dest):
    """The colour in dest for display: missing components are zero (CSS Color 4 section 4.4), nothing carried."""
    if color.space == dest:
        return [0.0 if v is None else v for v in color.c]
    return from_xyz_d65(dest, color.xyz())


def gamut_map(color, dest):
    """Binary search gamut mapping with local MINDE into the rgb space dest; returns (values, mapped?)."""
    target = display_values(color, dest)
    if in_gamut_values(target):
        return [min(1.0, max(0.0, v)) for v in target], False
    origin = color.to('oklch')
    L, C, H = [0.0 if v is None else v for v in origin.c]
    if L >= 1.0:
        return Color('oklab', [1, 0, 0]).to(dest).c, True
    if L <= 0.0:
        return Color('oklab', [0, 0, 0]).to(dest).c, True
    JND = 0.02
    epsilon = 0.0001

    def clip(v):
        return [min(1.0, max(0.0, x)) for x in v]

    def oklab_of(space, vals):
        return XYZ_to_OKLab(to_xyz_d65(space, vals))

    current = [L, C, H]
    cur_dest = Color('oklch', current).to(dest).c
    clipped = clip(cur_dest)
    E = delta_eok(oklab_of(dest, clipped), XYZ_to_OKLab(to_xyz_d65('oklch', current)))
    if E < JND:
        return clipped, True
    lo, hi = 0.0, C
    min_in_gamut = True
    while hi - lo > epsilon:
        chroma = (lo + hi) / 2
        current = [L, chroma, H]
        cur_dest = Color('oklch', current).to(dest).c
        if min_in_gamut and in_gamut_values(cur_dest):
            lo = chroma
            continue
        clipped = clip(cur_dest)
        E = delta_eok(oklab_of(dest, clipped), XYZ_to_OKLab(to_xyz_d65('oklch', current)))
        if E < JND:
            if JND - E < epsilon:
                return clipped, True
            min_in_gamut = False
            lo = chroma
        else:
            hi = chroma
    return clipped, True


# ---------------------------------------------------------------- tokenizer (CSS Syntax 3, the subset colour values use)

NUM_RE = re.compile(r'[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?')
IDENT_RE = re.compile(r'-?(?:[A-Za-z_]|[^\x00-\x7f]|--)[A-Za-z0-9_\-]*|--[A-Za-z0-9_\-]*')


class Tok:
    __slots__ = ('kind', 'value', 'unit', 'text')

    def __init__(self, kind, value=None, unit=None, text=''):
        self.kind = kind
        self.value = value
        self.unit = unit
        self.text = text

    def __repr__(self):
        return '%s(%r%s)' % (self.kind, self.value, (' ' + self.unit) if self.unit else '')


def tokenize(s):
    toks = []
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch in ' \t\n\r\f':
            while i < n and s[i] in ' \t\n\r\f':
                i += 1
            toks.append(Tok('ws'))
            continue
        if ch == '/' and s.startswith('/*', i):
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if ch == '#':
            m = re.compile(r'#([A-Za-z0-9_\-]+)').match(s, i)
            if m:
                toks.append(Tok('hash', m.group(1)))
                i = m.end()
                continue
            toks.append(Tok('delim', '#'))
            i += 1
            continue
        m = NUM_RE.match(s, i)
        if m and (ch.isdigit() or ch == '.' or (ch in '+-' and i + 1 < n and (s[i + 1].isdigit() or s[i + 1] == '.'))):
            text = m.group(0)
            v = float(text)
            i = m.end()
            if i < n and s[i] == '%':
                toks.append(Tok('percentage', v, text=text))
                i += 1
                continue
            mi = IDENT_RE.match(s, i)
            if mi and not (s[i] in 'eE' and False):
                toks.append(Tok('dimension', v, mi.group(0).lower(), text=text))
                i = mi.end()
                continue
            toks.append(Tok('number', v, text=text))
            continue
        mi = IDENT_RE.match(s, i)
        if mi:
            name = mi.group(0)
            i = mi.end()
            if i < n and s[i] == '(':
                toks.append(Tok('function', name.lower()))
                i += 1
            else:
                toks.append(Tok('ident', name.lower(), text=name))
            continue
        if ch == '(':
            toks.append(Tok('('))
        elif ch == ')':
            toks.append(Tok(')'))
        elif ch == ',':
            toks.append(Tok(','))
        else:
            toks.append(Tok('delim', ch))
        i += 1
    return toks


class Invalid(Exception):
    pass


# ---------------------------------------------------------------- named colours, CSS Color 4 section 6.1

NAMED = {
    'aliceblue': 0xf0f8ff, 'antiquewhite': 0xfaebd7, 'aqua': 0x00ffff, 'aquamarine': 0x7fffd4, 'azure': 0xf0ffff,
    'beige': 0xf5f5dc, 'bisque': 0xffe4c4, 'black': 0x000000, 'blanchedalmond': 0xffebcd, 'blue': 0x0000ff,
    'blueviolet': 0x8a2be2, 'brown': 0xa52a2a, 'burlywood': 0xdeb887, 'cadetblue': 0x5f9ea0,
    'chartreuse': 0x7fff00, 'chocolate': 0xd2691e, 'coral': 0xff7f50, 'cornflowerblue': 0x6495ed,
    'cornsilk': 0xfff8dc, 'crimson': 0xdc143c, 'cyan': 0x00ffff, 'darkblue': 0x00008b, 'darkcyan': 0x008b8b,
    'darkgoldenrod': 0xb8860b, 'darkgray': 0xa9a9a9, 'darkgreen': 0x006400, 'darkgrey': 0xa9a9a9,
    'darkkhaki': 0xbdb76b, 'darkmagenta': 0x8b008b, 'darkolivegreen': 0x556b2f, 'darkorange': 0xff8c00,
    'darkorchid': 0x9932cc, 'darkred': 0x8b0000, 'darksalmon': 0xe9967a, 'darkseagreen': 0x8fbc8f,
    'darkslateblue': 0x483d8b, 'darkslategray': 0x2f4f4f, 'darkslategrey': 0x2f4f4f, 'darkturquoise': 0x00ced1,
    'darkviolet': 0x9400d3, 'deeppink': 0xff1493, 'deepskyblue': 0x00bfff, 'dimgray': 0x696969,
    'dimgrey': 0x696969, 'dodgerblue': 0x1e90ff, 'firebrick': 0xb22222, 'floralwhite': 0xfffaf0,
    'forestgreen': 0x228b22, 'fuchsia': 0xff00ff, 'gainsboro': 0xdcdcdc, 'ghostwhite': 0xf8f8ff, 'gold': 0xffd700,
    'goldenrod': 0xdaa520, 'gray': 0x808080, 'green': 0x008000, 'greenyellow': 0xadff2f, 'grey': 0x808080,
    'honeydew': 0xf0fff0, 'hotpink': 0xff69b4, 'indianred': 0xcd5c5c, 'indigo': 0x4b0082, 'ivory': 0xfffff0,
    'khaki': 0xf0e68c, 'lavender': 0xe6e6fa, 'lavenderblush': 0xfff0f5, 'lawngreen': 0x7cfc00,
    'lemonchiffon': 0xfffacd, 'lightblue': 0xadd8e6, 'lightcoral': 0xf08080, 'lightcyan': 0xe0ffff,
    'lightgoldenrodyellow': 0xfafad2, 'lightgray': 0xd3d3d3, 'lightgreen': 0x90ee90, 'lightgrey': 0xd3d3d3,
    'lightpink': 0xffb6c1, 'lightsalmon': 0xffa07a, 'lightseagreen': 0x20b2aa, 'lightskyblue': 0x87cefa,
    'lightslategray': 0x778899, 'lightslategrey': 0x778899, 'lightsteelblue': 0xb0c4de, 'lightyellow': 0xffffe0,
    'lime': 0x00ff00, 'limegreen': 0x32cd32, 'linen': 0xfaf0e6, 'magenta': 0xff00ff, 'maroon': 0x800000,
    'mediumaquamarine': 0x66cdaa, 'mediumblue': 0x0000cd, 'mediumorchid': 0xba55d3, 'mediumpurple': 0x9370db,
    'mediumseagreen': 0x3cb371, 'mediumslateblue': 0x7b68ee, 'mediumspringgreen': 0x00fa9a,
    'mediumturquoise': 0x48d1cc, 'mediumvioletred': 0xc71585, 'midnightblue': 0x191970, 'mintcream': 0xf5fffa,
    'mistyrose': 0xffe4e1, 'moccasin': 0xffe4b5, 'navajowhite': 0xffdead, 'navy': 0x000080, 'oldlace': 0xfdf5e6,
    'olive': 0x808000, 'olivedrab': 0x6b8e23, 'orange': 0xffa500, 'orangered': 0xff4500, 'orchid': 0xda70d6,
    'palegoldenrod': 0xeee8aa, 'palegreen': 0x98fb98, 'paleturquoise': 0xafeeee, 'palevioletred': 0xdb7093,
    'papayawhip': 0xffefd5, 'peachpuff': 0xffdab9, 'peru': 0xcd853f, 'pink': 0xffc0cb, 'plum': 0xdda0dd,
    'powderblue': 0xb0e0e6, 'purple': 0x800080, 'rebeccapurple': 0x663399, 'red': 0xff0000,
    'rosybrown': 0xbc8f8f, 'royalblue': 0x4169e1, 'saddlebrown': 0x8b4513, 'salmon': 0xfa8072,
    'sandybrown': 0xf4a460, 'seagreen': 0x2e8b57, 'seashell': 0xfff5ee, 'sienna': 0xa0522d, 'silver': 0xc0c0c0,
    'skyblue': 0x87ceeb, 'slateblue': 0x6a5acd, 'slategray': 0x708090, 'slategrey': 0x708090, 'snow': 0xfffafa,
    'springgreen': 0x00ff7f, 'steelblue': 0x4682b4, 'tan': 0xd2b48c, 'teal': 0x008080, 'thistle': 0xd8bfd8,
    'tomato': 0xff6347, 'turquoise': 0x40e0d0, 'violet': 0xee82ee, 'wheat': 0xf5deb3, 'white': 0xffffff,
    'whitesmoke': 0xf5f5f5, 'yellow': 0xffff00, 'yellowgreen': 0x9acd32,
}
# CSS Color 4 section 6.2 and Appendix A; values come from the context (the platform's palette)
SYSTEM_COLORS = ['accentcolor', 'accentcolortext', 'activetext', 'buttonborder', 'buttonface', 'buttontext',
                 'canvas', 'canvastext', 'field', 'fieldtext', 'graytext', 'highlight', 'highlighttext', 'linktext',
                 'mark', 'marktext', 'selecteditem', 'selecteditemtext', 'visitedtext']
DEPRECATED_SYSTEM = {'activeborder': 'buttonborder', 'activecaption': 'canvas', 'appworkspace': 'canvas',
                     'background': 'canvas', 'buttonhighlight': 'buttonface', 'buttonshadow': 'buttonface',
                     'captiontext': 'canvastext', 'inactiveborder': 'buttonborder', 'inactivecaption': 'canvas',
                     'inactivecaptiontext': 'graytext', 'infobackground': 'canvas', 'infotext': 'canvastext',
                     'menu': 'canvas', 'menutext': 'canvastext', 'scrollbar': 'canvas',
                     'threeddarkshadow': 'buttonborder', 'threedface': 'buttonface',
                     'threedhighlight': 'buttonborder', 'threedlightshadow': 'buttonborder',
                     'threedshadow': 'buttonborder', 'window': 'canvas', 'windowframe': 'buttonborder',
                     'windowtext': 'canvastext'}


def rgb8(v, alpha=1.0):
    return Color('srgb', [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255], alpha, legacy=True)


class Context:
    def __init__(self, current=None, system=None, dark=False, headroom=0.0, noclamp=False):
        self.noclamp = noclamp  # parse a serialized computed value, which keeps what parsing would clamp
        self.current = current or rgb8(0x000000)
        self.system = system or {}
        self.dark = dark
        self.headroom = headroom


# ---------------------------------------------------------------- math functions (CSS Values 4 section 10), typed

class Num:
    """A calculated value: v in canonical units; t is 'number', 'percentage' or 'angle' (degrees)."""
    __slots__ = ('v', 't')

    def __init__(self, v, t):
        self.v = v
        self.t = t


ANGLE = {'deg': 1.0, 'grad': 0.9, 'rad': 180 / math.pi, 'turn': 360.0}
MATH_FUNCS = {'calc', 'min', 'max', 'clamp', 'round', 'mod', 'rem', 'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
              'atan2', 'pow', 'sqrt', 'hypot', 'log', 'exp', 'abs', 'sign'}


class Parser:
    def __init__(self, toks, ctx):
        self.t = toks
        self.i = 0
        self.ctx = ctx

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else Tok('eof')

    def next(self):
        tok = self.peek()
        self.i += 1
        return tok

    def ws(self):
        while self.peek().kind == 'ws':
            self.i += 1

    def expect(self, kind):
        self.ws()
        tok = self.next()
        if tok.kind != kind:
            raise Invalid('expected %s, found %r' % (kind, tok))
        return tok

    def at(self, kind, value=None):
        self.ws()
        tok = self.peek()
        return tok.kind == kind and (value is None or tok.value == value)

    # --- calc
    def math_value(self, chans):
        """One math term: number, percentage, dimension, constant, channel keyword, ( ... ) or function."""
        self.ws()
        tok = self.next()
        if tok.kind == 'number':
            return Num(tok.value, 'number')
        if tok.kind == 'percentage':
            return Num(tok.value, 'percentage')
        if tok.kind == 'dimension':
            if tok.unit in ANGLE:
                return Num(tok.value * ANGLE[tok.unit], 'angle')
            raise Invalid('unit %s' % tok.unit)
        if tok.kind == 'ident':
            if chans is not None and tok.value in chans:
                v = chans[tok.value]
                return Num(0.0 if v is None else v, 'number')
            consts = {'e': math.e, 'pi': math.pi, 'infinity': math.inf, '-infinity': -math.inf, 'nan': math.nan}
            if tok.value in consts:
                return Num(consts[tok.value], 'number')
            raise Invalid('ident %s in math' % tok.value)
        if tok.kind == '(':
            v = self.math_sum(chans)
            self.expect(')')
            return v
        if tok.kind == 'function' and tok.value in MATH_FUNCS:
            return self.math_function(tok.value, chans)
        raise Invalid('math term %r' % tok)

    def math_product(self, chans):
        v = self.math_value(chans)
        while True:
            save = self.i
            self.ws()
            tok = self.peek()
            if tok.kind == 'delim' and tok.value in '*/':
                self.next()
                w = self.math_value(chans)
                if tok.value == '*':
                    if v.t != 'number' and w.t != 'number':
                        raise Invalid('product of two dimensions')
                    v = Num(v.v * w.v, w.t if v.t == 'number' else v.t)
                else:
                    if w.t != 'number' and w.t != v.t:
                        raise Invalid('division by a dimension')
                    t = 'number' if w.t == v.t else v.t
                    v = Num(v.v / w.v if w.v != 0 else math.copysign(math.inf, v.v) if v.v != 0 else math.nan, t)
            else:
                self.i = save
                return v

    def math_sum(self, chans):
        v = self.math_product(chans)
        while True:
            save = self.i
            had_ws = self.peek().kind == 'ws'
            self.ws()
            tok = self.peek()
            if tok.kind == 'delim' and tok.value in '+-' and had_ws and self.i + 1 < len(self.t) and self.t[self.i + 1].kind == 'ws':
                self.next()
                w = self.math_product(chans)
                if w.t != v.t:
                    raise Invalid('sum of %s and %s' % (v.t, w.t))
                v = Num(v.v + w.v if tok.value == '+' else v.v - w.v, v.t)
            elif tok.kind in ('number', 'percentage', 'dimension') and had_ws and tok.text[:1] in '+-':
                raise Invalid('operator needs whitespace')
            else:
                self.i = save
                return v

    def math_args(self, chans):
        args = [self.math_sum(chans)]
        while self.at(','):
            self.next()
            args.append(self.math_sum(chans))
        self.expect(')')
        return args

    def math_function(self, name, chans):
        if name == 'round':
            strategy = 'nearest'
            self.ws()
            if self.peek().kind == 'ident' and self.peek().value in ('nearest', 'up', 'down', 'to-zero'):
                strategy = self.next().value
                self.expect(',')
            args = self.math_args(chans)
            a = args[0]
            b = args[1] if len(args) > 1 else Num(1.0, 'number')
            if b.v == 0:
                return Num(math.nan, a.t)
            q = a.v / b.v
            r = {'nearest': math.floor(q + 0.5), 'up': math.ceil(q), 'down': math.floor(q), 'to-zero': math.trunc(q)}[strategy]
            return Num(r * b.v, a.t)
        args = self.math_args(chans)

        def same(*xs):
            if any(x.t != xs[0].t for x in xs):
                raise Invalid('mixed types in %s' % name)
            return xs[0].t

        def rad(x):
            if x.t == 'angle':
                return math.radians(x.v)
            if x.t == 'number':
                return x.v
            raise Invalid('trig of percentage')
        if name == 'calc':
            if len(args) != 1:
                raise Invalid('calc arity')
            return args[0]
        if name in ('min', 'max'):
            t = same(*args)
            return Num((min if name == 'min' else max)(a.v for a in args), t)
        if name == 'clamp':
            t = same(*args)
            lo, val, hi = [a.v for a in args]
            return Num(max(lo, min(val, hi)), t)
        if name in ('mod', 'rem'):
            t = same(*args)
            a, b = args[0].v, args[1].v
            if b == 0:
                return Num(math.nan, t)
            return Num(a - b * (math.floor(a / b) if name == 'mod' else math.trunc(a / b)), t)
        if name in ('sin', 'cos', 'tan'):
            return Num(getattr(math, name)(rad(args[0])), 'number')
        if name in ('asin', 'acos', 'atan'):
            if args[0].t != 'number':
                raise Invalid('inverse trig of dimension')
            try:
                return Num(math.degrees(getattr(math, name)(args[0].v)), 'angle')
            except ValueError:
                return Num(math.nan, 'angle')
        if name == 'atan2':
            same(*args)
            return Num(math.degrees(math.atan2(args[0].v, args[1].v)), 'angle')
        if name == 'pow':
            if args[0].t != 'number' or args[1].t != 'number':
                raise Invalid('pow of dimension')
            return Num(args[0].v ** args[1].v, 'number')
        if name == 'sqrt':
            return Num(math.sqrt(args[0].v) if args[0].v >= 0 else math.nan, 'number')
        if name == 'hypot':
            t = same(*args)
            return Num(math.hypot(*[a.v for a in args]), t)
        if name == 'log':
            base = args[1].v if len(args) > 1 else math.e
            return Num(math.log(args[0].v, base) if args[0].v > 0 else (-math.inf if args[0].v == 0 else math.nan), 'number')
        if name == 'exp':
            return Num(math.exp(args[0].v), 'number')
        if name == 'abs':
            return Num(abs(args[0].v), args[0].t)
        if name == 'sign':
            v = args[0].v
            return Num(0.0 if v == 0 else math.copysign(1.0, v), 'number')
        raise Invalid(name)

    # --- components
    def component(self, chans, allow_pct=True, hue=False, allow_none=True):
        """Returns (value, kind) with kind 'number', 'percentage', 'angle' or 'none'."""
        self.ws()
        tok = self.peek()
        if tok.kind == 'ident' and tok.value == 'none':
            if not allow_none:
                raise Invalid('none not allowed')
            self.next()
            return None, 'none'
        if tok.kind == 'ident' and chans is not None and tok.value in chans:
            self.next()
            v = chans[tok.value]
            return v, ('none' if v is None else 'number')
        if tok.kind == 'function' and tok.value in MATH_FUNCS:
            self.next()
            v = self.math_function(tok.value, chans)
        elif tok.kind in ('number', 'percentage', 'dimension'):
            self.next()
            if tok.kind == 'dimension':
                if not hue or tok.unit not in ANGLE:
                    raise Invalid('dimension %s' % tok.unit)
                v = Num(tok.value * ANGLE[tok.unit], 'angle')
            else:
                v = Num(tok.value, tok.kind)
        else:
            raise Invalid('component %r' % tok)
        if v.t == 'percentage' and not allow_pct:
            raise Invalid('percentage not allowed')
        if v.t == 'angle' and not hue:
            raise Invalid('angle not allowed')
        val = v.v
        if math.isnan(val):
            val = 0.0
        return val, v.t

    def alpha_part(self, chans, origin_alpha=None):
        """[ / [<alpha-value> | none] ]? ; returns the alpha (None when 'none')."""
        if self.at('delim', '/'):
            self.next()
            v, k = self.component(chans)
            if k == 'none':
                return None
            if k == 'percentage':
                v /= 100
            if k == 'angle':
                raise Invalid('angle alpha')
            if math.isinf(v):
                v = 1.0 if v > 0 else 0.0
            return min(1.0, max(0.0, v))
        if origin_alpha is not None:
            return origin_alpha[0]
        return 1.0

    # --- <color>
    def color(self):
        self.ws()
        tok = self.next()
        ctx = self.ctx
        if tok.kind == 'hash':
            return parse_hex(tok.value)
        if tok.kind == 'ident':
            name = tok.value
            if name in NAMED:
                return rgb8(NAMED[name])
            if name == 'transparent':
                return Color('srgb', [0, 0, 0], 0.0, legacy=True)
            if name == 'currentcolor':
                c = ctx.current
                return Color(c.space, c.c, c.alpha, c.legacy)
            if name in SYSTEM_COLORS or name in DEPRECATED_SYSTEM:
                key = DEPRECATED_SYSTEM.get(name, name)
                if key not in ctx.system:
                    raise Invalid('system colour %s has no value in this context' % name)
                c = ctx.system[key]
                return Color(c.space, c.c, c.alpha, c.legacy)
            raise Invalid('unknown colour name %s' % name)
        if tok.kind == 'function':
            f = tok.value
            if f in ('rgb', 'rgba'):
                return self.rgb_function()
            if f in ('hsl', 'hsla'):
                return self.hsl_function()
            if f == 'hwb':
                return self.modern_function('hwb')
            if f in ('lab', 'lch', 'oklab', 'oklch', 'ictcp', 'jzazbz', 'jzczhz'):
                return self.modern_function(f)
            if f == 'color':
                return self.color_function()
            if f == 'color-mix':
                return self.color_mix()
            if f == 'alpha':
                return self.alpha_function()
            if f == 'light-dark':
                a = self.color()
                self.expect(',')
                b = self.color()
                self.expect(')')
                return b if ctx.dark else a
            if f == 'contrast-color':
                c = self.color()
                self.expect(')')
                return contrast_color(c)
            if f == 'device-cmyk':
                return self.device_cmyk()
            if f in ('hdr-color', 'color-hdr'):
                return self.hdr_color()
        raise Invalid('not a colour: %r' % tok)

    def origin(self):
        """from <color>, for relative colour syntax; returns the origin Color or None."""
        if self.at('ident', 'from'):
            self.next()
            return self.color()
        return None

    def rgb_function(self):
        origin = self.origin()
        save = self.i
        if origin is None:
            # legacy syntax: comma separated, all numbers or all percentages, no none
            try:
                return self.rgb_legacy()
            except Invalid:
                self.i = save
        chans = None
        oalpha = None
        if origin is not None:
            o = origin.to('srgb')
            chans = {'r': none_scale(o.c[0], 255), 'g': none_scale(o.c[1], 255), 'b': none_scale(o.c[2], 255),
                     'alpha': origin.alpha}
            oalpha = (origin.alpha,)
        vals = []
        for _ in range(3):
            v, k = self.component(chans)
            if k == 'percentage':
                v = v * 255 / 100
            vals.append(v)
        alpha = self.alpha_part(chans, oalpha)
        self.expect(')')
        c = [None if v is None else v / 255 for v in vals]
        if origin is None:
            c = [None if v is None else min(1.0, max(0.0, v)) for v in c]
            return Color('srgb', c, alpha, legacy=(None not in c and alpha is not None))
        c = carry_rel(origin, 'srgb', c)
        return Color('srgb', c, alpha)

    def rgb_legacy(self):
        vals = []
        kinds = []
        for i in range(3):
            if i:
                self.expect(',')
            self.ws()
            tok = self.peek()
            if tok.kind == 'ident':
                raise Invalid('legacy keyword')
            v, k = self.component(None, allow_none=False)
            vals.append(v)
            kinds.append(k)
        if len(set(kinds)) != 1:
            raise Invalid('mixed legacy rgb')
        alpha = 1.0
        if self.at(','):
            self.next()
            v, k = self.component(None, allow_none=False)
            alpha = v / 100 if k == 'percentage' else v
            alpha = min(1.0, max(0.0, alpha))
        self.expect(')')
        if kinds[0] == 'percentage':
            vals = [v * 255 / 100 for v in vals]
        return Color('srgb', [min(1.0, max(0.0, v / 255)) for v in vals], alpha, legacy=True)

    def hsl_function(self):
        origin = self.origin()
        save = self.i
        if origin is None:
            try:
                h, _ = self.component(None, allow_pct=False, hue=True, allow_none=False)
                self.expect(',')
                s, ks = self.component(None, allow_none=False)
                self.expect(',')
                l, kl = self.component(None, allow_none=False)
                if ks != 'percentage' or kl != 'percentage':
                    raise Invalid('legacy hsl needs percentages')
                alpha = 1.0
                if self.at(','):
                    self.next()
                    v, k = self.component(None, allow_none=False)
                    alpha = min(1.0, max(0.0, v / 100 if k == 'percentage' else v))
                self.expect(')')
                return Color('hsl', [h % 360, max(0.0, s), l], alpha, legacy=True)
            except Invalid:
                self.i = save
        return self.modern_function('hsl', origin, legacy_ok=True)

    def modern_function(self, f, origin=None, legacy_ok=False):
        if origin is None:
            origin = self.origin()
        # percentage reference ranges and clamps, CSS Color 4 sections 7 to 9, CSS Color HDR section 6
        spec = {
            'hsl': [(None, 'hue'), (100, None), (100, None)],
            'hwb': [(None, 'hue'), (100, None), (100, None)],
            'lab': [(100, (0, 100)), (125, None), (125, None)],
            'lch': [(100, (0, 100)), (150, (0, None)), (None, 'hue')],
            'oklab': [(1, (0, 1)), (0.4, None), (0.4, None)],
            'oklch': [(1, (0, 1)), (0.4, (0, None)), (None, 'hue')],
            'ictcp': [(1, None), (0.5, None), (0.5, None)],
            'jzazbz': [(1, None), (0.21, None), (0.21, None)],
            'jzczhz': [(1, None), (0.26, None), (None, 'hue')],
        }[f]
        names = {'hsl': 'hsl', 'hwb': 'hwb', 'lab': 'lab', 'lch': 'lch', 'oklab': 'lab', 'oklch': 'lch',
                 'ictcp': ['i', 'ct', 'cp'], 'jzazbz': ['j', 'a', 'b'], 'jzczhz': ['j', 'c', 'h']}[f]
        if isinstance(names, str):
            names = list(names)
        chans = None
        oalpha = None
        if origin is not None:
            o = origin.to(f)
            chans = dict(zip(names, o.c))
            chans['alpha'] = origin.alpha
            oalpha = (origin.alpha,)
        vals = []
        for i, (ref, rule) in enumerate(spec):
            hue = rule == 'hue'
            v, k = self.component(chans, allow_pct=not hue, hue=hue)
            if k == 'percentage':
                v = v * ref / 100
            if hue and v is not None:
                v = v % 360 if not math.isinf(v) else 0.0
            if (origin is None or f in ('lab', 'lch', 'oklab', 'oklch')) and isinstance(rule, tuple) and v is not None and not self.ctx.noclamp:
                lo, hi = rule
                if lo is not None:
                    v = max(lo, v)
                if hi is not None:
                    v = min(hi, v)
            if origin is None and f in ('hsl',) and i == 1 and v is not None and not self.ctx.noclamp:
                v = max(0.0, v)
            vals.append(v)
        alpha = self.alpha_part(chans, oalpha)
        self.expect(')')
        if origin is not None:
            vals = carry_rel(origin, f, vals)
        return Color(f, vals, alpha)

    def color_function(self):
        origin = self.origin()
        self.ws()
        tok = self.next()
        if tok.kind != 'ident':
            raise Invalid('color() needs a colour space')
        space = tok.value
        if space == 'xyz':
            space = 'xyz-d65'
        if space not in RGB_SPACES and space not in XYZ_SPACES:
            raise Invalid('unknown colour space %s' % space)
        chans = None
        oalpha = None
        if origin is not None:
            o = origin.to(space)
            names = ['x', 'y', 'z'] if space in XYZ_SPACES else ['r', 'g', 'b']
            chans = dict(zip(names, o.c))
            chans['alpha'] = origin.alpha
            oalpha = (origin.alpha,)
        vals = []
        for _ in range(3):
            v, k = self.component(chans)
            if k == 'percentage':
                v = v / 100
            vals.append(v)
        alpha = self.alpha_part(chans, oalpha)
        self.expect(')')
        if origin is not None:
            vals = carry_rel(origin, space, vals)
        return Color(space, vals, alpha)

    def alpha_function(self):
        origin = self.origin()
        if origin is None:
            raise Invalid('alpha() needs an origin')
        chans = {'alpha': origin.alpha}
        if not self.at('delim', '/'):
            raise Invalid('alpha() needs / alpha')
        alpha = self.alpha_part(chans, (origin.alpha,))
        self.expect(')')
        return Color(origin.space, origin.c, alpha)

    def device_cmyk(self):
        vals = []
        save = self.i
        try:
            for i in range(4):
                if i:
                    self.expect(',')
                v, k = self.component(None, allow_pct=False, allow_none=False)
                vals.append(v)
            self.expect(')')
            alpha = 1.0
        except Invalid:
            self.i = save
            vals = []
            for _ in range(4):
                v, k = self.component(None)
                if k == 'percentage':
                    v /= 100
                vals.append(v)
            alpha = self.alpha_part(None)
            self.expect(')')
        c, m, y, k = [min(1.0, max(0.0, 0.0 if v is None else v)) for v in vals]
        # CSS Color 5 section 6.1, naive conversion (no @color-profile for device-cmyk)
        r = 1 - min(1, c * (1 - k) + k)
        g = 1 - min(1, m * (1 - k) + k)
        b = 1 - min(1, y * (1 - k) + k)
        return Color('srgb', [r, g, b], alpha)

    def color_mix(self):
        space, hue_method = 'oklab', 'shorter'
        if self.at('ident', 'in'):
            self.next()
            self.ws()
            tok = self.next()
            if tok.kind != 'ident':
                raise Invalid('color-mix space')
            space = tok.value
            if space == 'xyz':
                space = 'xyz-d65'
            rect = ['srgb', 'srgb-linear', 'display-p3', 'display-p3-linear', 'a98-rgb', 'prophoto-rgb', 'rec2020',
                    'lab', 'oklab', 'xyz-d50', 'xyz-d65']
            polar = ['hsl', 'hwb', 'lch', 'oklch']
            if space not in rect and space not in polar:
                raise Invalid('interpolation space %s' % space)
            if space in polar and self.at('ident') and self.peek().value in ('shorter', 'longer', 'increasing', 'decreasing'):
                hue_method = self.next().value
                if not self.at('ident', 'hue'):
                    raise Invalid('hue keyword')
                self.next()
            self.expect(',')
        items = []
        while True:
            pct = None
            self.ws()
            if self.peek().kind == 'percentage' or (self.peek().kind == 'function' and self.peek().value in MATH_FUNCS):
                pct = self.mix_pct()
                col = self.color()
            else:
                col = self.color()
                self.ws()
                if self.peek().kind == 'percentage' or (self.peek().kind == 'function' and self.peek().value in MATH_FUNCS):
                    pct = self.mix_pct()
            items.append([col, pct])
            if self.at(','):
                self.next()
                continue
            self.expect(')')
            break
        return mix(items, space, hue_method)

    def mix_pct(self):
        # <percentage [0,100]>: a literal outside the range is invalid, a math function's result is clamped
        literal = self.peek().kind == 'percentage'
        v, k = self.component(None, allow_none=False)
        if k != 'percentage':
            raise Invalid('mix percentage')
        if literal and (v < 0 or v > 100):
            raise Invalid('mix percentage range')
        return min(100.0, max(0.0, v))

    def hdr_color(self):
        items = []
        for i in range(2):
            if i:
                self.expect(',')
            self.ws()
            h = None
            if self.peek().kind == 'number':
                h = self.next().value
                col = self.color()
            else:
                col = self.color()
                self.ws()
                if self.peek().kind == 'number':
                    h = self.next().value
            if h is not None and h < 0:
                raise Invalid('negative headroom')
            items.append((col, 0.0 if h is None else h))
        self.expect(')')
        (c1, h1), (c2, h2) = items
        if h1 == h2:
            raise Invalid('hdr-color() headrooms must differ')
        return hdr_mix(c1, h1, c2, h2, self.ctx.headroom)


def none_scale(v, k):
    return None if v is None else v * k


def carry_rel(origin, space, vals):
    """CSS Color 5 section 4.1: analogous components missing in the origin stay missing."""
    return vals


def parse_hex(h):
    if not re.fullmatch(r'[0-9a-fA-F]+', h) or len(h) not in (3, 4, 6, 8):
        raise Invalid('hex colour #%s' % h)
    if len(h) in (3, 4):
        h = ''.join(ch * 2 for ch in h)
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    a = int(h[6:8], 16) / 255 if len(h) == 8 else 1.0
    return Color('srgb', [r / 255, g / 255, b / 255], a, legacy=True)


def contrast_color(c):
    """CSS Color 5 section 8: white or black, whichever has the larger contrast; white on a tie.
    The algorithm is UA-defined; this uses WCAG 2.1 relative luminance from the gamut-mapped sRGB value."""
    rgb, _ = gamut_map(Color(c.space, c.c, 1.0), 'srgb')
    lum = mul(M_SRGB_TO_XYZ, lin_sRGB(rgb))[1]
    white = 1.05 / (lum + 0.05)
    black = (lum + 0.05) / 0.05
    return rgb8(0xffffff) if white >= black else rgb8(0x000000)


def hdr_mix(c1, H1, c2, H2, H):
    """CSS Color HDR sections 5.1 and 11.6: interpolate in absolute D65 XYZ by headroom."""
    x1 = [v * YW for v in c1.xyz()]
    x2 = [v * YW for v in c2.xyz()]
    w1 = min(1, max(0, (H - H2) / (H1 - H2)))
    w2 = min(1, max(0, (H - H1) / (H2 - H1)))
    eps = 0.001
    out = [(x1[i] + eps) ** w1 * (x2[i] + eps) ** w2 - eps for i in range(3)]
    a1 = 1.0 if c1.alpha is None else c1.alpha
    a2 = 1.0 if c2.alpha is None else c2.alpha
    return Color('xyz-d65', [v / YW for v in out], a1 * w1 + a2 * w2)


def normalize_mix(items, force):
    """CSS Values 5 section 6.1, normalizing mix percentages."""
    specified = sum(p for _, p in items if p is not None)
    specified_c = min(specified, 100)
    omitted = [it for it in items if it[1] is None]
    out = []
    for col, p in items:
        if p is None:
            p = (100 - specified_c) / len(omitted)
        out.append([col, p])
    total = sum(p for _, p in out)
    if total > 100 or (total > 0 and force):
        out = [[c, p * 100 / total] for c, p in out]
    leftover = 100 - total if total < 100 else 0
    return out, leftover


def mix(items, space, hue_method):
    """CSS Color 5 section 3.3."""
    items, leftover = normalize_mix(items, True)
    alpha_mult = 1 - leftover / 100
    if len(items) == 1:
        col = items[0][0].to(space)
    else:
        stack = list(reversed(items))
        while len(stack) >= 2:
            a = stack.pop()
            b = stack.pop()
            combined = a[1] + b[1]
            progress = b[1] / combined if combined > 0 else 0.5
            stack.append([interpolate(a[0], b[0], progress, space, hue_method), combined])
        col = stack[0][0]
    alpha = None if col.alpha is None else col.alpha * alpha_mult
    return Color(col.space, col.c, alpha)


def interpolate(a, b, p, space, hue_method='shorter'):
    """CSS Color 4 section 13: missing components, premultiplication, hue fix-up, linear interpolation."""
    ca = a.to(space)
    cb = b.to(space)
    va, vb = list(ca.c), list(cb.c)
    aa, ab = a.alpha, b.alpha
    for i in range(3):
        if va[i] is None and vb[i] is not None:
            va[i] = vb[i]
        elif vb[i] is None and va[i] is not None:
            vb[i] = va[i]
    if aa is None and ab is not None:
        aa = ab
    elif ab is None and aa is not None:
        ab = aa
    hi = POLAR.get(space)
    if hi is not None and va[hi] is not None and vb[hi] is not None:
        t1, t2 = va[hi] % 360, vb[hi] % 360
        d = t2 - t1
        if hue_method == 'shorter':
            if d > 180:
                t1 += 360
            elif d < -180:
                t2 += 360
        elif hue_method == 'longer':
            if 0 < d < 180:
                t1 += 360
            elif -180 < d <= 0:
                t2 += 360
        elif hue_method == 'increasing':
            if t2 < t1:
                t2 += 360
        elif hue_method == 'decreasing':
            if t1 < t2:
                t1 += 360
        va[hi], vb[hi] = t1, t2

    def premul(v, al):
        if al is None:
            return v
        return [x if (x is None or i == hi) else x * al for i, x in enumerate(v)]
    pa, pb = premul(va, aa), premul(vb, ab)
    out = []
    for i in range(3):
        if pa[i] is None or pb[i] is None:
            out.append(None)
        else:
            out.append(pa[i] * (1 - p) + pb[i] * p)
    alpha = None if aa is None else aa * (1 - p) + ab * p
    if alpha is not None and alpha != 0:
        out = [x if (x is None or i == hi) else x / alpha for i, x in enumerate(out)]
    if hi is not None and out[hi] is not None:
        out[hi] %= 360
    return Color(space, out, alpha)


def parse(s, ctx=None):
    p = Parser(tokenize(s), ctx or Context())
    c = p.color()
    p.ws()
    if p.peek().kind != 'eof':
        raise Invalid('trailing input %r' % p.peek())
    return c


# ---------------------------------------------------------------- what a renderer must draw

def target_value(color, target_space, bounded):
    """The value a renderer stores for color in a target of target_space (an rgb space of RGB_SPACES).
    bounded: the target holds [0, 1] only (unorm formats); then CSS Color 4 section 14.2 gamut mapping applies.
    Returns (rgb, alpha, mapped)."""
    alpha = 1.0 if color.alpha is None else color.alpha
    if bounded:
        rgb, mapped = gamut_map(color, target_space)
        return [min(1.0, max(0.0, v)) for v in rgb], alpha, mapped
    return display_values(color, target_space), alpha, False
