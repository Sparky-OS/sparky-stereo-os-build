#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Writes po/<lang>/kcm_ums.po from the template (xgettext output) and the tables below."""
import re, subprocess, sys, os

T = {
 "pl": ["Serwer multimediów:", "Udostępniaj telewizorom i urządzeniom w sieci", "Serwer jest włączony. Poniższe foldery są widoczne dla każdego urządzenia w Twojej sieci.", "Serwer jest wyłączony. Nic nie jest udostępniane.", "Nazwa serwera:", "Udostępniane foldery:", "Usuń", "Żadne foldery nie są udostępniane.", "Dodaj folder…", "Przywróć domyślne foldery", "Otwórz interfejs WWW", "Urządzenia, transkodowanie i wszystko inne ustawia się w interfejsie WWW.", "Wybierz folder do udostępnienia", "Nie udało się zmienić serwera multimediów: %1"],
 "pt_BR": ["Servidor de mídia:", "Compartilhar com as TVs e dispositivos da rede", "O servidor está ligado. As pastas abaixo ficam visíveis para todos os dispositivos da sua rede.", "O servidor está desligado. Nada é compartilhado.", "Nome do servidor:", "Pastas compartilhadas:", "Remover", "Nenhuma pasta é compartilhada.", "Adicionar pasta…", "Restaurar pastas padrão", "Abrir a interface web", "Dispositivos, transcodificação e todo o resto são configurados na interface web.", "Escolher uma pasta para compartilhar", "Não foi possível alterar o servidor de mídia: %1"],
 "fr": ["Serveur multimédia :", "Partager avec les téléviseurs et appareils du réseau", "Le serveur est activé. Les dossiers ci-dessous sont visibles par tous les appareils de votre réseau.", "Le serveur est désactivé. Rien n'est partagé.", "Nom du serveur :", "Dossiers partagés :", "Supprimer", "Aucun dossier n'est partagé.", "Ajouter un dossier…", "Rétablir les dossiers par défaut", "Ouvrir l'interface web", "Les appareils, le transcodage et tout le reste se règlent dans l'interface web.", "Choisir un dossier à partager", "Impossible de modifier le serveur multimédia : %1"],
 "ja": ["メディアサーバー：", "ネットワーク上のテレビや機器と共有する", "サーバーはオンです。下のフォルダーは、ネットワーク上のすべての機器から見えます。", "サーバーはオフです。何も共有されていません。", "サーバー名：", "共有フォルダー：", "削除", "共有しているフォルダーはありません。", "フォルダーを追加…", "既定のフォルダーに戻す", "ウェブインターフェースを開く", "機器、トランスコード、その他の設定はウェブインターフェースで行います。", "共有するフォルダーを選択", "メディアサーバーを変更できませんでした：%1"],
 "ko": ["미디어 서버:", "네트워크의 TV 및 기기와 공유", "서버가 켜져 있습니다. 아래 폴더는 네트워크의 모든 기기에 보입니다.", "서버가 꺼져 있습니다. 공유되는 항목이 없습니다.", "서버 이름:", "공유 폴더:", "제거", "공유하는 폴더가 없습니다.", "폴더 추가…", "기본 폴더 복원", "웹 인터페이스 열기", "기기, 트랜스코딩 및 그 밖의 모든 설정은 웹 인터페이스에서 합니다.", "공유할 폴더 선택", "미디어 서버를 변경할 수 없습니다: %1"],
 "zh_CN": ["媒体服务器：", "与网络中的电视和设备共享", "服务器已开启。下面的文件夹对网络中的所有设备可见。", "服务器已关闭。未共享任何内容。", "服务器名称：", "共享文件夹：", "移除", "没有共享的文件夹。", "添加文件夹…", "恢复默认文件夹", "打开网页界面", "设备、转码和其他所有设置都在网页界面中进行。", "选择要共享的文件夹", "无法更改媒体服务器：%1"],
 "zh_TW": ["媒體伺服器：", "與網路中的電視和裝置分享", "伺服器已開啟。下列資料夾對網路中的所有裝置可見。", "伺服器已關閉。未分享任何內容。", "伺服器名稱：", "分享的資料夾：", "移除", "沒有分享的資料夾。", "新增資料夾…", "還原預設資料夾", "開啟網頁介面", "裝置、轉碼及其他所有設定都在網頁介面中進行。", "選擇要分享的資料夾", "無法變更媒體伺服器：%1"],
}
ORDER = ["Media server:", "Share with the TVs and devices on the network",
 "The server is on. The folders below are visible to every device on your network.", "The server is off. Nothing is shared.",
 "Server name:", "Shared folders:", "Remove", "No folders are shared.", "Add Folder…", "Restore Default Folders", "Open Web Interface",
 "Devices, transcoding and everything else are set in the web interface.", "Choose a Folder to Share", "Could not change the media server: %1"]

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "..", "src")
pot = os.path.join(here, "kcm_ums.pot")
subprocess.check_call(["xgettext", "--from-code=UTF-8", "-C", "-kde", "-ki18n:1", "-ki18nc:1c,2", "-ki18np:1,2",
    "--package-name=kcm-ums", "--msgid-bugs-address=Capitain_Jack@yahoo.com", "--add-comments=i18n:", "-o", "po/kcm_ums.pot",
    "src/kcm_ums.cpp", "--language=JavaScript", "src/ui/main.qml"], cwd=os.path.join(here, ".."))
subprocess.check_call(["msgcat", "--no-wrap", "-o", "po/kcm_ums.pot", pot])
text = open(pot, encoding="utf-8").read()
found = re.findall(r'^msgid "(.*)"$', text, re.M)[1:]
assert sorted(found) == sorted(ORDER), (set(found) ^ set(ORDER))
for lang, tr in T.items():
    assert len(tr) == len(ORDER)
    d = dict(zip(ORDER, tr))
    out = []
    for block in text.split("\n\n"):
        m = re.search(r'^msgid "(.*)"$', block, re.M)
        if m and m.group(1) in d:
            block = re.sub(r'^msgstr ".*"$', 'msgstr "%s"' % d[m.group(1)], block, flags=re.M)
        elif not m or m.group(1) == "":
            block = block.replace("Language: \\n", "Language: %s\\n" % lang).replace("charset=CHARSET", "charset=UTF-8")
            block = block.replace("#, fuzzy\n", "").replace("SOME DESCRIPTIVE TITLE.", "Translation of kcm_ums to %s." % lang)
            block = block.replace("YEAR THE PACKAGE'S COPYRIGHT HOLDER", "2026 Daniel Ramos (Capitain Jack)").replace("FIRST AUTHOR <EMAIL@ADDRESS>, YEAR.", "Machine-assisted draft, not yet reviewed by a native speaker.")
            block = block.replace("YEAR-MO-DA HO:MI+ZONE", "2026-10-12 00:00+0000").replace("FULL NAME <EMAIL@ADDRESS>", "Claude (AI-assisted draft) <noreply@anthropic.com>").replace("LANGUAGE <LL@li.org>", "Sparky Stereo OS")
        out.append(block)
    os.makedirs(os.path.join(here, lang), exist_ok=True)
    open(os.path.join(here, lang, "kcm_ums.po"), "w", encoding="utf-8").write("\n\n".join(out))
print("ok", len(ORDER), "strings,", len(T), "languages")
