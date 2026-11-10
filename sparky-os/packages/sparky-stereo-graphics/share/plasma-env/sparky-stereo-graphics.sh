# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
# Sourced by startplasma before sparky-stereo-primary-gpu.sh. The main desktop GPU the person chose
# in System Settings, Graphics becomes KWIN_DRM_DEVICES at this login. Automatic sets nothing, so
# the edition's own rule in sparky-stereo-primary-gpu.sh and KWin's order stay in charge. A
# KWIN_DRM_DEVICES the person set by hand, here or in ~/.config/plasma-workspace/env, wins.
# A chosen GPU that cannot draw (not in the computer, no driver, no render node) is never replaced
# by another one in the person's name: sparky-stereo-gpu-env says why in the session's log and keeps
# it, and the notification at login (sparky-stereo-graphics-problems.service) offers the GPUs that
# can draw as the person's explicit choice. Until then KWin's own order draws this login, since
# nothing could be shown without a desktop.
if [ -z "${KWIN_DRM_DEVICES:-}" ]; then
	if command -v sparky-stereo-gpu-env >/dev/null 2>&1; then
		if _sp_graphics=$(sparky-stereo-gpu-env --session); then
			[ -z "$_sp_graphics" ] || eval "$_sp_graphics"
		fi
	elif [ "$(dpkg-query -W -f='${db:Status-Status}' sparky-stereo-graphics 2>/dev/null)" = installed ]; then
		# the package is installed and its command is gone: said in the session's log (a removed package's
		# leftover configuration is the person's choice and says nothing)
		_sp_lang=${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}
		_sp_lang=${_sp_lang%%.*}
		case ${_sp_lang%%@*} in
		zh_TW | zh_HK) _sp_lang=zh_TW ;;
		zh*) _sp_lang=zh_CN ;;
		pt_BR) _sp_lang=pt_BR ;;
		*) _sp_lang=${_sp_lang%%_*} ;;
		esac
		case $_sp_lang in
		pl) _sp_m='Brakuje sparky-stereo-gpu-env, więc nie można zastosować procesora graficznego wybranego w Ustawieniach systemowych, Grafika. Zainstaluj go ponownie: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		pt_BR) _sp_m='O sparky-stereo-gpu-env não está instalado, então a GPU escolhida em Configurações do Sistema, Gráficos não pode ser aplicada. Reinstale-o: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		fr) _sp_m="sparky-stereo-gpu-env est absent : le GPU choisi dans Configuration du système, Graphiques ne peut pas être appliqué. Réinstallez-le : sudo apt-get install --reinstall sparky-stereo-graphics" ;;
		de) _sp_m='sparky-stereo-gpu-env fehlt, daher kann die in den Systemeinstellungen unter Grafik gewählte GPU nicht angewendet werden. Installieren Sie es neu: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		es) _sp_m='Falta sparky-stereo-gpu-env, así que no se puede aplicar la GPU elegida en Configuración del sistema, Gráficos. Reinstálelo: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		ja) _sp_m='sparky-stereo-gpu-env が見つからないため、システム設定の「グラフィックス」で選んだ GPU を適用できません。再インストールしてください: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		ko) _sp_m='sparky-stereo-gpu-env가 없어서 시스템 설정의 그래픽에서 선택한 GPU를 적용할 수 없습니다. 다시 설치하십시오: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		zh_CN) _sp_m='缺少 sparky-stereo-gpu-env，因此无法应用在“系统设置 > 图形”中选择的 GPU。请重新安装：sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		zh_TW) _sp_m='缺少 sparky-stereo-gpu-env，因此無法套用在「系統設定 > 圖形」中選擇的 GPU。請重新安裝：sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		*) _sp_m='sparky-stereo-gpu-env is missing, so the GPU chosen in System Settings, Graphics cannot be applied. Reinstall it: sudo apt-get install --reinstall sparky-stereo-graphics' ;;
		esac
		echo "sparky-stereo-graphics: $_sp_m" >&2
		unset _sp_lang _sp_m
	fi
	unset _sp_graphics
fi
