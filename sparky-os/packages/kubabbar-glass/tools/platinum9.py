#!/usr/bin/env python3
"""Kubabbar Glass 9's colours in one place: the classic greys and the accent variations, read by the colour schemes
(make_colors9.py), the Kvantum themes (make_kvantum9.py) and the decoration and Plasma style (draw_theme9.py).
Original values chosen in the spirit of Mac OS 9's Platinum appearance; no colour is sampled from Apple's artwork.
GPL-3.0-only."""

FACE = (221, 221, 221)          # window, button and panel face
FACE_ALT = (204, 204, 204)      # the alternate face (inactive tabs, a sorted header)
LIGHT = (255, 255, 255)         # bevel light
SHADOW = (153, 153, 153)        # bevel shadow
DARK = (119, 119, 119)          # deeper shadow (sunken edges, grips)
OUTLINE = (30, 30, 30)          # control outlines
VIEW = (255, 255, 255)          # document and list backgrounds
VIEW_ALT = (242, 242, 242)      # alternate rows
TRACK = (198, 198, 198)         # scroll and progress tracks
PRESSED = (102, 102, 102)       # a pressed push button's face (white text on it reads at 5.7:1)
DISABLED_LINE = (160, 160, 160)
TOOLTIP = (255, 255, 230)
TEXT = (0, 0, 0)
TEXT_INACTIVE = (80, 80, 80)    # 4.5:1 or more on FACE and FACE_ALT (looks-texts-readable)
WALLPAPER = (170, 170, 222)     # the desktop's light periwinkle, light enough for dark text through the glass

# The accent variations, the classic Appearance panel's idea: the accent colours the menu highlight, the progress bar,
# the scroll box and the slider; its light form is the text highlight. The first is the default. Each entry:
# accent (white text on it), light (black text on it), mid (scroll box and slider faces), dark (grips and focus).
ACCENTS = {
    "lavender": {"accent": (84, 84, 168), "light": (204, 204, 255), "mid": (153, 153, 221), "dark": (51, 51, 119)},
    "graphite": {"accent": (88, 94, 104), "light": (214, 216, 222), "mid": (160, 166, 176), "dark": (54, 58, 66)},
    "ivy": {"accent": (46, 104, 46), "light": (204, 232, 204), "mid": (138, 190, 138), "dark": (30, 72, 30)},
    "rose": {"accent": (152, 50, 94), "light": (246, 206, 222), "mid": (222, 150, 180), "dark": (104, 30, 62)},
    "gold": {"accent": (122, 90, 6), "light": (244, 228, 176), "mid": (214, 184, 96), "dark": (84, 62, 4)},
    "teal": {"accent": (30, 100, 108), "light": (198, 230, 232), "mid": (122, 186, 192), "dark": (22, 70, 76)},
}
DEFAULT_ACCENT = "lavender"

# Each accent's name in the ten languages (a plain colour word, never a product's name).
ACCENT_NAMES = {
    "lavender": {"en": "Lavender", "pl": "Lawendowy", "pt_BR": "Lavanda", "fr": "Lavande", "de": "Lavendel",
                 "es": "Lavanda", "ja": "ラベンダー", "ko": "라벤더", "zh_CN": "薰衣草紫", "zh_TW": "薰衣草紫"},
    "graphite": {"en": "Graphite", "pl": "Grafitowy", "pt_BR": "Grafite", "fr": "Graphite", "de": "Graphit",
                 "es": "Grafito", "ja": "グラファイト", "ko": "그래파이트", "zh_CN": "石墨灰", "zh_TW": "石墨灰"},
    "ivy": {"en": "Ivy", "pl": "Bluszczowy", "pt_BR": "Hera", "fr": "Lierre", "de": "Efeu",
            "es": "Hiedra", "ja": "アイビー", "ko": "아이비", "zh_CN": "常春藤绿", "zh_TW": "常春藤綠"},
    "rose": {"en": "Rose", "pl": "Różany", "pt_BR": "Rosa", "fr": "Rose", "de": "Rosé",
             "es": "Rosa", "ja": "ローズ", "ko": "로즈", "zh_CN": "玫瑰粉", "zh_TW": "玫瑰粉"},
    "gold": {"en": "Gold", "pl": "Złoty", "pt_BR": "Dourado", "fr": "Or", "de": "Gold",
             "es": "Dorado", "ja": "ゴールド", "ko": "골드", "zh_CN": "金色", "zh_TW": "金色"},
    "teal": {"en": "Teal", "pl": "Morski", "pt_BR": "Azul-petróleo", "fr": "Bleu canard", "de": "Petrol",
             "es": "Verde azulado", "ja": "ティール", "ko": "틸", "zh_CN": "青色", "zh_TW": "青色"},
}
LANGUAGES = ("en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW")


def scheme_id(accent):
    return "kubabbar-glass-9" if accent == DEFAULT_ACCENT else f"kubabbar-glass-9-{accent}"


def kvantum_name(accent, together=True):
    base = "KubabbarGlass9" + ("" if accent == DEFAULT_ACCENT else accent.capitalize())
    return base if together else base + "Apart"


def hexa(rgb):
    return "#%02x%02x%02x" % tuple(rgb)


def lum(rgb):
    lin = [(c / 255) / 12.92 if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

# The Plasma style's texts, read over its translucent surfaces as seen over the wallpaper: these twelve stood under
# 4.5:1 on the top and side panels (44) and the alternate applet background (60); moved in lightness only, hues kept,
# by the stereo-artwork skill's readable_colours.py (4.55 at each one's worst surface). Only the Plasma style takes them.
STYLE_OVERRIDES = {
    ("Window", "ForegroundInactive"): (68, 68, 68), ("Window", "ForegroundNegative"): (140, 6, 0),
    ("Window", "ForegroundNeutral"): (95, 60, 1), ("Window", "ForegroundPositive"): (0, 80, 0),
    ("View", "ForegroundInactive"): (70, 70, 70), ("View", "ForegroundNegative"): (144, 6, 1),
    ("View", "ForegroundNeutral"): (99, 63, 0), ("View", "ForegroundPositive"): (1, 83, 1),
    ("Button", "ForegroundInactive"): (68, 68, 68), ("Button", "ForegroundNegative"): (140, 6, 0),
    ("Button", "ForegroundNeutral"): (95, 60, 1), ("Button", "ForegroundPositive"): (0, 80, 0),
}
