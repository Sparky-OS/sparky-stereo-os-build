#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
# Writes pack.json (for ../sparky-stereo-integration/make-pack.py) and lang/<code> (for the worker) from the one
# table below, so the menu and the worker say the same words. Usage: gen.py OUT-DIR
import json, os, sys

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW']
# the menu entry
NAME = {
 'en': 'Scan for viruses', 'pl': 'Skanuj w poszukiwaniu wirusów', 'pt_BR': 'Verificar vírus', 'fr': 'Rechercher des virus',
 'de': 'Auf Viren prüfen', 'es': 'Buscar virus', 'ja': 'ウイルスをスキャン', 'ko': '바이러스 검사', 'zh_CN': '扫描病毒', 'zh_TW': '掃描病毒',
}
# worker messages LOCAL2 and LOCAL3, printf order: 2 path; 3 none
M = {
 'en': ['Cannot scan %s: it is missing or is not a file or a folder.', 'Select one file or one folder to scan.'],
 'pl': ['Nie można przeskanować %s: nie istnieje albo nie jest plikiem ani folderem.', 'Wybierz jeden plik albo jeden folder do skanowania.'],
 'pt_BR': ['Não é possível verificar %s: não existe ou não é um arquivo nem uma pasta.', 'Selecione um arquivo ou uma pasta para verificar.'],
 'fr': ["Impossible d'analyser %s : l'élément est manquant ou n'est ni un fichier ni un dossier.", 'Sélectionnez un fichier ou un dossier à analyser.'],
 'de': ['%s kann nicht geprüft werden: Es fehlt oder ist weder eine Datei noch ein Ordner.', 'Wählen Sie eine Datei oder einen Ordner zum Prüfen aus.'],
 'es': ['No se puede analizar %s: no existe o no es un archivo ni una carpeta.', 'Seleccione un archivo o una carpeta para analizar.'],
 'ja': ['%s をスキャンできません。存在しないか、ファイルでもフォルダーでもありません。', 'スキャンするファイルまたはフォルダーを1つ選択してください。'],
 'ko': ['%s을(를) 검사할 수 없습니다. 없거나 파일 또는 폴더가 아닙니다.', '검사할 파일 또는 폴더를 하나 선택하세요.'],
 'zh_CN': ['无法扫描 %s：它不存在，或不是文件或文件夹。', '请选择一个要扫描的文件或文件夹。'],
 'zh_TW': ['無法掃描 %s：它不存在，或不是檔案或資料夾。', '請選取一個要掃描的檔案或資料夾。'],
}

def main():
    out = sys.argv[1]
    os.makedirs(os.path.join(out, 'lang'), exist_ok=True)
    hdr = '#!/bin/bash\n# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06\n# Copyright 2026 under the GNU GPL3 License\n'
    for lang in LANGS:
        body = f'LOCAL1="{NAME[lang]}"\n' + ''.join(f'LOCAL{i + 2}="{s}"\n' for i, s in enumerate(M[lang]))
        open(os.path.join(out, 'lang', lang), 'w').write(hdr + body)
    # the same types ClamTk's own KDE entry names (clamtk-kde.desktop: MimeType=inode/directory;application/octet-stream;)
    # ClamTk takes one path: its program reads $ARGV[0] only (clamtk 6.07, /usr/bin/clamtk), so the entry is offered
    # for one selected file or folder
    spec = {'id': 'clamav', 'program': 'clamtk', 'worker': '/usr/lib/sparky-stereo/clamav/scan',
            'menus': [{'file': 'sparky-stereo-clamav', 'icon': 'security-medium',
                       'mime': ['inode/directory', 'application/octet-stream'], 'urls': {'required': [1]},
                       'actions': [{'id': 'Scan', 'args': [], 'name': dict(NAME)}]}]}
    json.dump(spec, open(os.path.join(out, 'pack.json'), 'w'), ensure_ascii=False, indent=1)

main()
