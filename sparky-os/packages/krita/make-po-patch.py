#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the catalogue patch of the edition's Krita (queue row 148, Krita's milestone 1): every sentence the
# edition's patches add, in the nine languages besides English, appended to Krita's own catalogues (po/LANG/krita.po)
# of the source the package builds. "Enable 3D" and "Display Settings…" are the stereo layer's words, in its own
# translations (stereo-layer po/LANG/stereo-layer_qt.po); "canvas" is each catalogue's own word for Krita's canvas.
# The two sentences of the 16-bit canvas surface carry the translations of ORDER 46c unchanged.
#   make-po-patch.py PO_ROOT OUT
#   PO_ROOT  the unpacked source's top folder (it holds po/LANG/krita.po)
#   OUT      the patch to write (-p1, paths po/LANG/krita.po)
import difflib
import sys
from pathlib import Path

LANGS = ["de", "es", "fr", "ja", "ko", "pl", "pt_BR", "zh_CN", "zh_TW"]

# (msgctxt or None, msgid, {language: msgstr}); a msgid with %1 is a KDE format string
ENTRIES = [
    ("action", "Display Settings…", {
        "de": "Anzeigeeinstellungen …", "es": "Configuración de pantalla…", "fr": "Paramètres d’affichage…",
        "ja": "ディスプレイの設定…", "ko": "디스플레이 설정…", "pl": "Ustawienia ekranu…",
        "pt_BR": "Configurações de tela…", "zh_CN": "显示设置…", "zh_TW": "顯示設定…"}),
    ("action", "Display Settings", {
        "de": "Anzeigeeinstellungen", "es": "Configuración de pantalla", "fr": "Paramètres d’affichage",
        "ja": "ディスプレイの設定", "ko": "디스플레이 설정", "pl": "Ustawienia ekranu",
        "pt_BR": "Configurações de tela", "zh_CN": "显示设置", "zh_TW": "顯示設定"}),
    ("action", "Open the display settings: each screen's 3D format and the depth limits are set there", {
        "de": "Öffnet die Anzeigeeinstellungen: Dort werden das 3D-Format jedes Bildschirms und die Tiefengrenzen eingestellt",
        "es": "Abre la configuración de pantalla: allí se ajustan el formato 3D de cada pantalla y los límites de profundidad",
        "fr": "Ouvre les paramètres d’affichage : le format 3D de chaque écran et les limites de profondeur s’y règlent",
        "ja": "ディスプレイの設定を開きます。各画面の 3D 形式と奥行きの限度はそこで設定します",
        "ko": "디스플레이 설정을 엽니다. 각 화면의 3D 형식과 깊이 한계는 그곳에서 설정합니다",
        "pl": "Otwiera ustawienia ekranu: tam ustawia się format 3D każdego ekranu i granice głębi",
        "pt_BR": "Abre as configurações de tela: lá se ajustam o formato 3D de cada tela e os limites de profundidade",
        "zh_CN": "打开显示设置：每个屏幕的 3D 格式和深度限制都在那里设置",
        "zh_TW": "開啟顯示設定：每個螢幕的 3D 格式與深度限制都在那裡設定"}),
    (None, "Enable 3D", {
        "de": "3D aktivieren", "es": "Activar 3D", "fr": "Activer la 3D", "ja": "3D を有効にする", "ko": "3D 사용",
        "pl": "Włącz 3D", "pt_BR": "Ativar 3D", "zh_CN": "启用 3D", "zh_TW": "啟用 3D"}),
    (None, "Display Settings could not be opened: %1", {
        "de": "Die Anzeigeeinstellungen konnten nicht geöffnet werden: %1",
        "es": "No se pudo abrir la configuración de pantalla: %1",
        "fr": "Les paramètres d’affichage n’ont pas pu être ouverts : %1",
        "ja": "ディスプレイの設定を開けませんでした: %1",
        "ko": "디스플레이 설정을 열 수 없습니다: %1",
        "pl": "Nie można otworzyć ustawień ekranu: %1",
        "pt_BR": "Não foi possível abrir as configurações de tela: %1",
        "zh_CN": "无法打开显示设置：%1",
        "zh_TW": "無法開啟顯示設定：%1"}),
    (None, "This picture is shown flat, as its left eye. %1", {
        "de": "Dieses Bild wird flach gezeigt, als sein linkes Auge. %1",
        "es": "Esta imagen se muestra plana, como su ojo izquierdo. %1",
        "fr": "Cette image est affichée à plat, par son œil gauche. %1",
        "ja": "この画像は左目の画像として平面で表示されています。%1",
        "ko": "이 그림은 왼쪽 눈 화면으로 평면 표시됩니다. %1",
        "pl": "Ten obraz jest wyświetlany płasko, jako lewe oko. %1",
        "pt_BR": "Esta imagem é mostrada plana, como seu olho esquerdo. %1",
        "zh_CN": "此图像以平面方式显示，显示的是左眼画面。%1",
        "zh_TW": "此影像以平面方式顯示，顯示的是左眼畫面。%1"}),
    (None, "This picture is shown flat, as it is. %1", {
        "de": "Dieses Bild wird flach gezeigt, so wie es ist. %1",
        "es": "Esta imagen se muestra plana, tal como es. %1",
        "fr": "Cette image est affichée à plat, telle quelle. %1",
        "ja": "この画像はそのまま平面で表示されています。%1",
        "ko": "이 그림은 있는 그대로 평면 표시됩니다. %1",
        "pl": "Ten obraz jest wyświetlany płasko, tak jak jest. %1",
        "pt_BR": "Esta imagem é mostrada plana, como está. %1",
        "zh_CN": "此图像按原样以平面方式显示。%1",
        "zh_TW": "此影像按原樣以平面方式顯示。%1"}),
    (None, "The 3D canvas needs Krita's OpenGL canvas (Settings > Configure Krita > Display).", {
        "de": "Die 3D-Leinwand braucht Kritas OpenGL-Leinwand (Einstellungen > Krita einrichten > Anzeige).",
        "es": "El lienzo 3D necesita el lienzo OpenGL de Krita (Preferencias > Configurar Krita > Pantalla).",
        "fr": "Le canevas 3D a besoin du canevas OpenGL de Krita (Paramètres > Configuration de Krita > Affichage).",
        "ja": "3D キャンバスには Krita の OpenGL キャンバスが必要です (設定 > Krita の設定を変更 > 表示)。",
        "ko": "3D 캔버스에는 Krita의 OpenGL 캔버스가 필요합니다(설정 > Krita 설정 > 디스플레이).",
        "pl": "Płótno 3D wymaga płótna OpenGL Krity (Ustawienia > Ustawienia Krity > Wyświetlanie).",
        "pt_BR": "A tela de pintura 3D precisa da tela de pintura OpenGL do Krita (Configurações > Configurar o Krita > Visualização).",
        "zh_CN": "3D 画布需要 Krita 的 OpenGL 画布（设置 > 配置 Krita > 显示）。",
        "zh_TW": "3D 畫布需要 Krita 的 OpenGL 畫布（設定 > 設定 Krita > 顯示）。"}),
    (None, "This Krita was built without the surface the 3D canvas is shown on.", {
        "de": "Dieses Krita wurde ohne die Oberfläche gebaut, auf der die 3D-Leinwand gezeigt wird.",
        "es": "Este Krita se compiló sin la superficie en la que se muestra el lienzo 3D.",
        "fr": "Ce Krita a été compilé sans la surface sur laquelle le canevas 3D s’affiche.",
        "ja": "この Krita は 3D キャンバスを表示するサーフェスなしでビルドされています。",
        "ko": "이 Krita는 3D 캔버스를 표시하는 표면 없이 빌드되었습니다.",
        "pl": "Ta Krita została zbudowana bez powierzchni, na której wyświetlane jest płótno 3D.",
        "pt_BR": "Este Krita foi compilado sem a superfície em que a tela de pintura 3D é mostrada.",
        "zh_CN": "此 Krita 构建时未包含显示 3D 画布的表面。",
        "zh_TW": "此 Krita 建置時未包含顯示 3D 畫布的表面。"}),
    (None, "Krita runs on X11 here, and its 3D canvas is shown on Wayland: start Krita without QT_QPA_PLATFORM=xcb.", {
        "de": "Krita läuft hier unter X11, die 3D-Leinwand wird aber unter Wayland gezeigt: Starten Sie Krita ohne QT_QPA_PLATFORM=xcb.",
        "es": "Krita se ejecuta aquí en X11, y su lienzo 3D se muestra en Wayland: inicie Krita sin QT_QPA_PLATFORM=xcb.",
        "fr": "Krita tourne ici sous X11, et son canevas 3D s’affiche sous Wayland : lancez Krita sans QT_QPA_PLATFORM=xcb.",
        "ja": "ここでは Krita は X11 で動いていますが、3D キャンバスは Wayland で表示されます。QT_QPA_PLATFORM=xcb を付けずに Krita を起動してください。",
        "ko": "여기서 Krita는 X11에서 실행 중이며, 3D 캔버스는 Wayland에서 표시됩니다. QT_QPA_PLATFORM=xcb 없이 Krita를 시작하십시오.",
        "pl": "Krita działa tu w X11, a jej płótno 3D jest wyświetlane w Wayland: uruchom Kritę bez QT_QPA_PLATFORM=xcb.",
        "pt_BR": "O Krita roda aqui no X11, e a tela de pintura 3D é mostrada no Wayland: inicie o Krita sem QT_QPA_PLATFORM=xcb.",
        "zh_CN": "此处的 Krita 运行在 X11 上，而它的 3D 画布显示在 Wayland 上：请不带 QT_QPA_PLATFORM=xcb 启动 Krita。",
        "zh_TW": "此處的 Krita 在 X11 上執行，而它的 3D 畫布顯示於 Wayland：請不帶 QT_QPA_PLATFORM=xcb 啟動 Krita。"}),
    (None, "The 3D canvas is not shown in wrap-around mode.", {
        "de": "Im Textumfluss-Modus wird die 3D-Leinwand nicht gezeigt.",
        "es": "El lienzo 3D no se muestra en el modo envolvente.",
        "fr": "Le canevas 3D n’est pas affiché en mode enveloppant.",
        "ja": "ラップアラウンドモードでは 3D キャンバスは表示されません。",
        "ko": "둘러싸기 모드에서는 3D 캔버스가 표시되지 않습니다.",
        "pl": "W trybie owijania płótno 3D nie jest wyświetlane.",
        "pt_BR": "A tela de pintura 3D não é mostrada no modo em ciclo.",
        "zh_CN": "四方连续显示模式下不显示 3D 画布。",
        "zh_TW": "連續環繞模式下不顯示 3D 畫布。"}),
    (None, "The 3D canvas needs desktop OpenGL, and this canvas runs on OpenGL ES.", {
        "de": "Die 3D-Leinwand braucht Desktop-OpenGL, diese Leinwand läuft aber mit OpenGL ES.",
        "es": "El lienzo 3D necesita OpenGL de escritorio, y este lienzo funciona con OpenGL ES.",
        "fr": "Le canevas 3D a besoin d’OpenGL de bureau, et ce canevas fonctionne avec OpenGL ES.",
        "ja": "3D キャンバスにはデスクトップ OpenGL が必要ですが、このキャンバスは OpenGL ES で動作しています。",
        "ko": "3D 캔버스에는 데스크톱 OpenGL이 필요하지만, 이 캔버스는 OpenGL ES로 실행 중입니다.",
        "pl": "Płótno 3D wymaga OpenGL dla komputerów stacjonarnych, a to płótno działa na OpenGL ES.",
        "pt_BR": "A tela de pintura 3D precisa do OpenGL de desktop, e esta tela de pintura roda em OpenGL ES.",
        "zh_CN": "3D 画布需要桌面 OpenGL，而此画布运行在 OpenGL ES 上。",
        "zh_TW": "3D 畫布需要桌面 OpenGL，而此畫布在 OpenGL ES 上執行。"}),
    (None, "The 3D canvas could not make its OpenGL context.", {
        "de": "Die 3D-Leinwand konnte ihren OpenGL-Kontext nicht erzeugen.",
        "es": "El lienzo 3D no pudo crear su contexto de OpenGL.",
        "fr": "Le canevas 3D n’a pas pu créer son contexte OpenGL.",
        "ja": "3D キャンバスは OpenGL コンテキストを作成できませんでした。",
        "ko": "3D 캔버스가 OpenGL 컨텍스트를 만들 수 없습니다.",
        "pl": "Płótno 3D nie mogło utworzyć swojego kontekstu OpenGL.",
        "pt_BR": "A tela de pintura 3D não conseguiu criar seu contexto OpenGL.",
        "zh_CN": "3D 画布无法创建其 OpenGL 上下文。",
        "zh_TW": "3D 畫布無法建立其 OpenGL 上下文。"}),
    (None, "The graphics stack gave the 3D canvas one view (%1).", {
        "de": "Das Grafiksystem hat der 3D-Leinwand nur eine Ansicht gegeben (%1).",
        "es": "El sistema gráfico dio al lienzo 3D una sola vista (%1).",
        "fr": "Le système graphique n’a donné qu’une vue au canevas 3D (%1).",
        "ja": "グラフィックススタックが 3D キャンバスに 1 つのビューしか与えませんでした (%1)。",
        "ko": "그래픽 스택이 3D 캔버스에 뷰를 하나만 주었습니다(%1).",
        "pl": "Stos graficzny dał płótnu 3D tylko jeden widok (%1).",
        "pt_BR": "A pilha gráfica deu à tela de pintura 3D uma só vista (%1).",
        "zh_CN": "图形栈只给了 3D 画布一个视图（%1）。",
        "zh_TW": "圖形堆疊只給了 3D 畫布一個視圖（%1）。"}),
    (None, "The graphics stack does not show the surface the 3D canvas is drawn on (%1).", {
        "de": "Das Grafiksystem zeigt die Oberfläche nicht, auf der die 3D-Leinwand gezeichnet wird (%1).",
        "es": "El sistema gráfico no muestra la superficie en la que se dibuja el lienzo 3D (%1).",
        "fr": "Le système graphique n’affiche pas la surface sur laquelle le canevas 3D est dessiné (%1).",
        "ja": "グラフィックススタックは 3D キャンバスを描画するサーフェスを表示しません (%1)。",
        "ko": "그래픽 스택이 3D 캔버스를 그리는 표면을 표시하지 않습니다(%1).",
        "pl": "Stos graficzny nie wyświetla powierzchni, na której rysowane jest płótno 3D (%1).",
        "pt_BR": "A pilha gráfica não mostra a superfície em que a tela de pintura 3D é desenhada (%1).",
        "zh_CN": "图形栈不显示绘制 3D 画布的表面（%1）。",
        "zh_TW": "圖形堆疊不顯示繪製 3D 畫布的表面（%1）。"}),
    (None, "The canvas reaches the screen with %1 bits per channel, fewer than this document's %2: "
           "the graphics stack offers no deeper canvas surface here.", {
        "de": "Die Leinwand erreicht den Bildschirm mit %1 Bit pro Kanal, weniger als die %2 dieses Dokuments: "
              "Das Grafiksystem bietet hier keine tiefere Oberfläche für die Leinwand.",
        "es": "El lienzo llega a la pantalla con %1 bits por canal, menos que los %2 de este documento: "
              "el sistema gráfico no ofrece aquí una superficie de lienzo más profunda.",
        "fr": "Le canevas atteint l’écran avec %1 bits par canal, moins que les %2 de ce document : "
              "le système graphique n’offre ici aucune surface de canevas plus profonde.",
        "ja": "キャンバスはチャンネルあたり %1 ビットで画面に届き、このドキュメントの %2 ビットより少なくなります: "
              "ここではグラフィックススタックがより深いキャンバスサーフェスを提供していません。",
        "ko": "캔버스가 채널당 %1비트로 화면에 전달되며, 이 문서의 %2비트보다 적습니다. "
              "여기서는 그래픽 스택이 더 깊은 캔버스 표면을 제공하지 않습니다.",
        "pl": "Płótno trafia na ekran z %1 bitami na kanał, mniej niż %2 tego dokumentu: "
              "stos graficzny nie oferuje tu głębszej powierzchni płótna.",
        "pt_BR": "A tela de pintura chega ao monitor com %1 bits por canal, menos que os %2 deste documento: "
                 "a pilha gráfica não oferece aqui uma superfície mais profunda para a tela de pintura.",
        "zh_CN": "画布以每通道 %1 位到达屏幕，少于此文档的 %2 位：此处的图形栈不提供更深的画布表面。",
        "zh_TW": "畫布以每個色版 %1 位元抵達螢幕，少於此文件的 %2 位元：此處的圖形堆疊不提供更深的畫布表面。"}),
    (None, "The canvas reaches the screen with %1 bits per channel, fewer than this document's %2: "
           "the canvas surface bit depth is set to %1 bits in Settings > Configure Krita > Color Management.", {
        "de": "Die Leinwand erreicht den Bildschirm mit %1 Bit pro Kanal, weniger als die %2 dieses Dokuments: "
              "Die Bittiefe der Leinwandoberfläche ist unter Einstellungen > Krita einrichten > Farbverwaltung auf %1 Bit gesetzt.",
        "es": "El lienzo llega a la pantalla con %1 bits por canal, menos que los %2 de este documento: "
              "la profundidad de bits de la superficie del lienzo está fijada en %1 bits en Preferencias > Configurar Krita > Gestión de color.",
        "fr": "Le canevas atteint l’écran avec %1 bits par canal, moins que les %2 de ce document : "
              "la profondeur en bits de la surface du canevas est réglée sur %1 bits dans Paramètres > Configuration de Krita > Gestion des couleurs.",
        "ja": "キャンバスはチャンネルあたり %1 ビットで画面に届き、このドキュメントの %2 ビットより少なくなります: "
              "設定 > Krita の設定を変更 > カラーマネジメント でキャンバスサーフェスのビット深度が %1 ビットに設定されています。",
        "ko": "캔버스가 채널당 %1비트로 화면에 전달되며, 이 문서의 %2비트보다 적습니다. "
              "설정 > Krita 설정 > 색 관리에서 캔버스 표면 비트 깊이가 %1비트로 설정되어 있습니다.",
        "pl": "Płótno trafia na ekran z %1 bitami na kanał, mniej niż %2 tego dokumentu: "
              "głębia bitowa powierzchni płótna jest ustawiona na %1 bitów w Ustawienia > Ustawienia Krity > Zarządzanie barwami.",
        "pt_BR": "A tela de pintura chega ao monitor com %1 bits por canal, menos que os %2 deste documento: "
                 "a profundidade de bits da superfície da tela está definida como %1 bits em Configurações > Configurar o Krita > Gerenciamento de cor.",
        "zh_CN": "画布以每通道 %1 位到达屏幕，少于此文档的 %2 位：设置 > 配置 Krita > 色彩管理 中的画布表面位深度设为 %1 位。",
        "zh_TW": "畫布以每個色版 %1 位元抵達螢幕，少於此文件的 %2 位元：設定 > 設定 Krita > 色彩管理 中的畫布表面位元深度設為 %1 位元。"}),
    (None, "The canvas reaches the screen in half float, about 11 bits per channel, fewer than this document's 16: "
           "the graphics stack offers no 16-bit integer canvas surface here.", {
        "de": "Die Leinwand erreicht den Bildschirm in halber Gleitkommagenauigkeit, etwa 11 Bit pro Kanal, weniger als "
              "die 16 dieses Dokuments: Das Grafiksystem bietet hier keine 16-Bit-Ganzzahl-Oberfläche für die Leinwand.",
        "es": "El lienzo llega a la pantalla en coma flotante de media precisión, unos 11 bits por canal, menos que los 16 "
              "de este documento: el sistema gráfico no ofrece aquí una superficie de lienzo entera de 16 bits.",
        "fr": "Le canevas atteint l’écran en virgule flottante demi-précision, environ 11 bits par canal, moins que les 16 "
              "de ce document : le système graphique n’offre ici aucune surface de canevas entière de 16 bits.",
        "ja": "キャンバスは半精度浮動小数点 (チャンネルあたり約 11 ビット) で画面に届き、このドキュメントの 16 ビットより"
              "少なくなります: ここではグラフィックススタックが 16 ビット整数のキャンバスサーフェスを提供していません。",
        "ko": "캔버스가 반정밀도 부동소수점(채널당 약 11비트)으로 화면에 전달되며, 이 문서의 16비트보다 적습니다. "
              "여기서는 그래픽 스택이 16비트 정수 캔버스 표면을 제공하지 않습니다.",
        "pl": "Płótno trafia na ekran w formacie zmiennoprzecinkowym połówkowej precyzji, około 11 bitów na kanał, mniej "
              "niż 16 tego dokumentu: stos graficzny nie oferuje tu 16-bitowej całkowitoliczbowej powierzchni płótna.",
        "pt_BR": "A tela de pintura chega ao monitor em ponto flutuante de meia precisão, cerca de 11 bits por canal, menos "
                 "que os 16 deste documento: a pilha gráfica não oferece aqui uma superfície inteira de 16 bits para a tela de pintura.",
        "zh_CN": "画布以半精度浮点到达屏幕，每通道约 11 位，少于此文档的 16 位：此处的图形栈不提供 16 位整数画布表面。",
        "zh_TW": "畫布以半精度浮點抵達螢幕，每個色版約 11 位元，少於此文件的 16 位元：此處的圖形堆疊不提供 16 位元整數畫布表面。"}),
    (None, "16-bit", {
        "de": "16 Bit", "es": "16 bits", "fr": "16 bits", "ja": "16 ビット", "ko": "16비트", "pl": "16-bitowy",
        "pt_BR": "16 bits", "zh_CN": "16 位", "zh_TW": "16 位元"}),
    (None, "<p>The bit depth of the color that is passed to the window compositor. \"Auto\" uses the deepest surface "
           "the graphics stack offers. You should use at least 10-bit if you want to use HDR capabilities of your display</p>", {
        "de": "<p>Farbtiefe, die an den Fenster-Compositor übergeben wird. „Auto“ nutzt die höchste vom Grafiksystem "
              "angebotene Farbtiefe. Wählen Sie mindestens 10 Bit, um HDR des Bildschirms zu nutzen</p>",
        "es": "<p>Profundidad de color que se entrega al compositor de ventanas. «Auto» usa la superficie de mayor "
              "profundidad que ofrece el sistema gráfico. Use al menos 10 bits para aprovechar el HDR de la pantalla</p>",
        "fr": "<p>Profondeur de couleur transmise au compositeur de fenêtres. « Auto » utilise la surface de plus grande "
              "profondeur proposée par le système graphique. Choisissez au moins 10 bits pour profiter du HDR de l’écran</p>",
        "ja": "<p>ウィンドウコンポジターに渡す色のビット深度です。「自動」はグラフィックススタックが提供する最も深いサーフェスを"
              "使います。画面の HDR 機能を使うには 10 ビット以上を選んでください</p>",
        "ko": "<p>창 컴포지터로 전달하는 색의 비트 깊이입니다. ‘자동’은 그래픽 스택이 제공하는 가장 깊은 표면을 사용합니다. "
              "디스플레이의 HDR을 사용하려면 10비트 이상을 선택하세요</p>",
        "pl": "<p>Głębia bitowa koloru przekazywanego do kompozytora okien. „Auto” wybiera powierzchnię o największej głębi "
              "obsługiwanej przez stos graficzny. Aby korzystać z HDR ekranu, wybierz co najmniej 10 bitów</p>",
        "pt_BR": "<p>Profundidade de cor passada ao compositor de janelas. “Automático” usa a superfície com a maior "
                 "profundidade disponível. Use pelo menos 10 bits para aproveitar o HDR da tela</p>",
        "zh_CN": "<p>传给窗口合成器的颜色位深。“自动”使用图形系统提供的最高位深表面。要使用显示器的 HDR 功能，请至少选择 10 位</p>",
        "zh_TW": "<p>傳給視窗合成器的色彩位元深度。「自動」會使用圖形系統支援的最高位元深度繪圖表面。若要使用顯示器的 HDR 功能，請選擇至少 10 位元</p>"}),
]


def quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def entry(context, msgid, msgstr):
    lines = ["", "#, kde-format"] if "%1" in msgid else [""]
    if context:
        lines.append("msgctxt " + quote(context))
    lines += ["msgid " + quote(msgid), "msgstr " + quote(msgstr)]
    return "\n".join(lines) + "\n"


def main():
    root, out = Path(sys.argv[1]), Path(sys.argv[2])
    for context, msgid, translations in ENTRIES:
        missing = set(LANGS) - set(translations)
        assert not missing, (msgid, missing)
    patch = []
    for lang in LANGS:
        path = root / "po" / lang / "krita.po"
        old = path.read_text(encoding="utf-8")
        new = old if old.endswith("\n") else old + "\n"
        for context, msgid, translations in ENTRIES:
            key = ("msgctxt " + quote(context) + "\n" if context else "") + "msgid " + quote(msgid) + "\n"
            if "\n" + key in "\n" + old:
                raise SystemExit(f"{lang}: {msgid!r} is in Krita's catalogue already; take its translation instead")
            new += entry(context, msgid, translations[lang])
        patch += difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                      f"a/po/{lang}/krita.po", f"b/po/{lang}/krita.po", n=3)
    out.write_text("".join(patch), encoding="utf-8")


if __name__ == "__main__":
    main()
