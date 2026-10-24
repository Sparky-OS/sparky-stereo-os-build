#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Writes pack.json (for ../sparky-stereo-integration/make-pack.py) and lang/<code> (for the worker) from the one
# table below, so the menu and the worker's messages say the same words. Usage: gen.py OUT-DIR
# StereoMode values: RFC 9559 section 5.1.4.1.28.3 (Matroska element StereoMode, ID 0x53B8).
import json, os, sys

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']
SEP = {'ja': '、', 'zh_CN': '，', 'zh_TW': '，'}
# word: mono sbs tb checker rows cols anacr anagm laced left right remove submenu
W = {
 'en': ['Not 3D (mono)', 'Side by side', 'Top and bottom', 'Checkerboard', 'Row interleaved', 'Column interleaved', 'Anaglyph, cyan and red', 'Anaglyph, green and magenta', 'Both eyes laced in one block', 'left eye first', 'right eye first', 'Remove the 3D mark', 'Mark as 3D'],
 'pl': ['Nie 3D (mono)', 'Obok siebie', 'Góra i dół', 'Szachownica', 'Przeplot wierszy', 'Przeplot kolumn', 'Anaglif, cyjan i czerwień', 'Anaglif, zieleń i magenta', 'Oba oczy w jednym bloku', 'najpierw lewe oko', 'najpierw prawe oko', 'Usuń znacznik 3D', 'Oznacz jako 3D'],
 'pt_BR': ['Não 3D (mono)', 'Lado a lado', 'Superior e inferior', 'Xadrez', 'Linhas intercaladas', 'Colunas intercaladas', 'Anaglifo, ciano e vermelho', 'Anaglifo, verde e magenta', 'Os dois olhos em um só bloco', 'olho esquerdo primeiro', 'olho direito primeiro', 'Remover a marca 3D', 'Marcar como 3D'],
 'fr': ['Pas en 3D (mono)', 'Côte à côte', 'Haut et bas', 'Damier', 'Lignes entrelacées', 'Colonnes entrelacées', 'Anaglyphe, cyan et rouge', 'Anaglyphe, vert et magenta', 'Les deux yeux dans un seul bloc', 'œil gauche en premier', 'œil droit en premier', 'Retirer la marque 3D', 'Marquer comme 3D'],
 'de': ['Nicht 3D (Mono)', 'Nebeneinander', 'Übereinander', 'Schachbrett', 'Zeilenweise verschachtelt', 'Spaltenweise verschachtelt', 'Anaglyphe, Cyan und Rot', 'Anaglyphe, Grün und Magenta', 'Beide Augen in einem Block', 'linkes Auge zuerst', 'rechtes Auge zuerst', '3D-Markierung entfernen', 'Als 3D markieren'],
 'ja': ['3Dではない（モノ）', 'サイド・バイ・サイド', 'トップ・アンド・ボトム', '市松模様', '行インターリーブ', '列インターリーブ', 'アナグリフ（シアンと赤）', 'アナグリフ（緑とマゼンタ）', '両目を1ブロックに格納', '左目が先', '右目が先', '3Dマークを削除', '3Dとしてマーク'],
 'ko': ['3D 아님(모노)', '나란히', '위아래', '체커보드', '행 인터리브', '열 인터리브', '애너글리프, 청록과 빨강', '애너글리프, 초록과 자홍', '두 눈을 한 블록에 묶음', '왼쪽 눈 먼저', '오른쪽 눈 먼저', '3D 표시 제거', '3D로 표시'],
 'zh_CN': ['非 3D（单视图）', '左右并排', '上下排列', '棋盘格', '逐行交错', '逐列交错', '红蓝立体（青色与红色）', '绿品立体（绿色与品红）', '双眼合在一个块中', '左眼在先', '右眼在先', '移除 3D 标记', '标记为 3D'],
 'zh_TW': ['非 3D（單視圖）', '左右並排', '上下排列', '棋盤格', '逐行交錯', '逐列交錯', '紅藍立體（青色與紅色）', '綠洋紅立體（綠色與洋紅）', '雙眼合在一個區塊中', '左眼在先', '右眼在先', '移除 3D 標記', '標記為 3D'],
}
# worker messages (LOCAL2 to LOCAL9), printf order: M2 name; M3 count, label; M4 count; M5 name; M6 name, old, new; M7 name; M8 changed, failed; M9 name
M = {
 'en': ['Could not change %s', 'Marked %s file(s) as: %s', 'Removed the 3D mark from %s file(s)', '%s already has this mark.', '%s already has a different mark: %s. Replace it with: %s?', '%s has no video track.', 'Changed %s file(s), %s failed', "%s has no 3D mark."],
 'pl': ['Nie udało się zmienić %s', 'Oznaczono %s plik(ów) jako: %s', 'Usunięto znacznik 3D z %s plik(ów)', '%s ma już ten znacznik.', '%s ma już inny znacznik: %s. Zastąpić go znacznikiem: %s?', '%s nie ma ścieżki wideo.', 'Zmieniono %s plik(ów), niepowodzeń: %s', "%s nie ma znacznika 3D."],
 'pt_BR': ['Não foi possível alterar %s', '%s arquivo(s) marcado(s) como: %s', 'Marca 3D removida de %s arquivo(s)', '%s já tem esta marca.', '%s já tem outra marca: %s. Substituir por: %s?', '%s não tem faixa de vídeo.', '%s arquivo(s) alterado(s), %s com falha', "%s não tem marca 3D."],
 'fr': ['Impossible de modifier %s', '%s fichier(s) marqué(s) comme : %s', 'Marque 3D retirée de %s fichier(s)', '%s porte déjà cette marque.', '%s porte déjà une autre marque : %s. La remplacer par : %s ?', "%s n'a pas de piste vidéo.", '%s fichier(s) modifié(s), %s en échec', "%s n'a pas de marque 3D."],
 'de': ['%s konnte nicht geändert werden', '%s Datei(en) markiert als: %s', '3D-Markierung aus %s Datei(en) entfernt', '%s hat diese Markierung bereits.', '%s hat bereits eine andere Markierung: %s. Durch diese ersetzen: %s?', '%s hat keine Videospur.', '%s Datei(en) geändert, %s fehlgeschlagen', "%s hat keine 3D-Markierung."],
 'ja': ['%s を変更できませんでした', '%s 個のファイルを次としてマークしました: %s', '%s 個のファイルから3Dマークを削除しました', '%s には既にこのマークがあります。', '%s には既に別のマークがあります: %s。次に置き換えますか: %s？', '%s にはビデオトラックがありません。', '%s 個のファイルを変更し、%s 個が失敗しました', "%s には3Dマークがありません。"],
 'ko': ['%s을(를) 변경할 수 없습니다', '%s개 파일을 다음으로 표시했습니다: %s', '%s개 파일에서 3D 표시를 제거했습니다', '%s에는 이미 이 표시가 있습니다.', '%s에는 이미 다른 표시가 있습니다: %s. 다음으로 바꿀까요: %s?', '%s에는 비디오 트랙이 없습니다.', '%s개 파일을 변경했고 %s개가 실패했습니다', "%s에는 3D 표시가 없습니다."],
 'zh_CN': ['无法更改 %s', '已将 %s 个文件标记为：%s', '已从 %s 个文件中移除 3D 标记', '%s 已有此标记。', '%s 已有另一个标记：%s。要替换为：%s 吗？', '%s 没有视频轨道。', '已更改 %s 个文件，%s 个失败', "%s 没有 3D 标记。"],
 'zh_TW': ['無法變更 %s', '已將 %s 個檔案標記為：%s', '已從 %s 個檔案移除 3D 標記', '%s 已有此標記。', '%s 已有另一個標記：%s。要取代為：%s 嗎？', '%s 沒有視訊軌。', '已變更 %s 個檔案，%s 個失敗', "%s 沒有 3D 標記。"],
}
# value: (layout index in W, order) ; order None = none, 'l' left first, 'r' right first. RFC 9559 5.1.4.1.28.3
MODES = {0: (0, None), 1: (1, 'l'), 2: (2, 'r'), 3: (2, 'l'), 4: (3, 'r'), 5: (3, 'l'), 6: (4, 'r'), 7: (4, 'l'),
         8: (5, 'r'), 9: (5, 'l'), 10: (6, None), 11: (1, 'r'), 12: (7, None), 13: (8, 'l'), 14: (8, 'r')}

