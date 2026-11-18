# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# The sentences of the tray and of the settings page (English is the source text), then de, es, fr, ja, ko, pl, pt_BR, zh_CN, zh_TW.
LANGS = ["de", "es", "fr", "ja", "ko", "pl", "pt_BR", "zh_CN", "zh_TW"]
T = {
"At login:": ("Beim Anmelden:", "Al iniciar sesión:", "À la connexion :", "ログイン時:", "로그인할 때:", "Po zalogowaniu:", "Ao entrar:", "登录时：", "登入時："),
"Certificates, token drivers and PINs are set in the signer's own window. What the system trusts for secure connections is Sparky CA's.": (
 "Zertifikate, Token-Treiber und PINs werden im eigenen Fenster des Signierers eingestellt. Was das System bei sicheren Verbindungen vertraut, ist Sache von Sparky CA.",
 "Los certificados, los controladores de token y los PIN se configuran en la propia ventana del firmador. En qué confía el sistema para las conexiones seguras lo decide Sparky CA.",
 "Les certificats, les pilotes de jeton et les codes PIN se règlent dans la fenêtre du signataire elle-même. Ce à quoi le système fait confiance pour les connexions sécurisées relève de Sparky CA.",
 "証明書、トークンのドライバー、PIN は署名プログラム自身のウィンドウで設定します。安全な接続でシステムが信頼するものは Sparky CA が扱います。",
 "인증서, 토큰 드라이버, PIN은 서명 프로그램 자체 창에서 설정합니다. 보안 연결에서 시스템이 신뢰하는 대상은 Sparky CA가 관리합니다.",
 "Certyfikaty, sterowniki tokenów i PIN-y ustawia się w oknie samego programu. To, czemu system ufa w połączeniach szyfrowanych, należy do Sparky CA.",
 "Certificados, drivers de token e PINs são configurados na própria janela do assinador. Em que o sistema confia nas conexões seguras é assunto do Sparky CA.",
 "证书、令牌驱动程序和 PIN 在签名程序自己的窗口中设置。系统在安全连接中信任什么，由 Sparky CA 负责。",
 "憑證、權杖驅動程式和 PIN 在簽署程式自己的視窗中設定。系統在安全連線中信任什麼，由 Sparky CA 負責。"),
"Check CNJ's update address": ("Update-Adresse des CNJ prüfen", "Comprobar la dirección de actualización del CNJ", "Vérifier l’adresse de mise à jour du CNJ", "CNJ の更新アドレスを確認", "CNJ 업데이트 주소 확인", "Sprawdź adres aktualizacji CNJ", "Verificar o endereço de atualização do CNJ", "检查 CNJ 的更新地址", "檢查 CNJ 的更新位址"),
"CNJ's address:": ("Adresse des CNJ:", "Dirección del CNJ:", "Adresse du CNJ :", "CNJ のアドレス:", "CNJ 주소:", "Adres CNJ:", "Endereço do CNJ:", "CNJ 的地址：", "CNJ 的位址："),
"CNJ's update address could not be read on %1: %2": (
 "Die Update-Adresse des CNJ konnte am %1 nicht gelesen werden: %2", "No se pudo leer la dirección de actualización del CNJ el %1: %2", "L’adresse de mise à jour du CNJ n’a pas pu être lue le %1 : %2",
 "%1 に CNJ の更新アドレスを読み取れませんでした: %2", "%1에 CNJ의 업데이트 주소를 읽지 못했습니다: %2", "Nie udało się odczytać adresu aktualizacji CNJ (%1): %2", "Não foi possível ler o endereço de atualização do CNJ em %1: %2",
 "%1 无法读取 CNJ 的更新地址：%2", "%1 無法讀取 CNJ 的更新位址：%2"),
"CNJ's update address has not been looked at yet.": (
 "Die Update-Adresse des CNJ wurde noch nicht geprüft.", "Todavía no se ha consultado la dirección de actualización del CNJ.", "L’adresse de mise à jour du CNJ n’a pas encore été consultée.",
 "CNJ の更新アドレスはまだ確認していません。", "CNJ의 업데이트 주소를 아직 확인하지 않았습니다.", "Adres aktualizacji CNJ nie został jeszcze sprawdzony.", "O endereço de atualização do CNJ ainda não foi consultado.", "尚未查看 CNJ 的更新地址。", "尚未查看 CNJ 的更新位址。"),
"Installed version:": ("Installierte Version:", "Versión instalada:", "Version installée :", "インストール済みのバージョン:", "설치된 버전:", "Zainstalowana wersja:", "Versão instalada:", "已安装的版本：", "已安裝的版本："),
"Install it from the app center.": ("Installieren Sie es über das Anwendungszentrum.", "Instálelo desde el centro de aplicaciones.", "Installez-le depuis le centre d’applications.", "アプリセンターからインストールしてください。", "앱 센터에서 설치하세요.", "Zainstaluj go z centrum aplikacji.", "Instale-o pela central de aplicativos.", "请从应用中心安装。", "請從應用程式中心安裝。"),
"Looking for the signer…": ("Der Signierer wird gesucht …", "Buscando el firmador…", "Recherche du signataire…", "署名プログラムを探しています…", "서명 프로그램을 찾는 중…", "Szukanie podpisującego…", "Procurando o assinador…", "正在查找签名程序…", "正在尋找簽署程式…"),
"none": ("keine", "ninguna", "aucune", "なし", "없음", "brak", "nenhuma", "无", "無"),
"On %1 CNJ's update address named version %2.": (
 "Am %1 nannte die Update-Adresse des CNJ die Version %2.", "El %1 la dirección de actualización del CNJ indicó la versión %2.", "Le %1, l’adresse de mise à jour du CNJ indiquait la version %2.",
 "%1 に CNJ の更新アドレスが示したバージョンは %2 です。", "%1에 CNJ의 업데이트 주소가 알려 준 버전은 %2입니다.", "W dniu %1 adres aktualizacji CNJ podawał wersję %2.", "Em %1 o endereço de atualização do CNJ indicava a versão %2.",
 "%1 时，CNJ 的更新地址给出的版本是 %2。", "%1 時，CNJ 的更新位址給出的版本是 %2。"),
"Open the certificate manager": ("Zertifikatsverwaltung öffnen", "Abrir el gestor de certificados", "Ouvrir le gestionnaire de certificats", "証明書マネージャーを開く", "인증서 관리자 열기", "Otwórz menedżera certyfikatów", "Abrir o gerenciador de certificados", "打开证书管理器", "開啟憑證管理員"),
"Open the signer": ("Signierer öffnen", "Abrir el firmador", "Ouvrir le signataire", "署名プログラムを開く", "서명 프로그램 열기", "Otwórz podpisującego", "Abrir o assinador", "打开签名程序", "開啟簽署程式"),
"PJeOffice Pro": ("PJeOffice Pro",) * 9,
"PJeOffice Pro is not installed.": ("PJeOffice Pro ist nicht installiert.", "PJeOffice Pro no está instalado.", "PJeOffice Pro n’est pas installé.", "PJeOffice Pro はインストールされていません。", "PJeOffice Pro가 설치되어 있지 않습니다.", "PJeOffice Pro nie jest zainstalowany.", "O PJeOffice Pro não está instalado.", "未安装 PJeOffice Pro。", "未安裝 PJeOffice Pro。"),
"PJeOffice Pro is not installed. Install it from the app center.": (
 "PJeOffice Pro ist nicht installiert. Installieren Sie es über das Anwendungszentrum.", "PJeOffice Pro no está instalado. Instálelo desde el centro de aplicaciones.", "PJeOffice Pro n’est pas installé. Installez-le depuis le centre d’applications.",
 "PJeOffice Pro はインストールされていません。アプリセンターからインストールしてください。", "PJeOffice Pro가 설치되어 있지 않습니다. 앱 센터에서 설치하세요.", "PJeOffice Pro nie jest zainstalowany. Zainstaluj go z centrum aplikacji.",
 "O PJeOffice Pro não está instalado. Instale-o pela central de aplicativos.", "未安装 PJeOffice Pro。请从应用中心安装。", "未安裝 PJeOffice Pro。請從應用程式中心安裝。"),
"Previous version kept:": ("Frühere Version bleibt erhalten:", "Versión anterior conservada:", "Version précédente conservée :", "保持されている以前のバージョン:", "보관 중인 이전 버전:", "Zachowana poprzednia wersja:", "Versão anterior mantida:", "保留的旧版本：", "保留的舊版本："),
"Quit this tray entry (the signer keeps running)": (
 "Dieses Symbol beenden (der Signierer läuft weiter)", "Cerrar esta entrada de la bandeja (el firmador sigue en marcha)", "Quitter cette icône (le signataire continue de tourner)",
 "このトレイ項目を終了（署名プログラムは動き続けます）", "이 트레이 항목 끝내기(서명 프로그램은 계속 실행됩니다)", "Zamknij tę ikonę zasobnika (podpisujący działa dalej)", "Encerrar este item da bandeja (o assinador continua em execução)",
 "退出此托盘项（签名程序继续运行）", "結束此系統匣項目（簽署程式繼續執行）"),
"Restart the signer": ("Signierer neu starten", "Reiniciar el firmador", "Redémarrer le signataire", "署名プログラムを再起動", "서명 프로그램 다시 시작", "Uruchom ponownie podpisującego", "Reiniciar o assinador", "重新启动签名程序", "重新啟動簽署程式"),
"Restart the signer now? Finish any signing first: a signing in progress would be cut.": (
 "Signierer jetzt neu starten? Schließen Sie zuerst jedes Signieren ab: Ein laufendes Signieren würde abgebrochen.", "¿Reiniciar el firmador ahora? Termine antes cualquier firma: una firma en curso se cortaría.",
 "Redémarrer le signataire maintenant ? Terminez d’abord toute signature : une signature en cours serait interrompue.", "署名プログラムを今すぐ再起動しますか？ 先に署名を終えてください。署名の途中だと中断されます。",
 "서명 프로그램을 지금 다시 시작할까요? 먼저 서명을 마치세요. 진행 중인 서명은 중단됩니다.", "Uruchomić teraz ponownie podpisującego? Najpierw dokończ podpisywanie: trwające podpisywanie zostałoby przerwane.",
 "Reiniciar o assinador agora? Termine antes qualquer assinatura: uma assinatura em andamento seria cortada.", "现在重新启动签名程序吗？请先完成所有签名：正在进行的签名会被中断。", "現在重新啟動簽署程式嗎？請先完成所有簽署：進行中的簽署會被中斷。"),
"Reviewed version:": ("Geprüfte Version:", "Versión revisada:", "Version examinée :", "確認済みのバージョン:", "검토된 버전:", "Sprawdzona wersja:", "Versão revisada:", "已审核的版本：", "已審核的版本："),
"Reviewed version %1 is waiting; %2 is in use.": (
 "Die geprüfte Version %1 wartet; %2 ist in Gebrauch.", "La versión revisada %1 está en espera; se usa la %2.", "La version examinée %1 attend ; la %2 est en service.",
 "確認済みのバージョン %1 が待機中で、%2 を使用中です。", "검토된 버전 %1이(가) 대기 중이며 %2을(를) 사용 중입니다.", "Sprawdzona wersja %1 czeka; używana jest %2.", "A versão revisada %1 está à espera; a %2 está em uso.",
 "已审核的版本 %1 正在等待，当前使用 %2。", "已審核的版本 %1 正在等待，目前使用 %2。"),
"Settings…": ("Einstellungen …", "Ajustes…", "Configuration…", "設定…", "설정…", "Ustawienia…", "Configurações…", "设置…", "設定…"),
"Start PJeOffice Pro when I log in": ("PJeOffice Pro bei meiner Anmeldung starten", "Iniciar PJeOffice Pro al iniciar mi sesión", "Démarrer PJeOffice Pro à ma connexion", "ログイン時に PJeOffice Pro を起動する", "로그인할 때 PJeOffice Pro 시작", "Uruchamiaj PJeOffice Pro po moim zalogowaniu", "Iniciar o PJeOffice Pro quando eu entrar", "登录时启动 PJeOffice Pro", "登入時啟動 PJeOffice Pro"),
"The certificate manager (Kleopatra) is not installed.": (
 "Die Zertifikatsverwaltung (Kleopatra) ist nicht installiert.", "El gestor de certificados (Kleopatra) no está instalado.", "Le gestionnaire de certificats (Kleopatra) n’est pas installé.",
 "証明書マネージャー（Kleopatra）はインストールされていません。", "인증서 관리자(Kleopatra)가 설치되어 있지 않습니다.", "Menedżer certyfikatów (Kleopatra) nie jest zainstalowany.", "O gerenciador de certificados (Kleopatra) não está instalado.", "未安装证书管理器（Kleopatra）。", "未安裝憑證管理員（Kleopatra）。"),
"The installed version is the reviewed one.": (
 "Die installierte Version ist die geprüfte.", "La versión instalada es la revisada.", "La version installée est celle qui a été examinée.", "インストール済みのバージョンは確認済みのものです。", "설치된 버전이 검토된 버전입니다.",
 "Zainstalowana wersja jest sprawdzoną wersją.", "A versão instalada é a revisada.", "已安装的版本就是已审核的版本。", "已安裝的版本就是已審核的版本。"),
"The signer answers on this computer.": (
 "Der Signierer antwortet auf diesem Computer.", "El firmador responde en este equipo.", "Le signataire répond sur cet ordinateur.", "署名プログラムはこのコンピューターで応答しています。", "서명 프로그램이 이 컴퓨터에서 응답합니다.",
 "Podpisujący odpowiada na tym komputerze.", "O assinador responde neste computador.", "签名程序在此计算机上有响应。", "簽署程式在此電腦上有回應。"),
"The signer answers on this computer. The system's certificate list changed: restart the signer to use it.": (
 "Der Signierer antwortet auf diesem Computer. Die Zertifikatsliste des Systems hat sich geändert: Starten Sie den Signierer neu, um sie zu verwenden.",
 "El firmador responde en este equipo. La lista de certificados del sistema cambió: reinicie el firmador para usarla.",
 "Le signataire répond sur cet ordinateur. La liste de certificats du système a changé : redémarrez le signataire pour l’utiliser.",
 "署名プログラムはこのコンピューターで応答しています。システムの証明書一覧が変わりました。使うには署名プログラムを再起動してください。",
 "서명 프로그램이 이 컴퓨터에서 응답합니다. 시스템의 인증서 목록이 바뀌었습니다. 사용하려면 서명 프로그램을 다시 시작하세요.",
 "Podpisujący odpowiada na tym komputerze. Lista certyfikatów systemu się zmieniła: uruchom ponownie podpisującego, aby jej użyć.",
 "O assinador responde neste computador. A lista de certificados do sistema mudou: reinicie o assinador para usá-la.",
 "签名程序在此计算机上有响应。系统的证书列表已更改：请重新启动签名程序以使用它。", "簽署程式在此電腦上有回應。系統的憑證清單已變更：請重新啟動簽署程式以使用它。"),
"The signer does not answer on this computer. Open it from this menu.": (
 "Der Signierer antwortet auf diesem Computer nicht. Öffnen Sie ihn über dieses Menü.", "El firmador no responde en este equipo. Ábralo desde este menú.", "Le signataire ne répond pas sur cet ordinateur. Ouvrez-le depuis ce menu.",
 "署名プログラムはこのコンピューターで応答していません。このメニューから開いてください。", "서명 프로그램이 이 컴퓨터에서 응답하지 않습니다. 이 메뉴에서 여세요.", "Podpisujący nie odpowiada na tym komputerze. Otwórz go z tego menu.",
 "O assinador não responde neste computador. Abra-o por este menu.", "签名程序在此计算机上没有响应。请从此菜单打开它。", "簽署程式在此電腦上沒有回應。請從此選單開啟它。"),
"The signer does not answer on this computer. Open it with the button below.": (
 "Der Signierer antwortet auf diesem Computer nicht. Öffnen Sie ihn mit der Schaltfläche unten.", "El firmador no responde en este equipo. Ábralo con el botón de abajo.", "Le signataire ne répond pas sur cet ordinateur. Ouvrez-le avec le bouton ci-dessous.",
 "署名プログラムはこのコンピューターで応答していません。下のボタンで開いてください。", "서명 프로그램이 이 컴퓨터에서 응답하지 않습니다. 아래 버튼으로 여세요.", "Podpisujący nie odpowiada na tym komputerze. Otwórz go przyciskiem poniżej.",
 "O assinador não responde neste computador. Abra-o com o botão abaixo.", "签名程序在此计算机上没有响应。请用下面的按钮打开它。", "簽署程式在此電腦上沒有回應。請用下方的按鈕開啟它。"),
"The signer stopped answering.": ("Der Signierer antwortet nicht mehr.", "El firmador dejó de responder.", "Le signataire ne répond plus.", "署名プログラムが応答しなくなりました。", "서명 프로그램이 응답하지 않게 되었습니다.", "Podpisujący przestał odpowiadać.", "O assinador parou de responder.", "签名程序不再响应。", "簽署程式不再回應。"),
"The system's certificate list changed. Restart the signer to use it.": (
 "Die Zertifikatsliste des Systems hat sich geändert. Starten Sie den Signierer neu, um sie zu verwenden.", "La lista de certificados del sistema cambió. Reinicie el firmador para usarla.",
 "La liste de certificats du système a changé. Redémarrez le signataire pour l’utiliser.", "システムの証明書一覧が変わりました。使うには署名プログラムを再起動してください。", "시스템의 인증서 목록이 바뀌었습니다. 사용하려면 서명 프로그램을 다시 시작하세요.",
 "Lista certyfikatów systemu się zmieniła. Uruchom ponownie podpisującego, aby jej użyć.", "A lista de certificados do sistema mudou. Reinicie o assinador para usá-la.", "系统的证书列表已更改。请重新启动签名程序以使用它。", "系統的憑證清單已變更。請重新啟動簽署程式以使用它。"),
"Update:": ("Aktualisierung:", "Actualización:", "Mise à jour :", "更新:", "업데이트:", "Aktualizacja:", "Atualização:", "更新：", "更新："),
"Up to date: version %1 is the reviewed one. Updates arrive with the package, after each new version is reviewed.": (
 "Aktuell: Version %1 ist die geprüfte. Aktualisierungen kommen mit dem Paket, nachdem jede neue Version geprüft wurde.", "Al día: la versión %1 es la revisada. Las actualizaciones llegan con el paquete, después de revisar cada versión nueva.",
 "À jour : la version %1 est celle qui a été examinée. Les mises à jour arrivent avec le paquet, après examen de chaque nouvelle version.", "最新です。バージョン %1 が確認済みのものです。更新は、新しいバージョンが確認されたあと、パッケージとともに届きます。",
 "최신 상태입니다. 버전 %1이(가) 검토된 버전입니다. 업데이트는 새 버전이 검토된 뒤 패키지와 함께 옵니다.", "Aktualne: wersja %1 jest sprawdzoną wersją. Aktualizacje przychodzą z pakietem, po sprawdzeniu każdej nowej wersji.",
 "Em dia: a versão %1 é a revisada. As atualizações chegam com o pacote, depois de cada versão nova ser revisada.", "已是最新：版本 %1 就是已审核的版本。更新会在每个新版本审核后随软件包一起到来。", "已是最新：版本 %1 就是已審核的版本。更新會在每個新版本審核後隨套件一起到來。"),
"Version %1": ("Version %1", "Versión %1", "Version %1", "バージョン %1", "버전 %1", "Wersja %1", "Versão %1", "版本 %1", "版本 %1"),
"Version %1 is in use. The reviewed version %2 did not install: see the Problems page.": (
 "Version %1 ist in Gebrauch. Die geprüfte Version %2 wurde nicht installiert: siehe die Seite „Probleme“.", "Se usa la versión %1. La versión revisada %2 no se instaló: vea la página Problemas.",
 "La version %1 est en service. La version examinée %2 n’a pas été installée : voir la page Problèmes.", "バージョン %1 を使用中です。確認済みのバージョン %2 はインストールされませんでした。「問題」ページをご覧ください。",
 "버전 %1을(를) 사용 중입니다. 검토된 버전 %2이(가) 설치되지 않았습니다. 문제 페이지를 보세요.", "Używana jest wersja %1. Sprawdzona wersja %2 nie została zainstalowana: zobacz stronę Problemy.",
 "A versão %1 está em uso. A versão revisada %2 não foi instalada: veja a página Problemas.", "正在使用版本 %1。已审核的版本 %2 未能安装：请查看“问题”页面。", "正在使用版本 %1。已審核的版本 %2 未能安裝：請查看「問題」頁面。"),
}
# the notification events and the files that name the program (desktop entries, the service menu, the settings page)
FILES = {
 "Comment": ("Sign court documents with PJeOffice Pro", ("PJeOffice Pro: Gerichtsdokumente signieren", "Firmar documentos judiciales con PJeOffice Pro", "Signer des documents judiciaires avec PJeOffice Pro", "PJeOffice Pro で裁判所の書類に署名する", "PJeOffice Pro로 법원 문서에 서명", "Podpisywanie dokumentów sądowych w PJeOffice Pro", "Assinar documentos judiciais com o PJeOffice Pro", "使用 PJeOffice Pro 为法院文件签名", "使用 PJeOffice Pro 為法院文件簽署")),
 "SignAction": ("Sign with PJeOffice Pro (creates a CAdES file beside the PDF)", ("Mit PJeOffice Pro signieren (erzeugt eine CAdES-Datei neben dem PDF)", "Firmar con PJeOffice Pro (crea un archivo CAdES junto al PDF)", "Signer avec PJeOffice Pro (crée un fichier CAdES à côté du PDF)", "PJeOffice Pro で署名（PDF の隣に CAdES ファイルを作成）", "PJeOffice Pro로 서명(PDF 옆에 CAdES 파일을 만듭니다)", "Podpisz w PJeOffice Pro (tworzy plik CAdES obok PDF)", "Assinar com o PJeOffice Pro (cria um arquivo CAdES ao lado do PDF)", "使用 PJeOffice Pro 签名（在 PDF 旁生成 CAdES 文件）", "使用 PJeOffice Pro 簽署（在 PDF 旁產生 CAdES 檔案）")),
 "TrayName": ("PJeOffice Pro tray entry", ("PJeOffice-Pro-Symbol im Systemabschnitt", "Entrada de bandeja de PJeOffice Pro", "Icône de PJeOffice Pro dans la zone de notification", "PJeOffice Pro のトレイ項目", "PJeOffice Pro 트레이 항목", "Ikona PJeOffice Pro w zasobniku", "Item de bandeja do PJeOffice Pro", "PJeOffice Pro 托盘项", "PJeOffice Pro 系統匣項目")),
 "SignerStopped": ("The signer stopped answering", ("Der Signierer antwortet nicht mehr", "El firmador dejó de responder", "Le signataire ne répond plus", "署名プログラムが応答しなくなりました", "서명 프로그램이 응답하지 않게 되었습니다", "Podpisujący przestał odpowiadać", "O assinador parou de responder", "签名程序不再响应", "簽署程式不再回應")),
 "UpdateChecked": ("CNJ's update address was checked", ("Die Update-Adresse des CNJ wurde geprüft", "Se consultó la dirección de actualización del CNJ", "L’adresse de mise à jour du CNJ a été vérifiée", "CNJ の更新アドレスを確認しました", "CNJ 업데이트 주소를 확인했습니다", "Sprawdzono adres aktualizacji CNJ", "O endereço de atualização do CNJ foi consultado", "已检查 CNJ 的更新地址", "已檢查 CNJ 的更新位址")),
 "SettingsDescription": ("Start at login, the installed version and the update state", ("Start bei der Anmeldung, installierte Version und Aktualisierungsstand", "Inicio al entrar, versión instalada y estado de la actualización", "Démarrage à la connexion, version installée et état de la mise à jour", "ログイン時の起動、インストール済みのバージョン、更新の状態", "로그인 시 시작, 설치된 버전, 업데이트 상태", "Uruchamianie po zalogowaniu, zainstalowana wersja i stan aktualizacji", "Início ao entrar, versão instalada e estado da atualização", "登录时启动、已安装的版本和更新状态", "登入時啟動、已安裝的版本和更新狀態")),
}
