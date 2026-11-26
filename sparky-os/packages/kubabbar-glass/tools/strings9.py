#!/usr/bin/env python3
"""Kubabbar Glass 9's texts in the ten languages, read by draw_theme9.py and the metadata writers. GPL-3.0-only."""

LOOK_DESCRIPTION = {
    "en": "Kubabbar Glass 9 is a variant of Kubabbar Glass, our own name for this family of looks, chosen by Daniel Ramos on 14 October 2026: every control drawn in a classic bevelled form, in the family's glass. The 9 is for the classic desktop of 1999 to 2001 that it recalls, and for Sparky 9 \"Tiamat\", on which Sparky Stereo OS 9 \"Mashtabba\" is built.",
    "pl": "Kubabbar Glass 9 to odmiana Kubabbar Glass, naszej nazwy tej rodziny wyglądów, wybranej przez Daniela Ramosa 14 października 2026 r.: każda kontrolka narysowana w klasycznej, wypukłej formie, w szkle tej rodziny. Dziewiątka nawiązuje do klasycznego pulpitu z lat od 1999 do 2001, który przypomina, oraz do Sparky 9 „Tiamat”, na którym zbudowano Sparky Stereo OS 9 „Mashtabba”.",
    "pt_BR": "Kubabbar Glass 9 é uma variante do Kubabbar Glass, o nome que Daniel Ramos escolheu para esta família de visuais em 14 de outubro de 2026: todos os controles desenhados na forma clássica em relevo, com o vidro da família. O 9 vem da área de trabalho clássica de 1999 a 2001 que ele lembra e do Sparky 9 \"Tiamat\", sobre o qual o Sparky Stereo OS 9 \"Mashtabba\" é construído.",
    "fr": "Kubabbar Glass 9 est une variante de Kubabbar Glass, le nom que Daniel Ramos a choisi pour cette famille d’apparences le 14 octobre 2026 : chaque commande dessinée dans une forme classique en relief, avec le verre de la famille. Le 9 rappelle le bureau classique de 1999 à 2001 qu’il évoque, et Sparky 9 « Tiamat », sur lequel est construit Sparky Stereo OS 9 « Mashtabba ».",
    "de": "Kubabbar Glass 9 ist eine Variante von Kubabbar Glass, dem Namen, den Daniel Ramos am 14. Oktober 2026 für diese Familie von Erscheinungsbildern gewählt hat: jedes Bedienelement in klassischer, plastischer Form, im Glas der Familie. Die 9 steht für den klassischen Desktop der Jahre 1999 bis 2001, an den es erinnert, und für Sparky 9 „Tiamat“, auf dem Sparky Stereo OS 9 „Mashtabba“ aufbaut.",
    "es": "Kubabbar Glass 9 es una variante de Kubabbar Glass, el nombre que Daniel Ramos eligió para esta familia de apariencias el 14 de octubre de 2026: cada control dibujado en una forma clásica en relieve, con el cristal de la familia. El 9 recuerda el escritorio clásico de 1999 a 2001 que evoca y a Sparky 9 «Tiamat», sobre el que se construye Sparky Stereo OS 9 «Mashtabba».",
    "ja": "Kubabbar Glass 9 は Kubabbar Glass の派生版です。Kubabbar Glass は、2026 年 10 月 14 日に Daniel Ramos がこの外観ファミリーに選んだ名前です。すべてのコントロールをクラシックな立体的な形で、ファミリー共通のガラスとともに描いています。9 は、この外観が思い起こさせる 1999 年から 2001 年のクラシックなデスクトップと、Sparky Stereo OS 9「Mashtabba」の基盤である Sparky 9「Tiamat」に由来します。",
    "ko": "Kubabbar Glass 9는 Kubabbar Glass의 변형입니다. Kubabbar Glass는 Daniel Ramos가 2026년 10월 14일에 이 모양 계열에 붙인 이름입니다. 모든 컨트롤을 클래식한 입체 형태로, 계열 공통의 유리와 함께 그렸습니다. 9는 이 모양이 떠올리게 하는 1999년부터 2001년까지의 클래식 데스크톱과, Sparky Stereo OS 9 \"Mashtabba\"의 기반인 Sparky 9 \"Tiamat\"에서 왔습니다.",
    "zh_CN": "Kubabbar Glass 9 是 Kubabbar Glass 的变体。Kubabbar Glass 是 Daniel Ramos 于 2026 年 10 月 14 日为这一外观系列选定的名称。所有控件都以经典的立体形式绘制，并带有该系列共同的玻璃效果。其中的 9 既指它让人想起的 1999 年至 2001 年的经典桌面，也指 Sparky 9“Tiamat”，Sparky Stereo OS 9“Mashtabba”正是在其上构建的。",
    "zh_TW": "Kubabbar Glass 9 是 Kubabbar Glass 的變體。Kubabbar Glass 是 Daniel Ramos 於 2026 年 10 月 14 日為這一外觀系列選定的名稱。所有控制項都以經典的立體形式繪製，並帶有該系列共同的玻璃效果。其中的 9 既指它讓人想起的 1999 年至 2001 年的經典桌面，也指 Sparky 9「Tiamat」，Sparky Stereo OS 9「Mashtabba」正是在其上建構的。",
}

