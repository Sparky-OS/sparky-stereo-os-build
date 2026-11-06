#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
# Writes pack.json (for ../sparky-stereo-integration/make-pack.py) and lang/<code> (for the worker) from the one
# table below, so the menu and the worker say the same words. Usage: gen.py OUT-DIR
import json, os, sys

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']
NAME = {
 'en': 'Run with Wine', 'pl': 'Uruchom w Wine', 'pt_BR': 'Executar com o Wine', 'fr': 'Exécuter avec Wine',
 'de': 'Mit Wine ausführen', 'ja': 'Wine で実行', 'ko': 'Wine으로 실행', 'zh_CN': '用 Wine 运行', 'zh_TW': '用 Wine 執行',
}
# worker messages LOCAL2 to LOCAL4, printf order: 2 file; 3 none; 4 file, status
# (LOCAL4 is a first draft with AI assistance, pending review by native speakers)
M = {
 'en': ['Cannot run %s: the file is missing or is not a regular file.', 'Select the Windows program to run.', "Wine could not start %s (it ended with status %s). Run it from a terminal with: wine start /unix FILE, to see why."],
 'pl': ['Nie można uruchomić %s: plik nie istnieje lub nie jest zwykłym plikiem.', 'Wybierz program dla Windows do uruchomienia.', "Wine nie mógł uruchomić %s (zakończył działanie ze statusem %s). Uruchom plik w terminalu poleceniem: wine start /unix PLIK, aby zobaczyć przyczynę."],
 'pt_BR': ['Não é possível executar %s: o arquivo não existe ou não é um arquivo comum.', 'Selecione o programa do Windows a executar.', "O Wine não conseguiu iniciar %s (terminou com o status %s). Execute-o em um terminal com: wine start /unix ARQUIVO, para ver o motivo."],
 'fr': ["Impossible d'exécuter %s : le fichier est manquant ou n'est pas un fichier ordinaire.", 'Sélectionnez le programme Windows à exécuter.', "Wine n'a pas pu démarrer %s (il s'est terminé avec le statut %s). Lancez-le dans un terminal avec : wine start /unix FICHIER, pour voir pourquoi."],
 'de': ['%s kann nicht ausgeführt werden: Die Datei fehlt oder ist keine reguläre Datei.', 'Wählen Sie das Windows-Programm aus, das ausgeführt werden soll.', "Wine konnte %s nicht starten (Beendigungsstatus %s). Starten Sie die Datei in einem Terminal mit: wine start /unix DATEI, um den Grund zu sehen."],
 'ja': ['%s を実行できません。ファイルが存在しないか、通常のファイルではありません。', '実行する Windows プログラムを選択してください。', "Wine が %s を起動できませんでした（終了ステータス %s）。原因を確認するには、端末で wine start /unix ファイル を実行してください。"],
 'ko': ['%s을(를) 실행할 수 없습니다. 파일이 없거나 일반 파일이 아닙니다.', '실행할 Windows 프로그램을 선택하세요.', "Wine이 %s을(를) 시작하지 못했습니다(종료 상태 %s). 이유를 보려면 터미널에서 wine start /unix 파일 을(를) 실행하세요."],
 'zh_CN': ['无法运行 %s：文件缺失或不是普通文件。', '请选择要运行的 Windows 程序。', "Wine 无法启动 %s（退出状态 %s）。请在终端中运行 wine start /unix 文件 以查看原因。"],
 'zh_TW': ['無法執行 %s：檔案遺失或不是一般檔案。', '請選取要執行的 Windows 程式。', "Wine 無法啟動 %s（結束狀態 %s）。請在終端機中執行 wine start /unix 檔案 以查看原因。"],
}
# Windows programs and installers. application/x-ms-dos-executable is the alias of application/x-msdownload in
# shared-mime-info, which also holds .dll, so the executable types are named one by one and the .dll-only type is not
MIME = ['application/x-ms-dos-executable', 'application/x-dosexec', 'application/vnd.microsoft.portable-executable',
        'application/x-ms-ne-executable', 'application/x-msi']

def main():
    out = sys.argv[1]
    os.makedirs(os.path.join(out, 'lang'), exist_ok=True)
    hdr = '#!/bin/bash\n# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06\n# Copyright 2026 under the GNU GPL3 License\n'
    for lang in LANGS:
        body = f'LOCAL1="{NAME[lang]}"\n' + ''.join(f'LOCAL{i + 2}="{s}"\n' for i, s in enumerate(M[lang]))
        open(os.path.join(out, 'lang', lang), 'w').write(hdr + body)
    spec = {'id': 'wine', 'program': 'wine', 'worker': '/usr/lib/sparky-stereo/wine/run',
            'menus': [{'file': 'sparky-stereo-wine', 'icon': 'wine', 'mime': MIME, 'urls': {'min': 1},
                       'actions': [{'id': 'Run', 'args': [], 'name': dict(NAME)}]}]}
    json.dump(spec, open(os.path.join(out, 'pack.json'), 'w'), ensure_ascii=False, indent=1)

main()
