#!/usr/bin/env python3
"""Kubabbar Glass 9's texts in the ten languages, read by draw_theme9.py and the metadata writers. GPL-3.0-only."""

LOOK_DESCRIPTION = {
    "en": "Kubabbar Glass 9 is a variant of Kubabbar Glass, our own name for this family of looks, chosen by Daniel Ramos on 14 October 2026: every control drawn in a classic bevelled form, in the family's glass. The 9 is for the classic desktop of 1999 to 2001 that it recalls, and for Sparky 9 \"Tiamat\", on which Sparky Stereo OS 9 \"Mashtabba\" is built.",
    "pl": "Kubabbar Glass 9 to odmiana Kubabbar Glass, naszej nazwy tej rodziny wyglądów, wybranej przez Daniela Ramosa 14 października 2026 r.: każda kontrolka narysowana w klasycznej, wypukłej formie, w szkle tej rodziny. Dziewiątka nawiązuje do klasycznego pulpitu z lat 1999–2001, oraz do Sparky 9 „Tiamat”, na którym zbudowano Sparky Stereo OS 9 „Mashtabba”.",
    "pt_BR": "Kubabbar Glass 9 é uma variante do Kubabbar Glass, o nome que Daniel Ramos escolheu para esta família de visuais em 14 de outubro de 2026: todos os controles desenhados na forma clássica em relevo, com o vidro da família. O 9 faz referência tanto à área de trabalho clássica de 1999 a 2001 que o tema evoca quanto ao Sparky 9 \"Tiamat\", sobre o qual o Sparky Stereo OS 9 \"Mashtabba\" é construído.",
    "fr": "Kubabbar Glass 9 est une variante de Kubabbar Glass, le nom que Daniel Ramos a choisi pour cette famille d’apparences le 14 octobre 2026 : chaque commande dessinée dans une forme classique en relief, avec le verre de la famille. Le 9 fait référence au bureau classique de 1999 à 2001 que ce thème évoque, ainsi qu’à Sparky 9 « Tiamat », sur lequel repose Sparky Stereo OS 9 « Mashtabba ».",
    "de": "Kubabbar Glass 9 ist eine Variante von Kubabbar Glass, dem Namen, den Daniel Ramos am 14. Oktober 2026 für diese Familie von Erscheinungsbildern gewählt hat: jedes Bedienelement in klassischer, plastischer Form, im Glas der Familie. Die 9 steht für den klassischen Desktop der Jahre 1999 bis 2001, an den diese Variante erinnert, und für Sparky 9 „Tiamat“, auf dem Sparky Stereo OS 9 „Mashtabba“ aufbaut.",
    "es": "Kubabbar Glass 9 es una variante de Kubabbar Glass, el nombre que Daniel Ramos eligió para esta familia de apariencias el 14 de octubre de 2026: cada control dibujado en una forma clásica en relieve, con el cristal de la familia. El 9 hace referencia tanto al escritorio clásico de 1999 a 2001 que evoca esta variante como a Sparky 9 «Tiamat», sobre el que se construye Sparky Stereo OS 9 «Mashtabba».",
    "ja": "Kubabbar Glass 9 は Kubabbar Glass の派生版です。Kubabbar Glass は、2026 年 10 月 14 日に Daniel Ramos がこの外観のシリーズに付けた名前です。すべてのコントロールをクラシックな立体的な形で、ファミリー共通のガラスとともに描いています。9 は、この外観が思い起こさせる 1999 年から 2001 年のクラシックなデスクトップと、Sparky Stereo OS 9「Mashtabba」の基盤である Sparky 9「Tiamat」に由来します。",
    "ko": "Kubabbar Glass 9는 Kubabbar Glass의 변형입니다. Kubabbar Glass는 Daniel Ramos가 2026년 10월 14일에 이 모양 계열에 붙인 이름입니다. 모든 컨트롤을 클래식한 입체 형태로, 계열 공통의 유리와 함께 그렸습니다. 9는 이 모양이 떠올리게 하는 1999년부터 2001년까지의 클래식 데스크톱과, Sparky Stereo OS 9 ‘Mashtabba’의 기반인 Sparky 9 ‘Tiamat’를 뜻합니다.",
    "zh_CN": "Kubabbar Glass 9 是 Kubabbar Glass 的变体。Kubabbar Glass 是 Daniel Ramos 于 2026 年 10 月 14 日为这一外观系列选定的名称。所有控件都以经典的立体形式绘制，并带有该系列共同的玻璃效果。其中的 9 既指它让人想起的 1999 年至 2001 年的经典桌面，也指 作为 Sparky Stereo OS 9“Mashtabba”基础的 Sparky 9“Tiamat”。",
    "zh_TW": "Kubabbar Glass 9 是 Kubabbar Glass 的變體。Kubabbar Glass 是 Daniel Ramos 於 2026 年 10 月 14 日為這一外觀系列選定的名稱。所有控制項都以經典的立體形式繪製，並帶有該系列共同的玻璃效果。其中的 9 既指它讓人想起的 1999 年至 2001 年的經典桌面，也指 作為 Sparky Stereo OS 9「Mashtabba」基礎的 Sparky 9「Tiamat」。",
}

