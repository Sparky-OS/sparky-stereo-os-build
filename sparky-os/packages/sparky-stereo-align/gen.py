#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Writes pack.json (for ../sparky-stereo-integration/make-pack.py) and lang/<code> (for the worker) from the one
# table below. Usage: gen.py OUT-DIR
import json, os, sys

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']
# submenu for two pictures, submenu for one stereo file, Save as JPS, MPO, PNS (one word is the format), first picture is the left eye, first picture is the right eye
W = {
 'en': ['Align stereo pair', 'Align the two views', 'Save as %s', ', first picture is the left eye', ', first picture is the right eye'],
 'pl': ['Wyrównaj parę stereo', 'Wyrównaj oba widoki', 'Zapisz jako %s', ', pierwszy obraz to lewe oko', ', pierwszy obraz to prawe oko'],
 'pt_BR': ['Alinhar par estéreo', 'Alinhar as duas vistas', 'Salvar como %s', ', a primeira imagem é o olho esquerdo', ', a primeira imagem é o olho direito'],
 'fr': ['Aligner la paire stéréo', 'Aligner les deux vues', 'Enregistrer en %s', ", la première image est l'œil gauche", ", la première image est l'œil droit"],
 'de': ['Stereopaar ausrichten', 'Beide Ansichten ausrichten', 'Als %s speichern', ', das erste Bild ist das linke Auge', ', das erste Bild ist das rechte Auge'],
 'ja': ['ステレオペアを位置合わせ', '2つのビューを位置合わせ', '%sとして保存', '（最初の画像が左目）', '（最初の画像が右目）'],
 'ko': ['스테레오 쌍 정렬', '두 시점 정렬', '%s(으)로 저장', ' (첫 번째 사진이 왼쪽 눈)', ' (첫 번째 사진이 오른쪽 눈)'],
 'zh_CN': ['对齐立体图像对', '对齐两个视图', '保存为 %s', '（第一张图片为左眼）', '（第一张图片为右眼）'],
 'zh_TW': ['對齊立體影像對', '對齊兩個視圖', '儲存為 %s', '（第一張影像為左眼）', '（第一張影像為右眼）'],
}
# worker messages LOCAL2 to LOCAL8, printf order: 2 file; 3 none; 4 file; 5 sizes; 6 file; 7 none; 8 left, right
M = {
 'en': ['Saved as %s.', 'The pictures could not be aligned: they share too few points.', '%s is not a stereo picture (JPS, MPO or PNS with a mark).', 'The two pictures differ in size: %s and %s.', 'Could not read %s.', 'Select two pictures, or one stereo picture.', 'Left eye: %s. Right eye: %s.'],
 'pl': ['Zapisano jako %s.', 'Nie udało się wyrównać obrazów: mają zbyt mało wspólnych punktów.', '%s nie jest obrazem stereo (JPS, MPO lub PNS ze znacznikiem).', 'Oba obrazy mają różne rozmiary: %s i %s.', 'Nie udało się odczytać %s.', 'Wybierz dwa obrazy albo jeden obraz stereo.', 'Lewe oko: %s. Prawe oko: %s.'],
 'pt_BR': ['Salvo como %s.', 'Não foi possível alinhar as imagens: elas têm pontos em comum de menos.', '%s não é uma imagem estéreo (JPS, MPO ou PNS com marca).', 'As duas imagens têm tamanhos diferentes: %s e %s.', 'Não foi possível ler %s.', 'Selecione duas imagens ou uma imagem estéreo.', 'Olho esquerdo: %s. Olho direito: %s.'],
 'fr': ['Enregistré sous %s.', "Les images n'ont pas pu être alignées : elles ont trop peu de points communs.", "%s n'est pas une image stéréo (JPS, MPO ou PNS avec marque).", 'Les deux images ont des tailles différentes : %s et %s.', 'Impossible de lire %s.', 'Sélectionnez deux images ou une image stéréo.', 'Œil gauche : %s. Œil droit : %s.'],
 'de': ['Gespeichert als %s.', 'Die Bilder konnten nicht ausgerichtet werden: Sie haben zu wenige gemeinsame Punkte.', '%s ist kein Stereobild (JPS, MPO oder PNS mit Markierung).', 'Die beiden Bilder haben unterschiedliche Größen: %s und %s.', '%s konnte nicht gelesen werden.', 'Wählen Sie zwei Bilder oder ein Stereobild aus.', 'Linkes Auge: %s. Rechtes Auge: %s.'],
 'ja': ['%s として保存しました。', '画像を位置合わせできませんでした。共通する点が少なすぎます。', '%s はステレオ画像（マーク付きの JPS、MPO、PNS）ではありません。', '2つの画像のサイズが異なります: %s と %s。', '%s を読み込めませんでした。', '画像を2つ、またはステレオ画像を1つ選択してください。', '左目: %s。右目: %s。'],
 'ko': ['%s(으)로 저장했습니다.', '사진을 정렬하지 못했습니다. 공통된 점이 너무 적습니다.', '%s은(는) 스테레오 사진(표시가 있는 JPS, MPO, PNS)이 아닙니다.', '두 사진의 크기가 다릅니다: %s 및 %s.', '%s을(를) 읽을 수 없습니다.', '사진 두 장 또는 스테레오 사진 한 장을 선택하세요.', '왼쪽 눈: %s. 오른쪽 눈: %s.'],
 'zh_CN': ['已保存为 %s。', '无法对齐这些图片：它们的共同点太少。', '%s 不是立体图片（带标记的 JPS、MPO 或 PNS）。', '两张图片大小不同：%s 与 %s。', '无法读取 %s。', '请选择两张图片或一张立体图片。', '左眼：%s。右眼：%s。'],
 'zh_TW': ['已儲存為 %s。', '無法對齊這些影像：它們的共同點太少。', '%s 不是立體影像（帶標記的 JPS、MPO 或 PNS）。', '兩張影像大小不同：%s 與 %s。', '無法讀取 %s。', '請選取兩張影像或一張立體影像。', '左眼：%s。右眼：%s。'],
}
FORMATS = [('Jps', 'jps', 'JPS'), ('Mpo', 'mpo', 'MPO'), ('Pns', 'pns', 'PNS')]
PAIR_MIME = ['image/jpeg', 'image/png', 'image/tiff', 'image/x-mpo', 'image/x-jps', 'image/x-pns']
FILE_MIME = ['image/x-jps', 'image/x-mpo', 'image/x-pns']

