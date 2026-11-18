#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes po/<lang>/stereo-model-viewer.po and the template from the table below and from F3D's table of the edition's sentences
(application/F3DSparkyStrings.h of the F3D fork): the words for 3D are one set across the programs (Enable 3D, Display Settings,
the sentences about the depth limits), so they are read from that table and never translated twice.
Usage: make-po.py F3DSparkyStrings.h"""
import re, sys
from pathlib import Path

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW']
HERE = Path(__file__).resolve().parents[1]

# F3D's rows, in the order of the header's enum
rows = []
text = Path(sys.argv[1]).read_text(encoding='utf-8')
table = text[text.index('table[][Count] = {'):]
for block in re.findall(r'\{\s*((?:"(?:[^"\\]|\\.)*"\s*,?\s*)+)\}', table):
    strings = re.findall(r'"((?:[^"\\]|\\.)*)"', block)
    if len(strings) == 7:
        rows.append(strings)
assert len(rows) == 10, len(rows)
F3D = {lang: rows[i] for i, lang in enumerate(LANGS)}
SHARED = ['Enable 3D', 'Display Settings', 'Display Settings could not be opened: kcmshell6 was not found',
          '3D could not be enabled: this display offers no stereo window']
DEPTH = [4, 5, 6]

# context, English, then pl, pt_BR, fr, de, es, ja, ko, zh_CN, zh_TW
OWN = [
 ('@title:window', 'Stereo Model Viewer', ['Przeglądarka modeli stereo', 'Visualizador de modelos estéreo', 'Visionneuse de modèles stéréo', 'Stereo-Modellbetrachter', 'Visor de modelos estéreo', 'ステレオモデルビューア', '스테레오 모델 뷰어', '立体模型查看器', '立體模型檢視器']),
 ('@title', 'Open a 3D model, look at it and turn it', ['Otwórz model 3D, obejrzyj go i obracaj', 'Abra um modelo 3D, olhe e gire', 'Ouvrir un modèle 3D, le regarder et le tourner', 'Ein 3D-Modell öffnen, ansehen und drehen', 'Abrir un modelo 3D, mirarlo y girarlo', '3Dモデルを開いて、見て、回す', '3D 모델을 열고 보고 돌려 보세요', '打开 3D 模型，查看并旋转它', '開啟 3D 模型，檢視並旋轉它']),
 ('@title:window', 'Open a 3D model', ['Otwórz model 3D', 'Abrir um modelo 3D', 'Ouvrir un modèle 3D', '3D-Modell öffnen', 'Abrir un modelo 3D', '3Dモデルを開く', '3D 모델 열기', '打开 3D 模型', '開啟 3D 模型']),
 ('@action:button', 'Open…', ['Otwórz…', 'Abrir…', 'Ouvrir…', 'Öffnen…', 'Abrir…', '開く…', '열기…', '打开…', '開啟…']),
 ('@action:button', 'Recent files', ['Ostatnie pliki', 'Arquivos recentes', 'Fichiers récents', 'Zuletzt geöffnet', 'Archivos recientes', '最近使ったファイル', '최근 파일', '最近的文件', '最近的檔案']),
 ('@action:inmenu', 'Clear the list', ['Wyczyść listę', 'Limpar a lista', 'Vider la liste', 'Liste leeren', 'Vaciar la lista', 'リストを消去', '목록 지우기', '清除列表', '清除清單']),
 ('@action:button', 'Reset view', ['Przywróć widok', 'Restaurar a vista', 'Réinitialiser la vue', 'Ansicht zurücksetzen', 'Restablecer la vista', 'ビューをリセット', '보기 초기화', '重置视图', '重設檢視']),
 ('@action:button', 'Play the animation', ['Odtwórz animację', 'Reproduzir a animação', 'Lire l’animation', 'Animation abspielen', 'Reproducir la animación', 'アニメーションを再生', '애니메이션 재생', '播放动画', '播放動畫']),
 ('@action:button', 'Stop the animation', ['Zatrzymaj animację', 'Parar a animação', 'Arrêter l’animation', 'Animation anhalten', 'Detener la animación', 'アニメーションを停止', '애니메이션 정지', '停止动画', '停止動畫']),
 ('@action:button', 'Render resolution per eye', ['Rozdzielczość renderowania na oko', 'Resolução de renderização por olho', 'Résolution de rendu par œil', 'Renderauflösung pro Auge', 'Resolución de renderizado por ojo', '片目あたりのレンダリング解像度', '눈당 렌더링 해상도', '每只眼睛的渲染分辨率', '每隻眼睛的繪製解析度']),
 ('@item:inmenu', 'Half of the area', ['Połowa obszaru', 'Metade da área', 'La moitié de la zone', 'Halb so groß wie der Bereich', 'La mitad del área', 'エリアの半分', '영역의 절반', '区域的一半', '區域的一半']),
 ('@item:inmenu', 'The size of the area', ['Rozmiar obszaru', 'O tamanho da área', 'La taille de la zone', 'So groß wie der Bereich', 'El tamaño del área', 'エリアと同じ大きさ', '영역과 같은 크기', '与区域相同', '與區域相同']),
 ('@item:inmenu', 'One and a half times the area', ['Półtora raza obszaru', 'Uma vez e meia a área', 'Une fois et demie la zone', 'Eineinhalbfach der Bereich', 'Una vez y media el área', 'エリアの1.5倍', '영역의 1.5배', '区域的 1.5 倍', '區域的 1.5 倍']),
 ('@item:inmenu', 'Twice the area', ['Dwa razy obszar', 'Duas vezes a área', 'Deux fois la zone', 'Doppelt so groß wie der Bereich', 'El doble del área', 'エリアの2倍', '영역의 2배', '区域的 2 倍', '區域的 2 倍']),
 ('@info placeholder', 'Open a 3D model or drop a file here', ['Otwórz model 3D lub upuść tu plik', 'Abra um modelo 3D ou solte um arquivo aqui', 'Ouvrez un modèle 3D ou déposez un fichier ici', 'Öffnen Sie ein 3D-Modell oder legen Sie hier eine Datei ab', 'Abra un modelo 3D o suelte un archivo aquí', '3Dモデルを開くか、ここにファイルをドロップしてください', '3D 모델을 열거나 여기에 파일을 끌어다 놓으세요', '打开 3D 模型，或将文件拖放到此处', '開啟 3D 模型，或將檔案拖放到此處']),
 ('@info the file is not a model the viewer knows', '“%1” is not a 3D model format the viewer can read.', ['„%1” nie jest formatem modelu 3D, który przeglądarka potrafi odczytać.', '“%1” não é um formato de modelo 3D que o visualizador consiga ler.', '« %1 » n’est pas un format de modèle 3D que la visionneuse sait lire.', '„%1“ ist kein 3D-Modellformat, das der Betrachter lesen kann.', '«%1» no es un formato de modelo 3D que el visor pueda leer.', '「%1」は、このビューアで読める3Dモデル形式ではありません。', '“%1”은(는) 뷰어가 읽을 수 있는 3D 모델 형식이 아닙니다.', '“%1”不是查看器可以读取的 3D 模型格式。', '「%1」不是檢視器可以讀取的 3D 模型格式。']),
 ('@info a model file that cannot be read', '“%1” cannot be read: it is damaged or not a valid model file.', ['Nie można odczytać „%1”: plik jest uszkodzony lub nie jest poprawnym plikiem modelu.', '“%1” não pode ser lido: o arquivo está danificado ou não é um modelo válido.', '« %1 » ne peut pas être lu : le fichier est endommagé ou n’est pas un modèle valide.', '„%1“ kann nicht gelesen werden: Die Datei ist beschädigt oder keine gültige Modelldatei.', '«%1» no se puede leer: el archivo está dañado o no es un modelo válido.', '「%1」を読み込めません: ファイルが破損しているか、有効なモデルファイルではありません。', '“%1”을(를) 읽을 수 없습니다: 파일이 손상되었거나 올바른 모델 파일이 아닙니다.', '无法读取“%1”：文件已损坏，或不是有效的模型文件。', '無法讀取「%1」：檔案已損毀，或不是有效的模型檔案。']),
 ('@info:shell', 'A model to open', ['Model do otwarcia', 'Um modelo para abrir', 'Un modèle à ouvrir', 'Ein zu öffnendes Modell', 'Un modelo para abrir', '開くモデル', '열 모델', '要打开的模型', '要開啟的模型']),
 ('@item:inlistbox file dialog filter', '3D models (*.glb *.gltf *.obj *.stl *.ply *.3mf *.fbx *.dae *.off *.step *.stp *.brep *.iges *.igs *.drc *.splat *.spz *.pts *.vtk *.vtp *.vtu *.3ds *.wrl *.xyz *.dxf)', None),
 ('@item:inlistbox file dialog filter', 'All files (*)', ['Wszystkie pliki (*)', 'Todos os arquivos (*)', 'Tous les fichiers (*)', 'Alle Dateien (*)', 'Todos los archivos (*)', 'すべてのファイル (*)', '모든 파일 (*)', '所有文件 (*)', '所有檔案 (*)']),
]
MODELS = {'pl': 'Modele 3D', 'pt_BR': 'Modelos 3D', 'fr': 'Modèles 3D', 'de': '3D-Modelle', 'es': 'Modelos 3D', 'ja': '3Dモデル', 'ko': '3D 모델', 'zh_CN': '3D 模型', 'zh_TW': '3D 模型'}
SHARED_CTX = ['@action:button', '@action:button', '@info', '@info']
DEPTH_CTX = '@info'

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def entries(lang):
    out = []
    i = LANGS.index(lang)
    for ctx, en, tr in OWN:
        if tr is None:
            msg = en if lang == 'en' else en.replace('3D models', MODELS[lang])
        else:
            msg = en if lang == 'en' else tr[i - 1]
        out.append((ctx, en, msg))
    shared_ids = [0, 1, 2, 3]
    for n, idx in enumerate(shared_ids):
        out.append((SHARED_CTX[n], F3D['en'][idx], F3D[lang][idx]))
    for idx in DEPTH:
        out.append((DEPTH_CTX, F3D['en'][idx], F3D[lang][idx]))
    return out

def write(path, lang, template=False):
    lines = ['# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)', '# SPDX-License-Identifier: GPL-3.0-or-later',
             'msgid ""', 'msgstr ""', '"Project-Id-Version: stereo-model-viewer 0.1.0\\n"', '"Report-Msgid-Bugs-To: https://github.com/Sparky-OS/sparky-stereo-os/issues\\n"',
             '"MIME-Version: 1.0\\n"', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Content-Transfer-Encoding: 8bit\\n"']
    if not template:
        lines.insert(4, '"Language: %s\\n"' % lang)
    lines.append('')
    for ctx, en, msg in entries('en' if template else lang):
        lines += ['msgctxt ' + q(ctx), 'msgid ' + q(en), 'msgstr ' + q('' if template else msg), '']
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text('\n'.join(lines), encoding='utf-8')

for lang in LANGS:
    write(HERE / 'po' / lang / 'stereo-model-viewer.po' if False else HERE / lang / 'stereo-model-viewer.po', lang)
write(HERE / 'stereo-model-viewer.pot', 'en', template=True)
print('written', len(LANGS), 'catalogues of', len(entries('en')), 'sentences')