STYLE_DESCRIPTION = {
    "en": "Original classic panels, pop-ups and tooltips in light grey, at the Kubabbar family's glass",
    "pl": "Oryginalne, klasyczne paski, okna wysuwne i podpowiedzi w jasnej szarości, w szkle rodziny Kubabbar",
    "pt_BR": "Painéis, pop-ups e dicas clássicos e originais em cinza-claro, com o vidro da família Kubabbar",
    "fr": "Panneaux, fenêtres contextuelles et infobulles classiques et originaux en gris clair, avec le verre de la famille Kubabbar",
    "de": "Eigene, klassische Kontrollleisten, Aufklappfenster und Kurzinfos in Hellgrau, im Glas der Kubabbar-Familie",
    "es": "Paneles, ventanas emergentes y ayudas emergentes de estilo clásico y original en gris claro, con el cristal de la familia Kubabbar",
    "ja": "Kubabbar ファミリーのガラスを備えた、明るいグレーのオリジナルのクラシックなパネル、ポップアップ、ツールチップ",
    "ko": "Kubabbar 계열의 유리를 갖춘 밝은 회색의 독자적인 클래식 패널, 팝업, 풍선 도움말",
    "zh_CN": "带有 Kubabbar 系列玻璃效果的浅灰色原创经典面板、弹窗和工具提示",
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

# The menu bar layout (milestone 2): the family's menu bar sentence (kubabbar-glass-menubar), and the window list at the
# bar's right end, Plasma's own applet in the place of the classic Application menu.
MENUBAR_NAME = {
    "en": "Kubabbar Glass 9, menu bar and dock", "de": "Kubabbar Glass 9 mit Menüleiste und Dock",
    "pl": "Kubabbar Glass 9, pasek menu i dok", "pt_BR": "Kubabbar Glass 9, barra de menus e dock",
    "fr": "Kubabbar Glass 9, barre de menus et dock", "es": "Kubabbar Glass 9, barra de menú y dock",
    "ja": "Kubabbar Glass 9、メニューバーとドック", "ko": "Kubabbar Glass 9, 메뉴 표시줄와 독",
    "zh_CN": "Kubabbar Glass 9，菜单栏和 Dock", "zh_TW": "Kubabbar Glass 9，選單列與 Dock",
}
MENUBAR_SENTENCE = {
    "en": "This variant puts the application menu in a bar at the top and the task manager in a floating dock at the bottom, and minimised windows fly into their dock icon. The window list at the bar's right end switches between programs.",
    "de": "Diese Variante zeigt das Anwendungsmenü in einer Leiste oben und die Fensterleiste in einem schwebenden Dock unten. Beim Minimieren fliegen Fenster in ihr Dock-Symbol. Über die Fensterliste am rechten Ende der Leiste wechseln Sie zwischen Programmen.",
    "pl": "Ten wariant umieszcza menu aplikacji na pasku u góry, a pasek zadań na pływającym doku u dołu, zaś zminimalizowane okna wlatują do swojej ikony w doku. Lista okien na prawym końcu paska pozwala przełączać się między programami.",
    "pt_BR": "Esta variante coloca o menu de aplicativos na barra de menus superior e o gerenciador de tarefas em um dock flutuante na parte inferior. As janelas minimizadas voam para seus ícones no dock. A lista de janelas na ponta direita da barra permite alternar entre os programas.",
    "fr": "Cette variante place le menu de l’application dans la barre de menus en haut et le gestionnaire de tâches dans un dock flottant en bas ; les fenêtres réduites s’envolent vers leur icône du dock. La liste des fenêtres, à l’extrémité droite de la barre, permet de passer d’un programme à l’autre.",
    "es": "Esta variante coloca el menú de la aplicación en una barra superior y el gestor de tareas en un dock flotante en la parte inferior, y las ventanas minimizadas vuelan hacia su icono del dock. La lista de ventanas, en el extremo derecho de la barra, cambia entre programas.",
    "ja": "このバリエーションは、アプリケーションメニューを上部のバーに、タスクマネージャを下部のフローティングドックに置き、最小化したウィンドウはドックのアイコンへ飛び込みます。バーの右端にあるウィンドウリストでプログラムを切り替えます。",
    "ko": "이 변형은 앱 메뉴를 위쪽 메뉴 표시줄에, 작업 관리자를 아래쪽의 떠 있는 독에 두며, 최소화된 창은 독의 아이콘으로 날아 들어갑니다. 막대 오른쪽 끝의 창 목록으로 프로그램을 전환합니다.",
    "zh_CN": "此变体将应用程序菜单放在顶部菜单栏，任务管理器放在底部的悬浮 Dock 中，最小化的窗口会飞入其 Dock 图标。栏右端的窗口列表用于在程序之间切换。",
    "zh_TW": "此變體將應用程式選單放在頂端選單列，工作管理員放在底部的浮動 Dock 中，最小化的視窗會飛入其 Dock 圖示。列右端的視窗清單用於在程式之間切換。",
}

# The login screen (an SDDM theme): its description, and the two texts SDDM's own constants do not have. Every other
# text on it is SDDM's, translated by SDDM (textConstants: welcomeText, userName, password, session, login, loginFailed,
# capslockWarning, shutdown, reboot).
SDDM_DESCRIPTION = {
    "en": "Login screen for the Kubabbar Glass 9 look: a classic window listing the people of this computer, over the look's pattern",
    "de": "Anmeldebildschirm für das Design Kubabbar Glass 9: Ein klassisches Fenster zeigt die Benutzer dieses Computers vor dem Designmuster",
    "es": "Pantalla de inicio de sesión del tema Kubabbar Glass 9: una ventana clásica muestra los usuarios del equipo sobre el motivo del tema",
    "fr": "Écran de connexion du thème Kubabbar Glass 9 : une fenêtre classique affiche la liste des utilisateurs de l’ordinateur sur le motif du thème",
    "ja": "Kubabbar Glass 9 のログイン画面：外観の模様の上に、このコンピューターを使う人の一覧を表示するクラシックなウィンドウ",
    "ko": "Kubabbar Glass 9 로그인 화면: 테마 무늬 위에 이 컴퓨터의 사용자 목록을 보여 주는 클래식 창",
    "pl": "Ekran logowania wyglądu Kubabbar Glass 9: klasyczne okno z listą osób korzystających z tego komputera, na tle wzoru tego wyglądu",
    "pt_BR": "Tela de login do tema Kubabbar Glass 9: uma janela clássica com a lista das pessoas deste computador sobre o padrão do tema",
    "zh_CN": "Kubabbar Glass 9 主题的登录屏幕：以主题图案为背景，在经典窗口中列出本机用户",
    "zh_TW": "Kubabbar Glass 9 主題的登入畫面：以主題圖案為背景，在經典視窗中列出本機使用者",
}
LOGIN_PROMPT = {
    "en": "Choose your name in the list, or type it.", "de": "Wählen Sie Ihren Benutzernamen aus der Liste oder geben Sie ihn ein.",
    "es": "Seleccione su usuario en la lista o escríbalo.", "fr": "Sélectionnez votre identifiant dans la liste ou saisissez-le.",
    "ja": "一覧からユーザ名を選ぶか、入力してください。", "ko": "목록에서 사용자 이름을 선택하거나 직접 입력하십시오.",
    "pl": "Wybierz nazwę użytkownika z listy lub wpisz ją.", "pt_BR": "Escolha seu usuário na lista ou digite-o.",
    "zh_CN": "请在列表中选择您的用户名，或直接输入。", "zh_TW": "請在清單中選取您的使用者名稱，或直接輸入。",
}
LOGIN_CANCEL = {
    "en": "Cancel", "de": "Abbrechen", "es": "Cancelar", "fr": "Annuler", "ja": "キャンセル", "ko": "취소",
    "pl": "Anuluj", "pt_BR": "Cancelar", "zh_CN": "取消", "zh_TW": "取消",
}