def main():
    out = sys.argv[1]
    os.makedirs(os.path.join(out, 'lang'), exist_ok=True)
    hdr = '#!/bin/bash\n# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24\n# Copyright 2026 under the GNU GPL3 License\n# Last update 2026/10/24\n'
    for l in LANGS:
        open(os.path.join(out, 'lang', l), 'w').write(hdr + f'LOCAL1="{W[l][0]}"\n' + ''.join(f'LOCAL{i + 2}="{s}"\n' for i, s in enumerate(M[l])))
    pair, single = [], []
    for ident, ext, label in FORMATS:
        for suffix, tail, swap in (('Left', 3, []), ('Right', 4, ['swap'])):
            pair.append({'id': f'Pair{ident}{suffix}', 'args': [ext] + swap,
                         'name': {l: (W[l][2] % label) + W[l][tail] for l in LANGS}})
        single.append({'id': f'File{ident}', 'args': [ext], 'name': {l: W[l][2] % label for l in LANGS}})
    spec = {'id': 'align', 'program': 'align_image_stack', 'worker': '/usr/lib/sparky-stereo/align/align',
            'menus': [{'file': 'sparky-stereo-align-pair', 'icon': 'image-x-generic', 'mime': PAIR_MIME, 'urls': {'required': [2]},
                       'submenu': {l: W[l][0] for l in LANGS}, 'actions': pair},
                      {'file': 'sparky-stereo-align-file', 'icon': 'image-x-generic', 'mime': FILE_MIME, 'urls': {'required': [1]},
                       'submenu': {l: W[l][1] for l in LANGS}, 'actions': single}]}
    json.dump(spec, open(os.path.join(out, 'pack.json'), 'w'), ensure_ascii=False, indent=1)

main()
