# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The page's own sentences in the edition's ten languages (English is the source text). Order: de, es, fr, ja, ko, pl, pt_BR, zh_CN, zh_TW.
# The packings' names are not here: make-po.py takes them from the stereo layer's catalogues, so a camera and a file read alike.
LANGS = ["de", "es", "fr", "ja", "ko", "pl", "pt_BR", "zh_CN", "zh_TW"]
T = {
"This page cannot change this kind of control (%1).": (
 "Diese Seite kann diese Art von Regler nicht ändern (%1).", "Esta página no puede cambiar este tipo de control (%1).", "Cette page ne peut pas modifier ce type de réglage (%1).",
 "このページでは、この種類の調整項目（%1）は変更できません。", "이 페이지에서는 이 종류의 조절 항목(%1)을 바꿀 수 없습니다.", "Ta strona nie może zmienić tego rodzaju regulacji (%1).",
 "Esta página não pode alterar este tipo de controle (%1).", "此页面无法更改这种类型的调节项（%1）。", "此頁面無法變更這種類型的調整項目（%1）。"),
"The camera only reports this value.": (
 "Die Kamera meldet diesen Wert nur.", "La cámara solo informa de este valor.", "La caméra ne fait que signaler cette valeur.",
 "この値はカメラが報告するだけで、変更できません。", "이 값은 카메라가 알려 주기만 합니다.", "Kamera tylko podaje tę wartość.",
 "A câmera apenas informa este valor.", "摄像头仅报告此值。", "相機僅回報此值。"),
"The camera is not using this control now. Another setting turns it on.": (
 "Die Kamera verwendet diesen Regler gerade nicht. Eine andere Einstellung schaltet ihn ein.", "La cámara no usa este control ahora. Otro ajuste lo activa.", "La caméra n’utilise pas ce réglage pour le moment. Un autre réglage l’active.",
 "カメラは現在この調整項目を使っていません。別の設定を変えると有効になります。", "카메라가 지금은 이 조절 항목을 쓰지 않습니다. 다른 설정을 바꾸면 켜집니다.", "Kamera nie używa teraz tej regulacji. Włącza ją inne ustawienie.",
 "A câmera não está usando este controle agora. Outra configuração o ativa.", "摄像头目前未使用此调节项，需要更改另一项设置才能启用。", "相機目前未使用此調整項目，需要變更另一項設定才能啟用。"),
"%1 is not a V4L2 camera, so its controls are not available here.": (
 "%1 ist keine V4L2-Kamera, daher sind ihre Regler hier nicht verfügbar.", "%1 no es una cámara V4L2, así que sus controles no están disponibles aquí.", "%1 n’est pas une caméra V4L2 : ses réglages ne sont pas disponibles ici.",
 "%1 は V4L2 カメラではないため、ここでは調整項目を使えません。", "%1은(는) V4L2 카메라가 아니므로 여기서 조절 항목을 쓸 수 없습니다.", "%1 nie jest kamerą V4L2, więc jej regulacje nie są tu dostępne.",
 "%1 não é uma câmera V4L2, então seus controles não estão disponíveis aqui.", "%1 不是 V4L2 摄像头，因此这里无法使用它的调节项。", "%1 不是 V4L2 相機，因此這裡無法使用它的調整項目。"),
"No camera is called %1.": (
 "Es gibt keine Kamera namens %1.", "No hay ninguna cámara llamada %1.", "Aucune caméra ne s’appelle %1.",
 "%1 という名前のカメラはありません。", "%1(이)라는 카메라가 없습니다.", "Nie ma kamery o nazwie %1.",
 "Nenhuma câmera se chama %1.", "没有名为 %1 的摄像头。", "沒有名為 %1 的相機。"),
"%1: the saved size and format were not applied. ": (
 "%1: Die gespeicherte Größe und das Format wurden nicht angewendet. ", "%1: no se aplicaron el tamaño y el formato guardados. ", "%1 : la taille et le format enregistrés n’ont pas été appliqués. ",
 "%1: 保存したサイズと形式は適用されませんでした。", "%1: 저장된 크기와 형식을 적용하지 못했습니다. ", "%1: zapisany rozmiar i format nie zostały zastosowane. ",
 "%1: o tamanho e o formato salvos não foram aplicados. ", "%1：未能应用已保存的尺寸和格式。", "%1：未能套用已儲存的尺寸與格式。"),
"%1: the camera no longer lists the control %2.": (
 "%1: Die Kamera führt den Regler %2 nicht mehr auf.", "%1: la cámara ya no lista el control %2.", "%1 : la caméra n’indique plus le réglage %2.",
 "%1: カメラの調整項目一覧に %2 がなくなりました。", "%1: 카메라가 더 이상 조절 항목 %2을(를) 제공하지 않습니다.", "%1: kamera nie podaje już regulacji %2.",
 "%1: a câmera não lista mais o controle %2.", "%1：摄像头不再提供调节项 %2。", "%1：相機不再提供調整項目 %2。"),
"%1: the saved value of %2 was not applied. ": (
 "%1: Der gespeicherte Wert von %2 wurde nicht angewendet. ", "%1: no se aplicó el valor guardado de %2. ", "%1 : la valeur enregistrée de %2 n’a pas été appliquée. ",
 "%1: %2 の保存した値は適用されませんでした。", "%1: %2의 저장된 값을 적용하지 못했습니다. ", "%1: zapisana wartość %2 nie została zastosowana. ",
 "%1: o valor salvo de %2 não foi aplicado. ", "%1：未能应用 %2 的已保存值。", "%1：未能套用 %2 的已儲存值。"),
"This computer's built-in camera has a known fault in how it sends pictures over USB. The system's kernel corrects it, so nothing needs to be done here.": (
 "Die eingebaute Kamera dieses Computers hat einen bekannten Fehler bei der Bildübertragung über USB. Der Kernel des Systems korrigiert ihn, hier ist nichts zu tun.",
 "La cámara integrada de este equipo tiene un fallo conocido al enviar imágenes por USB. El núcleo del sistema lo corrige, así que aquí no hay que hacer nada.",
 "La caméra intégrée de cet ordinateur a un défaut connu dans l’envoi des images par USB. Le noyau du système le corrige : il n’y a rien à faire ici.",
 "このコンピューターの内蔵カメラには、USB での画像送信に既知の不具合があります。システムのカーネルが補正するため、ここで行うことはありません。",
 "이 컴퓨터의 내장 카메라는 USB로 영상을 보내는 방식에 알려진 결함이 있습니다. 시스템 커널이 이를 바로잡으므로 여기서 할 일은 없습니다.",
 "Wbudowana kamera tego komputera ma znaną usterkę w przesyłaniu obrazu przez USB. Jądro systemu ją koryguje, więc nie trzeba tu nic robić.",
 "A câmera integrada deste computador tem uma falha conhecida no envio de imagens por USB. O kernel do sistema a corrige, então não há nada a fazer aqui.",
 "此电脑的内置摄像头在通过 USB 传输图像时存在已知故障。系统内核已对其进行修正，这里无需任何操作。",
 "此電腦的內建相機在透過 USB 傳輸影像時存在已知故障。系統核心已對其進行修正，這裡無需任何操作。"),
"There is no default camera.": (
 "Es gibt keine Standardkamera.", "No hay cámara predeterminada.", "Il n’y a pas de caméra par défaut.",
 "既定のカメラがありません。", "기본 카메라가 없습니다.", "Brak domyślnej kamery.",
 "Não há câmera padrão.", "没有默认摄像头。", "沒有預設相機。"),
"%1 has no control called %2.": (
 "%1 hat keinen Regler namens %2.", "%1 no tiene ningún control llamado %2.", "%1 n’a pas de réglage nommé %2.",
 "%1 に %2 という調整項目はありません。", "%1에는 %2(이)라는 조절 항목이 없습니다.", "%1 nie ma regulacji o nazwie %2.",
 "%1 não tem um controle chamado %2.", "%1 没有名为 %2 的调节项。", "%1 沒有名為 %2 的調整項目。"),
"%1 is not one of the packings. See: sparky-stereo-camera packing %2 list": (
 "%1 gehört nicht zu den Anordnungen. Siehe: sparky-stereo-camera packing %2 list", "%1 no es una de las disposiciones. Consulte: sparky-stereo-camera packing %2 list", "%1 ne fait pas partie des agencements. Voir : sparky-stereo-camera packing %2 list",
 "%1 は指定できる形式ではありません。次を参照: sparky-stereo-camera packing %2 list", "%1은(는) 사용할 수 있는 형식이 아닙니다. 참고: sparky-stereo-camera packing %2 list", "%1 nie jest jednym z układów. Zobacz: sparky-stereo-camera packing %2 list",
 "%1 não é uma das disposições. Veja: sparky-stereo-camera packing %2 list", "%1 不是可用的排列方式。请参阅：sparky-stereo-camera packing %2 list", "%1 不是可用的排列方式。請參閱：sparky-stereo-camera packing %2 list"),
"%1 could not be started. Is PipeWire installed?": (
 "%1 konnte nicht gestartet werden. Ist PipeWire installiert?", "No se pudo iniciar %1. ¿Está instalado PipeWire?", "%1 n’a pas pu démarrer. PipeWire est-il installé ?",
 "%1 を起動できませんでした。PipeWire はインストールされていますか。", "%1을(를) 시작할 수 없습니다. PipeWire가 설치되어 있습니까?", "Nie udało się uruchomić %1. Czy PipeWire jest zainstalowany?",
 "Não foi possível iniciar %1. O PipeWire está instalado?", "无法启动 %1。是否已安装 PipeWire？", "無法啟動 %1。是否已安裝 PipeWire？"),
"%1 did not answer. PipeWire may not be running in this session.": (
 "%1 hat nicht geantwortet. PipeWire läuft in dieser Sitzung möglicherweise nicht.", "%1 no respondió. Puede que PipeWire no esté en marcha en esta sesión.", "%1 n’a pas répondu. PipeWire n’est peut-être pas lancé dans cette session.",
 "%1 から応答がありません。このセッションで PipeWire が動いていない可能性があります。", "%1이(가) 응답하지 않습니다. 이 세션에서 PipeWire가 실행 중이 아닐 수 있습니다.", "%1 nie odpowiada. PipeWire może nie działać w tej sesji.",
 "%1 não respondeu. O PipeWire pode não estar em execução nesta sessão.", "%1 没有响应。此会话中的 PipeWire 可能没有运行。", "%1 沒有回應。此工作階段中的 PipeWire 可能沒有執行。"),
"%1 failed: %2": (
 "%1 ist fehlgeschlagen: %2", "%1 falló: %2", "%1 a échoué : %2",
 "%1 が失敗しました: %2", "%1 실패: %2", "%1 nie powiodło się: %2",
 "%1 falhou: %2", "%1 失败：%2", "%1 失敗：%2"),
"PipeWire's answer could not be read.": (
 "Die Antwort von PipeWire konnte nicht gelesen werden.", "No se pudo leer la respuesta de PipeWire.", "La réponse de PipeWire n’a pas pu être lue.",
 "PipeWire の応答を読み取れませんでした。", "PipeWire의 응답을 읽을 수 없습니다.", "Nie udało się odczytać odpowiedzi PipeWire.",
 "Não foi possível ler a resposta do PipeWire.", "无法读取 PipeWire 的响应。", "無法讀取 PipeWire 的回應。"),
"The preview could not start: PipeWire's loop was not created.": (
 "Die Vorschau konnte nicht starten: Die Schleife von PipeWire wurde nicht erstellt.", "No se pudo iniciar la vista previa: no se creó el bucle de PipeWire.", "L’aperçu n’a pas pu démarrer : la boucle de PipeWire n’a pas été créée.",
 "プレビューを開始できませんでした: PipeWire のループを作成できませんでした。", "미리 보기를 시작할 수 없습니다: PipeWire 루프를 만들지 못했습니다.", "Nie udało się uruchomić podglądu: nie utworzono pętli PipeWire.",
 "Não foi possível iniciar a pré-visualização: o laço do PipeWire não foi criado.", "无法开始预览：未能创建 PipeWire 循环。", "無法開始預覽：未能建立 PipeWire 迴圈。"),
"The preview could not start: PipeWire did not accept the connection.": (
 "Die Vorschau konnte nicht starten: PipeWire hat die Verbindung nicht angenommen.", "No se pudo iniciar la vista previa: PipeWire no aceptó la conexión.", "L’aperçu n’a pas pu démarrer : PipeWire a refusé la connexion.",
 "プレビューを開始できませんでした: PipeWire が接続を受け付けませんでした。", "미리 보기를 시작할 수 없습니다: PipeWire가 연결을 받아들이지 않았습니다.", "Nie udało się uruchomić podglądu: PipeWire nie przyjął połączenia.",
 "Não foi possível iniciar a pré-visualização: o PipeWire não aceitou a conexão.", "无法开始预览：PipeWire 拒绝了连接。", "無法開始預覽：PipeWire 拒絕了連線。"),
"The preview could not start: %1": (
 "Die Vorschau konnte nicht starten: %1", "No se pudo iniciar la vista previa: %1", "L’aperçu n’a pas pu démarrer : %1",
 "プレビューを開始できませんでした: %1", "미리 보기를 시작할 수 없습니다: %1", "Nie udało się uruchomić podglądu: %1",
 "Não foi possível iniciar a pré-visualização: %1", "无法开始预览：%1", "無法開始預覽：%1"),
"The preview stopped: %1": (
 "Die Vorschau wurde beendet: %1", "La vista previa se detuvo: %1", "L’aperçu s’est arrêté : %1",
 "プレビューが停止しました: %1", "미리 보기가 중지되었습니다: %1", "Podgląd został zatrzymany: %1",
 "A pré-visualização parou: %1", "预览已停止：%1", "預覽已停止：%1"),
"Another program is using %1, so it cannot change this now. Close that program and try again.": (
 "Ein anderes Programm verwendet %1, daher lässt sich das jetzt nicht ändern. Schließen Sie das Programm und versuchen Sie es erneut.",
 "Otro programa está usando %1, así que no se puede cambiar ahora. Cierre ese programa e inténtelo de nuevo.",
 "Un autre programme utilise %1 : cela ne peut pas être modifié maintenant. Fermez ce programme et réessayez.",
 "別のプログラムが %1 を使用しているため、今は変更できません。そのプログラムを閉じてからもう一度お試しください。",
 "다른 프로그램이 %1을(를) 사용 중이어서 지금은 바꿀 수 없습니다. 그 프로그램을 닫고 다시 시도하세요.",
 "Inny program używa %1, więc nie można tego teraz zmienić. Zamknij ten program i spróbuj ponownie.",
 "Outro programa está usando %1, então isso não pode ser alterado agora. Feche esse programa e tente de novo.",
 "另一个程序正在使用 %1，因此现在无法更改。请关闭该程序后重试。", "另一個程式正在使用 %1，因此現在無法變更。請關閉該程式後重試。"),
"%1 does not accept this value. The camera keeps its earlier setting.": (
 "%1 akzeptiert diesen Wert nicht. Die Kamera behält ihre bisherige Einstellung.", "%1 no acepta este valor. La cámara conserva su ajuste anterior.", "%1 n’accepte pas cette valeur. La caméra garde son réglage précédent.",
 "%1 はこの値を受け付けません。カメラは以前の設定のままです。", "%1이(가) 이 값을 받아들이지 않습니다. 카메라는 이전 설정을 유지합니다.", "%1 nie przyjmuje tej wartości. Kamera zachowuje poprzednie ustawienie.",
 "%1 não aceita este valor. A câmera mantém a configuração anterior.", "%1 不接受此值，摄像头保持原有设置。", "%1 不接受此值，相機維持原有設定。"),
"%1 does not allow this change now. Another setting of the camera may have to change first.": (
 "%1 erlaubt diese Änderung jetzt nicht. Möglicherweise muss zuerst eine andere Einstellung der Kamera geändert werden.", "%1 no permite este cambio ahora. Quizá haya que cambiar antes otro ajuste de la cámara.", "%1 n’autorise pas ce changement pour le moment. Il faut peut-être d’abord modifier un autre réglage de la caméra.",
 "%1 は今はこの変更を許可していません。先にカメラの別の設定を変える必要があるかもしれません。", "%1이(가) 지금은 이 변경을 허용하지 않습니다. 먼저 카메라의 다른 설정을 바꿔야 할 수 있습니다.", "%1 nie zezwala teraz na tę zmianę. Być może trzeba najpierw zmienić inne ustawienie kamery.",
 "%1 não permite esta alteração agora. Talvez seja preciso mudar antes outra configuração da câmera.", "%1 目前不允许此更改，可能需要先更改摄像头的另一项设置。", "%1 目前不允許此變更，可能需要先變更相機的另一項設定。"),
"%1 is not connected any more. Plug it in again.": (
 "%1 ist nicht mehr verbunden. Schließen Sie sie erneut an.", "%1 ya no está conectada. Vuelva a conectarla.", "%1 n’est plus connectée. Rebranchez-la.",
 "%1 は接続されていません。もう一度接続してください。", "%1의 연결이 끊어졌습니다. 다시 연결하세요.", "%1 nie jest już podłączona. Podłącz ją ponownie.",
 "%1 não está mais conectada. Conecte-a novamente.", "%1 已断开连接，请重新插入。", "%1 已中斷連線，請重新插入。"),
"%1 refused the change (%2).": (
 "%1 hat die Änderung abgelehnt (%2).", "%1 rechazó el cambio (%2).", "%1 a refusé le changement (%2).",
 "%1 は変更を拒否しました（%2）。", "%1이(가) 변경을 거부했습니다(%2).", "%1 odrzuciła zmianę (%2).",
 "%1 recusou a alteração (%2).", "%1 拒绝了此更改（%2）。", "%1 拒絕了此變更（%2）。"),
"No camera found": ("Keine Kamera gefunden", "No se encontró ninguna cámara", "Aucune caméra trouvée", "カメラが見つかりません", "카메라를 찾을 수 없습니다", "Nie znaleziono kamery", "Nenhuma câmera encontrada", "未找到摄像头", "找不到相機"),
"Plug in a camera. It appears here by itself, and you do not have to restart anything.": (
 "Schließen Sie eine Kamera an. Sie erscheint hier von selbst, ein Neustart ist nicht nötig.", "Conecte una cámara. Aparece aquí sola y no hace falta reiniciar nada.", "Branchez une caméra. Elle apparaît ici toute seule, sans rien redémarrer.",
 "カメラを接続してください。ここに自動で表示され、再起動は必要ありません。", "카메라를 연결하세요. 여기에 자동으로 나타나며 다시 시작할 필요가 없습니다.", "Podłącz kamerę. Pojawi się tu sama, nic nie trzeba uruchamiać ponownie.",
 "Conecte uma câmera. Ela aparece aqui sozinha, sem reiniciar nada.", "请插入摄像头。它会自动出现在这里，无需重新启动任何东西。", "請插入相機。它會自動出現在這裡，無需重新啟動任何東西。"),
"Default camera": ("Standardkamera", "Cámara predeterminada", "Caméra par défaut", "既定のカメラ", "기본 카메라", "Domyślna kamera", "Câmera padrão", "默认摄像头", "預設相機"),
"Programs that ask for a camera without choosing one get this camera.": (
 "Programme, die eine Kamera anfordern, ohne eine zu wählen, bekommen diese Kamera.", "Los programas que piden una cámara sin elegir ninguna reciben esta cámara.", "Les programmes qui demandent une caméra sans en choisir une reçoivent celle-ci.",
 "カメラを指定せずに要求したプログラムには、このカメラが使われます。", "카메라를 고르지 않고 요청하는 프로그램은 이 카메라를 받습니다.", "Programy, które proszą o kamerę bez wybierania jej, dostają tę kamerę.",
 "Os programas que pedem uma câmera sem escolher uma recebem esta câmera.", "未指定摄像头就请求摄像头的程序会使用这个摄像头。", "未指定相機就請求相機的程式會使用這個相機。"),
"A program in which you chose a camera keeps your choice. Programs that open the camera themselves, such as those built on Qt Multimedia, do not follow this default yet.": (
 "Ein Programm, in dem Sie eine Kamera gewählt haben, behält Ihre Wahl. Programme, die die Kamera selbst öffnen, etwa mit Qt Multimedia, folgen dieser Standardkamera noch nicht.",
 "Un programa en el que eligió una cámara conserva su elección. Los programas que abren la cámara por sí mismos, como los basados en Qt Multimedia, todavía no siguen esta cámara predeterminada.",
 "Un programme dans lequel vous avez choisi une caméra garde votre choix. Les programmes qui ouvrent eux-mêmes la caméra, comme ceux construits sur Qt Multimedia, ne suivent pas encore cette caméra par défaut.",
 "プログラム内でカメラを選んだ場合は、その選択が保たれます。Qt Multimedia を使うプログラムなど、カメラを自分で開くプログラムは、まだこの既定のカメラに従いません。",
 "프로그램에서 직접 카메라를 고른 경우 그 선택이 유지됩니다. Qt Multimedia를 쓰는 프로그램처럼 카메라를 직접 여는 프로그램은 아직 이 기본 카메라를 따르지 않습니다.",
 "Program, w którym wybrano kamerę, zachowuje ten wybór. Programy otwierające kamerę samodzielnie, na przykład oparte na Qt Multimedia, jeszcze nie stosują tej kamery domyślnej.",
 "Um programa em que você escolheu uma câmera mantém a sua escolha. Programas que abrem a câmera por conta própria, como os baseados no Qt Multimedia, ainda não seguem esta câmera padrão.",
 "在某个程序中选择过摄像头时，该程序保留您的选择。自行打开摄像头的程序（例如基于 Qt Multimedia 的程序）暂时不会遵循此默认摄像头。",
 "在某個程式中選擇過相機時，該程式會保留您的選擇。自行開啟相機的程式（例如以 Qt Multimedia 為基礎的程式）目前尚不會遵循此預設相機。"),
"Settings for:": ("Einstellungen für:", "Ajustes de:", "Réglages de :", "設定の対象:", "설정 대상:", "Ustawienia dla:", "Configurações de:", "设置对象：", "設定對象："),
"This preview cannot show that packing. Other programs can.": (
 "Diese Vorschau kann diese Anordnung nicht zeigen. Andere Programme können es.", "Esta vista previa no puede mostrar esa disposición. Otros programas sí.", "Cet aperçu ne peut pas montrer cet agencement. D’autres programmes le peuvent.",
 "このプレビューではその形式を表示できません。ほかのプログラムでは表示できます。", "이 미리 보기는 그 형식을 보여 줄 수 없습니다. 다른 프로그램은 가능합니다.", "Ten podgląd nie może pokazać tego układu. Inne programy mogą.",
 "Esta pré-visualização não pode mostrar essa disposição. Outros programas podem.", "此预览无法显示这种排列方式，其他程序可以。", "此預覽無法顯示這種排列方式，其他程式可以。"),
"Starting the preview…": ("Vorschau wird gestartet …", "Iniciando la vista previa…", "Démarrage de l’aperçu…", "プレビューを開始しています…", "미리 보기를 시작하는 중…", "Uruchamianie podglądu…", "Iniciando a pré-visualização…", "正在启动预览…", "正在啟動預覽…"),
"Picture": ("Bild", "Imagen", "Image", "画像", "화면", "Obraz", "Imagem", "画面", "畫面"),
"Format:": ("Format:", "Formato:", "Format :", "形式:", "형식:", "Format:", "Formato:", "格式：", "格式："),
"Size:": ("Größe:", "Tamaño:", "Taille :", "サイズ:", "크기:", "Rozmiar:", "Tamanho:", "尺寸：", "尺寸："),
"%1 × %2 to %3 × %4": ("%1 × %2 bis %3 × %4", "%1 × %2 a %3 × %4", "%1 × %2 à %3 × %4", "%1 × %2 から %3 × %4", "%1 × %2 ~ %3 × %4", "%1 × %2 do %3 × %4", "%1 × %2 a %3 × %4", "%1 × %2 至 %3 × %4", "%1 × %2 至 %3 × %4"),
"%1 × %2": ("%1 × %2",) * 9,
"Frames per second:": ("Bilder pro Sekunde:", "Fotogramas por segundo:", "Images par seconde :", "毎秒フレーム数:", "초당 프레임 수:", "Klatki na sekundę:", "Quadros por segundo:", "每秒帧数：", "每秒幀數："),
"Programs that choose their own size and format are not changed by this.": (
 "Programme, die Größe und Format selbst wählen, werden dadurch nicht geändert.", "Los programas que eligen su propio tamaño y formato no cambian con esto.", "Les programmes qui choisissent eux-mêmes leur taille et leur format ne sont pas modifiés par ceci.",
 "サイズや形式を自分で選ぶプログラムには影響しません。", "크기와 형식을 직접 고르는 프로그램에는 영향을 주지 않습니다.", "Programy, które same wybierają rozmiar i format, nie są przez to zmieniane.",
 "Os programas que escolhem o próprio tamanho e formato não são alterados por isto.", "自行选择尺寸和格式的程序不受此影响。", "自行選擇尺寸與格式的程式不受此影響。"),
"Camera controls": ("Regler der Kamera", "Controles de la cámara", "Réglages de la caméra", "カメラの調整項目", "카메라 조절 항목", "Regulacje kamery", "Controles da câmera", "摄像头调节项", "相機調整項目"),
"Reset to the camera's defaults": (
 "Auf die Standardwerte der Kamera zurücksetzen", "Restablecer los valores predeterminados de la cámara", "Rétablir les valeurs par défaut de la caméra",
 "カメラの初期値に戻す", "카메라 기본값으로 되돌리기", "Przywróć domyślne ustawienia kamery", "Redefinir para os padrões da câmera", "恢复为摄像头默认值", "還原為相機預設值"),
"Two lenses": ("Zwei Objektive", "Dos objetivos", "Deux objectifs", "2 つのレンズ", "렌즈 두 개", "Dwa obiektywy", "Duas lentes", "双镜头", "雙鏡頭"),
"Show the pair in 3D": ("Paar in 3D zeigen", "Mostrar el par en 3D", "Afficher la paire en 3D", "ペアを 3D で表示", "쌍을 3D로 보기", "Pokaż parę w 3D", "Mostrar o par em 3D", "以 3D 显示这一对画面", "以 3D 顯示這一對畫面"),
"Camera preview in 3D": ("Kameravorschau in 3D", "Vista previa de la cámara en 3D", "Aperçu de la caméra en 3D", "カメラのプレビュー（3D）", "카메라 미리 보기(3D)", "Podgląd kamery w 3D", "Pré-visualização da câmera em 3D", "摄像头 3D 预览", "相機 3D 預覽"),
"3D Input Format:": ("3D-Eingabeformat:", "Formato de entrada 3D:", "Format d’entrée 3D :", "3D 入力形式:", "3D 입력 형식:", "Format wejściowy 3D:", "Formato de entrada 3D:", "3D 输入格式：", "3D 輸入格式："),
"A camera with two lenses sends both pictures in one. Say how it packs them, and the preview shows the pair in 3D. A camera with one lens stays \"Not 3D\".": (
 "Eine Kamera mit zwei Objektiven sendet beide Bilder in einem. Geben Sie an, wie sie angeordnet sind, dann zeigt die Vorschau das Paar in 3D. Eine Kamera mit einem Objektiv bleibt auf „Nicht 3D“.",
 "Una cámara con dos objetivos envía las dos imágenes en una. Indique cómo las empaqueta y la vista previa mostrará el par en 3D. Una cámara con un objetivo se queda en «No es 3D».",
 "Une caméra à deux objectifs envoie les deux images en une seule. Indiquez comment elles sont assemblées et l’aperçu montrera la paire en 3D. Une caméra à un objectif reste sur « Pas en 3D ».",
 "レンズが 2 つあるカメラは、2 つの画像を 1 枚にまとめて送ります。まとめ方を選ぶと、プレビューで 3D のペアとして表示されます。レンズが 1 つのカメラは「3D ではない」のままにします。",
 "렌즈가 두 개인 카메라는 두 영상을 하나로 묶어 보냅니다. 묶는 방식을 지정하면 미리 보기에 3D 쌍으로 표시됩니다. 렌즈가 하나인 카메라는 \"3D 아님\"으로 둡니다.",
 "Kamera z dwoma obiektywami wysyła oba obrazy w jednym. Wskaż, jak są ułożone, a podgląd pokaże parę w 3D. Kamera z jednym obiektywem zostaje na „Nie 3D”.",
 "Uma câmera com duas lentes envia as duas imagens em uma. Diga como ela as empacota e a pré-visualização mostra o par em 3D. Uma câmera com uma lente fica em \"Não é 3D\".",
 "双镜头摄像头会把两路画面合成一幅发送。指明合成方式后，预览会以 3D 显示这一对画面。单镜头摄像头保持“非 3D”。",
 "雙鏡頭相機會把兩路畫面合成一幅傳送。指明合成方式後，預覽會以 3D 顯示這一對畫面。單鏡頭相機維持「非 3D」。"),
}
