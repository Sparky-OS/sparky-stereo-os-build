## Copyright (C) 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with Octave; see the file COPYING.  If not, see
## <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn  {} {@var{str} =} sparky_stereo_text (@var{key})
## @deftypefnx {} {@var{str} =} sparky_stereo_text (@var{key}, @var{lang})
## Sparky Stereo OS: the sentence @var{key} of Octave's 3D figures in the
## person's language.
##
## The language is the first of @env{LANGUAGE}'s list, then @env{LC_ALL},
## @env{LC_MESSAGES} or @env{LANG}, that the table has: the whole name
## (@code{pt_BR}), then the bare language (@code{fr} for @code{fr_CA});
## Chinese keeps its script (@code{zh_TW}, @code{zh_HK} and @code{zh_MO}
## read @code{zh_TW}, other Chinese @code{zh_CN}); English otherwise, and
## in the C locale.  @var{lang} chooses the language instead.
## @end deftypefn

function str = sparky_stereo_text (key, lang = "")

  persistent table = make_table ();

  field = strrep (key, "-", "_");
  if (! isfield (table, field))
    error ("sparky_stereo_text: no sentence '%s'", key);
  endif

  langs = {"en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"};
  if (isempty (lang))
    lang = person_language (langs);
  endif
  idx = find (strcmp (langs, lang), 1);
  if (isempty (idx))
    idx = 1;
  endif
  str = table.(field){idx};

endfunction

function lang = person_language (langs)

  lang = "en";
  locale = "";
  for var = {"LC_ALL", "LC_MESSAGES", "LANG"}
    locale = getenv (var{1});
    if (! isempty (locale))
      break;
    endif
  endfor
  ## gettext reads LANGUAGE only when a locale other than C is set
  if (isempty (locale) || any (strcmp (strtok (locale, ".@"), {"C", "POSIX"})))
    return;
  endif
  candidates = [strsplit(getenv ("LANGUAGE"), ":"), {locale}];
  for c = candidates
    name = strtok (c{1}, ".@");
    if (isempty (name))
      continue;
    endif
    [base, rest] = strtok (name, "_");
    territory = strrep (rest, "_", "");
    if (strcmp (base, "zh"))
      if (any (strcmp (territory, {"TW", "HK", "MO"})))
        lang = "zh_TW";
      else
        lang = "zh_CN";
      endif
      return;
    elseif (any (strcmp (langs, name)))
      lang = name;
      return;
    elseif (any (strcmp (langs, base)))
      lang = base;
      return;
    endif
  endfor

endfunction