STYLE_DESCRIPTION = {
    "en": "Original classic panels, pop-ups and tooltips in light grey, at the Kubabbar family's glass",
    "pl": "Oryginalne, klasyczne panele, okna wyskakujące i podpowiedzi w jasnej szarości, w szkle rodziny Kubabbar",
    "pt_BR": "Painéis, janelas suspensas e dicas clássicos e originais em cinza-claro, com o vidro da família Kubabbar",
    "fr": "Panneaux, fenêtres surgissantes et infobulles classiques et originaux en gris clair, avec le verre de la famille Kubabbar",
    "de": "Eigene, klassische Leisten, Aufklappfenster und Kurzinfos in Hellgrau, im Glas der Kubabbar-Familie",
    "es": "Paneles, ventanas emergentes y descripciones emergentes clásicos y originales en gris claro, con el cristal de la familia Kubabbar",
    "ja": "Kubabbar ファミリーのガラスを備えた、明るいグレーのオリジナルのクラシックなパネル、ポップアップ、ツールチップ",
    "ko": "Kubabbar 계열의 유리를 갖춘 밝은 회색의 독자적인 클래식 패널, 팝업, 도구 설명",
    "zh_CN": "带有 Kubabbar 系列玻璃效果的浅灰色原创经典面板、弹出窗口和工具提示",
    "zh_TW": "帶有 Kubabbar 系列玻璃效果的淺灰色原創經典面板、彈出視窗與工具提示",
}

DECORATION_COMMENT = {
    "en": "Original classic window frame with a striped title bar",
    "pl": "Oryginalna, klasyczna ramka okna z paskowanym paskiem tytułu",
    "pt_BR": "Moldura de janela clássica e original com barra de título listrada",
    "fr": "Cadre de fenêtre classique et original avec une barre de titre rayée",
    "de": "Eigener, klassischer Fensterrahmen mit gestreifter Titelleiste",
    "es": "Marco de ventana clásico y original con barra de título rayada",
    "ja": "縞模様のタイトルバーを持つオリジナルのクラシックなウィンドウ枠",
    "ko": "줄무늬 제목 표시줄이 있는 독자적인 클래식 창 틀",
    "zh_CN": "带条纹标题栏的原创经典窗口边框",
    "zh_TW": "帶條紋標題列的原創經典視窗框架",
}

WALLPAPER_DESCRIPTION = {
    "en": "An original light periwinkle pattern",
    "pl": "Oryginalny wzór w jasnym odcieniu barwinka",
    "pt_BR": "Um padrão original em azul-pervinca claro",
    "fr": "Un motif original bleu pervenche clair",
    "de": "Ein eigenes Muster in hellem Immergrünblau",
    "es": "Un patrón original en azul vincapervinca claro",
    "ja": "明るいペリウィンクルのオリジナルの模様",
    "ko": "밝은 페리윙클 색의 독자적인 무늬",
    "zh_CN": "原创的浅长春花蓝图案",
    "zh_TW": "原創的淺長春花藍圖案",
}