def label(lang, n):
    layout, order = MODES[n]
    w = W[lang]
    if order is None:
        return w[layout]
    return w[layout] + SEP.get(lang, ', ') + w[9 if order == 'l' else 10]

def main():
    out = sys.argv[1]
    os.makedirs(os.path.join(out, 'lang'), exist_ok=True)
    hdr = '#!/bin/bash\n# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24\n# Copyright 2026 under the GNU GPL3 License\n# Last update 2026/10/24\n'
    for lang in LANGS:
        body = f'LOCAL1="{W[lang][12]}"\n'
        body += ''.join(f'LOCAL{i + 2}="{s}"\n' for i, s in enumerate(M[lang]))
        body += f'LOCALREMOVE="{W[lang][11]}"\n'
        body += ''.join(f'MODE{n}="{label(lang, n)}"\n' for n in MODES)
        open(os.path.join(out, 'lang', lang), 'w').write(hdr + body)
    actions = [{'id': f'Mark{n}', 'args': [str(n)], 'name': {l: label(l, n) for l in LANGS}} for n in MODES]
    actions.append({'id': 'Remove', 'args': ['remove'], 'name': {l: W[l][11] for l in LANGS}})
    spec = {'id': 'mkv-mark', 'program': 'mkvpropedit', 'worker': '/usr/lib/sparky-stereo/mkv-mark/mark',
            'menus': [{'file': 'sparky-stereo-mkv-mark', 'icon': 'video-x-generic',
                       'mime': ['video/x-matroska', 'video/webm', 'video/x-matroska-3d'],
                       'submenu': {l: W[l][12] for l in LANGS}, 'actions': actions}]}
    json.dump(spec, open(os.path.join(out, 'pack.json'), 'w'), ensure_ascii=False, indent=1)

main()