function t = make_table ()

  ## The order of every row: en, pl, pt_BR, fr, de, es, ja, ko, zh_CN, zh_TW

  t.menu_enable_3d = {
    "Enable 3D (applies to new figures)",
    "Włącz 3D (działa dla nowych rysunków)",
    "Ativar 3D (vale para novas figuras)",
    "Activer la 3D (effective pour les nouvelles figures)",
    "3D einschalten (gilt für neue Abbildungen)",
    "Activar 3D (se aplica a las figuras nuevas)",
    "3D を有効にする (新しい図に反映)",
    "3D 켜기 (새 그림에 적용)",
    "启用 3D（对新图窗生效）",
    "啟用 3D（對新圖窗生效）"};

  t.menu_display_settings = {
    "3D display settings...",
    "Ustawienia wyświetlacza 3D...",
    "Configurações da tela 3D...",
    "Réglages de l'écran 3D...",
    "3D-Anzeigeeinstellungen ...",
    "Ajustes de la pantalla 3D...",
    "3D ディスプレイの設定...",
    "3D 디스플레이 설정...",
    "3D 显示设置...",
    "3D 顯示設定..."};

  t.display_settings_failed = {
    "Display Settings could not be opened.",
    "Nie udało się otworzyć ustawień wyświetlacza.",
    "Não foi possível abrir as Configurações de tela.",
    "Impossible d'ouvrir les Réglages de l'écran.",
    "Die Anzeigeeinstellungen konnten nicht geöffnet werden.",
    "No se pudieron abrir los Ajustes de pantalla.",
    "ディスプレイ設定を開けませんでした。",
    "디스플레이 설정을 열 수 없습니다.",
    "无法打开显示设置。",
    "無法開啟顯示設定。"};

  t.choice_not_saved = {
    "The 3D choice could not be saved.",
    "Nie udało się zapisać wyboru 3D.",
    "Não foi possível salvar a escolha de 3D.",
    "Le choix de la 3D n’a pas pu être enregistré.",
    "Die 3D-Auswahl konnte nicht gespeichert werden.",
    "No se pudo guardar la elección de 3D.",
    "3D の選択を保存できませんでした。",
    "3D 선택을 저장할 수 없습니다.",
    "无法保存 3D 选择。",
    "無法儲存 3D 選擇。"};

  t.limits_not_offered = {
    "3D depth: this desktop offers no depth limits, so both eyes show the same picture",
    "Głębia 3D: ten pulpit nie podaje limitów głębi, więc oba oczy widzą ten sam obraz",
    "Profundidade 3D: este desktop não oferece limites de profundidade, então os dois olhos veem a mesma imagem",
    "Profondeur 3D : ce bureau n’offre pas de limites de profondeur, les deux yeux voient donc la même image",
    "3D-Tiefe: Dieser Desktop bietet keine Tiefengrenzen, deshalb sehen beide Augen dasselbe Bild",
    "Profundidad 3D: este escritorio no ofrece límites de profundidad, así que los dos ojos ven la misma imagen",
    "3D奥行き: このデスクトップは奥行きの上限を提供しないため、両目に同じ画像を表示します",
    "3D 깊이: 이 데스크톱은 깊이 한계를 제공하지 않아 두 눈에 같은 화면을 보여 줍니다",
    "3D 深度：此桌面未提供深度限制，因此两眼显示相同的画面",
    "3D 深度：此桌面未提供深度限制，因此兩眼顯示相同的畫面"};

  t.limits_not_delivered = {
    "3D depth: the desktop has not delivered the depth limits yet, both eyes show the same picture for now",
    "Głębia 3D: pulpit nie przekazał jeszcze limitów głębi, na razie oba oczy widzą ten sam obraz",
    "Profundidade 3D: o desktop ainda não entregou os limites de profundidade, por enquanto os dois olhos veem a mesma imagem",
    "Profondeur 3D : le bureau n’a pas encore transmis les limites de profondeur, les deux yeux voient la même image pour l’instant",
    "3D-Tiefe: Der Desktop hat die Tiefengrenzen noch nicht geliefert, beide Augen sehen vorerst dasselbe Bild",
    "Profundidad 3D: el escritorio aún no ha entregado los límites de profundidad, por ahora los dos ojos ven la misma imagen",
    "3D奥行き: デスクトップがまだ奥行きの上限を渡していないため、今は両目に同じ画像を表示します",
    "3D 깊이: 데스크톱이 아직 깊이 한계를 전달하지 않아 지금은 두 눈에 같은 화면을 보여 줍니다",
    "3D 深度：桌面尚未提供深度限制，暂时两眼显示相同的画面",
    "3D 深度：桌面尚未提供深度限制，暫時兩眼顯示相同的畫面"};

  t.limits_unreadable = {
    "3D depth: this window cannot read the desktop's depth limits, so both eyes show the same picture",
    "Głębia 3D: to okno nie może odczytać limitów głębi pulpitu, więc oba oczy widzą ten sam obraz",
    "Profundidade 3D: esta janela não consegue ler os limites de profundidade do desktop, então os dois olhos veem a mesma imagem",
    "Profondeur 3D : cette fenêtre ne peut pas lire les limites de profondeur du bureau, les deux yeux voient donc la même image",
    "3D-Tiefe: Dieses Fenster kann die Tiefengrenzen des Desktops nicht lesen, deshalb sehen beide Augen dasselbe Bild",
    "Profundidad 3D: esta ventana no puede leer los límites de profundidad del escritorio, así que los dos ojos ven la misma imagen",
    "3D奥行き: このウィンドウはデスクトップの奥行きの上限を読み取れないため、両目に同じ画像を表示します",
    "3D 깊이: 이 창은 데스크톱의 깊이 한계를 읽을 수 없어 두 눈에 같은 화면을 보여 줍니다",
    "3D 深度：此窗口无法读取桌面的深度限制，因此两眼显示相同的画面",
    "3D 深度：此視窗無法讀取桌面的深度限制，因此兩眼顯示相同的畫面"};

  t.no_stereo_desktop = {
    "This desktop offers no stereo buffers, so figures stay 2D.",
    "Ten pulpit nie udostępnia buforów stereo, więc rysunki pozostają w 2D.",
    "Este desktop não oferece buffers estéreo, então as figuras ficam em 2D.",
    "Ce bureau n’offre pas de tampons stéréo : les figures restent donc en 2D.",
    "Dieser Desktop bietet keine Stereo-Puffer, deshalb bleiben Abbildungen 2D.",
    "Este escritorio no ofrece búferes estéreo, así que las figuras siguen en 2D.",
    "このデスクトップはステレオバッファーを提供しないため、図は 2D のままです。",
    "이 데스크톱은 스테레오 버퍼를 제공하지 않아 그림은 2D로 유지됩니다.",
    "此桌面不提供立体缓冲区，因此图窗保持 2D。",
    "此桌面不提供立體緩衝區，因此圖窗維持 2D。"};

  t.no_stereo_buffers = {
    "3D: this figure got no stereo buffers, so it is shown in 2D",
    "3D: ten rysunek nie otrzymał buforów stereo, więc jest wyświetlany w 2D",
    "3D: esta figura não recebeu buffers estéreo, então é mostrada em 2D",
    "3D : cette figure n’a pas reçu de tampons stéréo, elle est donc affichée en 2D",
    "3D: Diese Abbildung hat keine Stereo-Puffer erhalten, deshalb wird sie in 2D gezeigt",
    "3D: esta figura no recibió búferes estéreo, así que se muestra en 2D",
    "3D: この図はステレオバッファーを得られなかったため、2D で表示します",
    "3D: 이 그림은 스테레오 버퍼를 받지 못해 2D로 표시됩니다",
    "3D：此图窗未获得立体缓冲区，因此以 2D 显示",
    "3D：此圖窗未取得立體緩衝區，因此以 2D 顯示"};

  t.depth_unreadable = {
    "3D depth: the depth of this figure could not be read, so both eyes show the same picture",
    "Głębia 3D: nie udało się odczytać głębi tego rysunku, więc oba oczy widzą ten sam obraz",
    "Profundidade 3D: não foi possível ler a profundidade desta figura, então os dois olhos veem a mesma imagem",
    "Profondeur 3D : la profondeur de cette figure n’a pas pu être lue, les deux yeux voient donc la même image",
    "3D-Tiefe: Die Tiefe dieser Abbildung konnte nicht gelesen werden, deshalb sehen beide Augen dasselbe Bild",
    "Profundidad 3D: no se pudo leer la profundidad de esta figura, así que los dos ojos ven la misma imagen",
    "3D奥行き: この図の奥行きを読み取れなかったため、両目に同じ画像を表示します",
    "3D 깊이: 이 그림의 깊이를 읽을 수 없어 두 눈에 같은 화면을 보여 줍니다",
    "3D 深度：无法读取此图窗的深度，因此两眼显示相同的画面",
    "3D 深度：無法讀取此圖窗的深度，因此兩眼顯示相同的畫面"};

  t.separation_property = {
    "3D depth: the figure property stereoeyeseparation no longer sets the depth; the depth is fitted to the limits in the desktop's 3D settings",
    "Głębia 3D: właściwość rysunku stereoeyeseparation nie ustala już głębi; głębia jest dopasowana do limitów z ustawień 3D pulpitu",
    "Profundidade 3D: a propriedade de figura stereoeyeseparation não define mais a profundidade; a profundidade é ajustada aos limites das configurações 3D do desktop",
    "Profondeur 3D : la propriété de figure stereoeyeseparation ne fixe plus la profondeur ; la profondeur est ajustée aux limites des réglages 3D du bureau",
    "3D-Tiefe: Die Abbildungseigenschaft stereoeyeseparation legt die Tiefe nicht mehr fest; die Tiefe wird an die Grenzen in den 3D-Einstellungen des Desktops angepasst",
    "Profundidad 3D: la propiedad de figura stereoeyeseparation ya no fija la profundidad; la profundidad se ajusta a los límites de los ajustes 3D del escritorio",
    "3D奥行き: 図のプロパティ stereoeyeseparation は奥行きを決めなくなりました。奥行きはデスクトップの 3D 設定の上限に合わせます",
    "3D 깊이: 그림 속성 stereoeyeseparation은 더 이상 깊이를 정하지 않습니다. 깊이는 데스크톱 3D 설정의 한계에 맞춰집니다",
    "3D 深度：图窗属性 stereoeyeseparation 不再决定深度；深度按桌面 3D 设置中的限制自动调整",
    "3D 深度：圖窗屬性 stereoeyeseparation 不再決定深度；深度依桌面 3D 設定中的限制自動調整"};

  t.welcome_name = {
    "Octave in stereo 3D",
    "Octave w stereo 3D",
    "Octave em 3D estéreo",
    "Octave en 3D stéréo",
    "Octave in Stereo-3D",
    "Octave en 3D estéreo",
    "ステレオ 3D の Octave",
    "스테레오 3D로 보는 Octave",
    "立体 3D 中的 Octave",
    "立體 3D 中的 Octave"};

  t.welcome_title = {
    "A Klein bottle in stereo 3D: drag it to turn it",
    "Butelka Kleina w stereo 3D: przeciągnij, aby ją obrócić",
    "Uma garrafa de Klein em 3D estéreo: arraste para girá-la",
    "Une bouteille de Klein en 3D stéréo : faites-la glisser pour la tourner",
    "Eine Kleinsche Flasche in Stereo-3D: ziehen, um sie zu drehen",
    "Una botella de Klein en 3D estéreo: arrástrala para girarla",
    "ステレオ 3D のクラインの壺: ドラッグして回せます",
    "스테레오 3D 클라인 병: 끌어서 돌려 보세요",
    "立体 3D 中的克莱因瓶：拖动即可旋转",
    "立體 3D 中的克萊因瓶：拖曳即可旋轉"};

  t.welcome_menu = {
    "&Welcome",
    "&Powitanie",
    "&Boas-vindas",
    "&Bienvenue",
    "&Willkommen",
    "&Bienvenida",
    "ようこそ(&W)",
    "환영(&W)",
    "欢迎(&W)",
    "歡迎(&W)"};

  t.welcome_open_empty = {
    "Open &empty",
    "Otwórz &pusty",
    "Abrir &vazio",
    "Ouvrir &vide",
    "&Leer öffnen",
    "Abrir &vacío",
    "空で開く(&E)",
    "빈 상태로 열기(&E)",
    "空白打开(&E)",
    "空白開啟(&E)"};

  t.welcome_how = {
    "How it is &made",
    "Jak to &zrobiono",
    "Como é &feito",
    "Comment c’est &fait",
    "Wie es &gemacht ist",
    "Cómo está &hecho",
    "作り方(&M)",
    "만드는 방법(&M)",
    "制作方法(&M)",
    "製作方法(&M)"};

  t.welcome_hint = {
    "%s starts Octave without this example.   %s shows its code.",
    "%s uruchamia Octave bez tego przykładu.   %s pokazuje jego kod.",
    "%s abre o Octave sem este exemplo.   %s mostra o código dele.",
    "%s démarre Octave sans cet exemple.   %s montre son code.",
    "%s startet Octave ohne dieses Beispiel.   %s zeigt seinen Code.",
    "%s inicia Octave sin este ejemplo.   %s muestra su código.",
    "%s で、この例なしで Octave を起動します。   %s でコードを表示します。",
    "%s: 이 예제 없이 Octave를 시작합니다.   %s: 코드를 보여 줍니다.",
    "%s：启动 Octave 时不显示此示例。   %s：显示其代码。",
    "%s：啟動 Octave 時不顯示此範例。   %s：顯示其程式碼。"};

  t.welcome_empty_done = {
    "Octave will open empty from now on.  To see the example again: %s",
    "Od teraz Octave będzie się otwierać bez przykładu.  Aby znów zobaczyć przykład: %s",
    "De agora em diante o Octave abrirá vazio.  Para ver o exemplo de novo: %s",
    "Désormais, Octave s’ouvrira vide.  Pour revoir l’exemple : %s",
    "Octave öffnet sich ab jetzt leer.  Um das Beispiel wieder zu sehen: %s",
    "A partir de ahora Octave se abrirá vacío.  Para ver el ejemplo otra vez: %s",
    "これから Octave は空で開きます。  例をもう一度見るには: %s",
    "이제부터 Octave는 빈 상태로 열립니다.  예제를 다시 보려면: %s",
    "从现在起 Octave 将空白打开。  要再次查看示例：%s",
    "從現在起 Octave 將空白開啟。  要再次查看範例：%s"};

  t.welcome_again = {
    "To open with it again: %s",
    "Aby znów otwierać z nim: %s",
    "Para abrir com ele de novo: %s",
    "Pour l’ouvrir de nouveau avec lui : %s",
    "Um wieder mit ihm zu öffnen: %s",
    "Para volver a abrir con él: %s",
    "また例付きで開くには: %s",
    "다시 예제와 함께 열려면: %s",
    "要恢复打开时显示示例：%s",
    "要恢復開啟時顯示範例：%s"};

endfunction

%!test
%! ## Every sentence exists in all ten languages, none empty
%! langs = {"en", "pl", "pt_BR", "fr", "de", "es", "ja", "ko", "zh_CN", "zh_TW"};
%! for key = {"menu-enable-3d", "limits-not-offered", "separation-property", "welcome-hint"}
%!   for l = langs
%!     assert (! isempty (sparky_stereo_text (key{1}, l{1})));
%!   endfor
%! endfor
%!error <no sentence> sparky_stereo_text ("no-such-key")
