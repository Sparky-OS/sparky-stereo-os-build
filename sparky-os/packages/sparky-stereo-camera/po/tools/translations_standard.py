# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The kernel's standard control, menu and pixel format names (English source = the kernel's own description), keyed by the
# constant of linux/videodev2.h. Order: de, es, fr, ja, ko, pl, pt_BR, zh_CN, zh_TW.
# No established translation was found: v4l-utils' catalogues (de, fr, pt_BR, ca, uk) hold command line messages, not control names.
S = {
"V4L2_CID_BRIGHTNESS|Brightness": ("Helligkeit", "Brillo", "Luminosité", "明るさ", "밝기", "Jasność", "Brilho", "亮度", "亮度"),
"V4L2_CID_CONTRAST|Contrast": ("Kontrast", "Contraste", "Contraste", "コントラスト", "대비", "Kontrast", "Contraste", "对比度", "對比度"),
"V4L2_CID_SATURATION|Saturation": ("Sättigung", "Saturación", "Saturation", "彩度", "채도", "Nasycenie", "Saturação", "饱和度", "飽和度"),
"V4L2_CID_HUE|Hue": ("Farbton", "Tono", "Teinte", "色相", "색조", "Odcień", "Matiz", "色调", "色調"),
"V4L2_CID_AUTO_WHITE_BALANCE|White Balance, Automatic": ("Weißabgleich (automatisch)", "Balance de blancos (automático)", "Balance des blancs (automatique)", "ホワイトバランス（自動）", "화이트 밸런스(자동)", "Balans bieli (automatyczny)", "Balanço de branco (automático)", "白平衡（自动）", "白平衡（自動）"),
"V4L2_CID_GAMMA|Gamma": ("Gamma", "Gamma", "Gamma", "ガンマ", "감마", "Gamma", "Gama", "伽马", "伽瑪"),
"V4L2_CID_GAIN|Gain": ("Verstärkung", "Ganancia", "Gain", "ゲイン", "게인", "Wzmocnienie", "Ganho", "增益", "增益"),
"V4L2_CID_POWER_LINE_FREQUENCY|Power Line Frequency": ("Netzfrequenz", "Frecuencia de red", "Fréquence du secteur", "電源周波数", "전원 주파수", "Częstotliwość sieci", "Frequência da rede elétrica", "电源频率", "電源頻率"),
"V4L2_CID_SHARPNESS|Sharpness": ("Schärfe", "Nitidez", "Netteté", "シャープネス", "선명도", "Ostrość", "Nitidez", "锐度", "銳利度"),
"V4L2_CID_BACKLIGHT_COMPENSATION|Backlight Compensation": ("Gegenlichtkompensation", "Compensación de contraluz", "Compensation de contre-jour", "逆光補正", "역광 보정", "Kompensacja światła tylnego", "Compensação de contraluz", "背光补偿", "背光補償"),
"V4L2_CID_WHITE_BALANCE_TEMPERATURE|White Balance Temperature": ("Weißabgleich-Temperatur", "Temperatura del balance de blancos", "Température de la balance des blancs", "ホワイトバランス色温度", "화이트 밸런스 색온도", "Temperatura balansu bieli", "Temperatura do balanço de branco", "白平衡色温", "白平衡色溫"),
"V4L2_CID_HFLIP|Horizontal Flip": ("Horizontal spiegeln", "Voltear horizontalmente", "Retournement horizontal", "左右反転", "좌우 반전", "Odwrócenie w poziomie", "Espelhar horizontalmente", "水平翻转", "水平翻轉"),
"V4L2_CID_VFLIP|Vertical Flip": ("Vertikal spiegeln", "Voltear verticalmente", "Retournement vertical", "上下反転", "상하 반전", "Odwrócenie w pionie", "Espelhar verticalmente", "垂直翻转", "垂直翻轉"),
"V4L2_CID_EXPOSURE_AUTO|Auto Exposure": ("Automatische Belichtung", "Exposición automática", "Exposition automatique", "自動露出", "자동 노출", "Automatyczna ekspozycja", "Exposição automática", "自动曝光", "自動曝光"),
"V4L2_CID_EXPOSURE_ABSOLUTE|Exposure Time, Absolute": ("Belichtungszeit (absolut)", "Tiempo de exposición (absoluto)", "Temps d’exposition (absolu)", "露出時間（絶対値）", "노출 시간(절대값)", "Czas ekspozycji (bezwzględny)", "Tempo de exposição (absoluto)", "曝光时间（绝对值）", "曝光時間（絕對值）"),
"V4L2_CID_EXPOSURE_AUTO_PRIORITY|Exposure, Dynamic Framerate": ("Belichtung: dynamische Bildrate", "Exposición: velocidad de fotogramas dinámica", "Exposition : fréquence d’images dynamique", "露出：動的フレームレート", "노출: 동적 프레임 속도", "Ekspozycja: dynamiczna liczba klatek", "Exposição: taxa de quadros dinâmica", "曝光：动态帧率", "曝光：動態幀率"),
"V4L2_CID_FOCUS_ABSOLUTE|Focus, Absolute": ("Fokus (absolut)", "Enfoque (absoluto)", "Mise au point (absolue)", "フォーカス（絶対値）", "초점(절대값)", "Ostrość (bezwzględna)", "Foco (absoluto)", "对焦（绝对值）", "對焦（絕對值）"),
"V4L2_CID_FOCUS_AUTO|Focus, Automatic Continuous": ("Fokus (automatisch, kontinuierlich)", "Enfoque (automático continuo)", "Mise au point (automatique continue)", "フォーカス（自動連続）", "초점(자동 연속)", "Ostrość (automatyczna ciągła)", "Foco (automático contínuo)", "对焦（自动连续）", "對焦（自動連續）"),
"V4L2_CID_ZOOM_ABSOLUTE|Zoom, Absolute": ("Zoom (absolut)", "Zoom (absoluto)", "Zoom (absolu)", "ズーム（絶対値）", "줌(절대값)", "Zoom (bezwzględny)", "Zoom (absoluto)", "变焦（绝对值）", "變焦（絕對值）"),
"V4L2_CID_PAN_ABSOLUTE|Pan, Absolute": ("Schwenken (absolut)", "Panorámica (absoluta)", "Panoramique (absolu)", "パン（絶対値）", "팬(절대값)", "Obrót w poziomie (bezwzględny)", "Pan (absoluto)", "水平转动（绝对值）", "水平轉動（絕對值）"),
"V4L2_CID_TILT_ABSOLUTE|Tilt, Absolute": ("Neigen (absolut)", "Inclinación (absoluta)", "Inclinaison (absolue)", "チルト（絶対値）", "틸트(절대값)", "Pochylenie (bezwzględne)", "Tilt (absoluto)", "俯仰（绝对值）", "俯仰（絕對值）"),
"V4L2_CID_POWER_LINE_FREQUENCY_DISABLED|Disabled": ("Aus", "Desactivado", "Désactivé", "無効", "사용 안 함", "Wyłączone", "Desativado", "已禁用", "已停用"),
"V4L2_CID_POWER_LINE_FREQUENCY_50HZ|50 Hz": ("50 Hz",) * 9,
"V4L2_CID_POWER_LINE_FREQUENCY_60HZ|60 Hz": ("60 Hz",) * 9,
"V4L2_CID_POWER_LINE_FREQUENCY_AUTO|Auto": ("Automatisch", "Automático", "Automatique", "自動", "자동", "Automatycznie", "Automático", "自动", "自動"),
"V4L2_EXPOSURE_AUTO|Auto Mode": ("Automatikmodus", "Modo automático", "Mode automatique", "自動モード", "자동 모드", "Tryb automatyczny", "Modo automático", "自动模式", "自動模式"),
"V4L2_EXPOSURE_MANUAL|Manual Mode": ("Manueller Modus", "Modo manual", "Mode manuel", "手動モード", "수동 모드", "Tryb ręczny", "Modo manual", "手动模式", "手動模式"),
"V4L2_EXPOSURE_SHUTTER_PRIORITY|Shutter Priority Mode": ("Verschlusszeitpriorität", "Prioridad de obturador", "Priorité à la vitesse", "シャッター優先モード", "셔터 우선 모드", "Priorytet migawki", "Prioridade do obturador", "快门优先模式", "快門優先模式"),
"V4L2_EXPOSURE_APERTURE_PRIORITY|Aperture Priority Mode": ("Blendenpriorität", "Prioridad de apertura", "Priorité à l’ouverture", "絞り優先モード", "조리개 우선 모드", "Priorytet przysłony", "Prioridade de abertura", "光圈优先模式", "光圈優先模式"),
"V4L2_PIX_FMT_GREY|8-bit Greyscale": ("8-Bit-Graustufen", "Escala de grises de 8 bits", "Niveaux de gris 8 bits", "8 ビットグレースケール", "8비트 그레이스케일", "8-bitowa skala szarości", "Escala de cinza de 8 bits", "8 位灰度", "8 位元灰階"),
"V4L2_PIX_FMT_Y16|16-bit Greyscale": ("16-Bit-Graustufen", "Escala de grises de 16 bits", "Niveaux de gris 16 bits", "16 ビットグレースケール", "16비트 그레이스케일", "16-bitowa skala szarości", "Escala de cinza de 16 bits", "16 位灰度", "16 位元灰階"),
}
