import re
SHA='6087391759c7cba11fb5ef815fe8be91713b46a8607c12eb664a9d9a6882c4c7'
SIZE='167505940'
URL='https://pje-office.pje.jus.br/pro'
FILE='pjeoffice-pro-v2.5.16u-linux_x64.zip'

def edit(path, pairs):
    s = open(path, encoding='utf-8', newline='').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:60], s.count(old))
        s = s.replace(old, new)
    open(path, 'w', encoding='utf-8', newline='').write(s)

APP_CHECK = '''##### office others #####
elif [ "$1" = "pjeoffice" ]; then
	# CNJ's program with its own Java 8, for x86_64 only
	if [ "$ARCH64" = "" ]; then
		SYSTEM="wrong"
		ERRORPJEOFFICE="arch"
	fi
	PACKAGE="$1"

'''
APP_ERR = '''elif [ "$ERRORPJEOFFICE" = "arch" ]; then
	ERRORTEXT="$LOCAL004"
'''
APP_INFO = '''# pjeoffice is not a deb package, so tell here what will be downloaded
if [ "$1" = "pjeoffice" ]; then
	VERSION="Version: 2.5.16u"
	SECTION="Section: office"
	MAINTAINER="Author: CNJ, TRF3"
	DOWNSIZE="Download-Size: 159.7 MiB"
	INSTSIZE="Installed-Size: 340 MB"
	DESCRIPTION1="Description: signer of Brazil's court e-filing system (PJe)"
	DESCRIPTION2="PJeOffice Pro is downloaded from CNJ's own address and checked against a size and a SHA-256 written here; this entry also installs OpenSC, pcscd and libccid for tokens.<br />Its own updater is switched off: a new version comes with a new version of this entry.<br />Certificates and PINs stay in the program's own window.<br />Homepage: https://pjeoffice.trf3.jus.br/pjeoffice-pro/docs/userguide.html"
fi

'''
APP_BUTTONS = '''# install, reinstall or remove pjeoffice
elif [ "$1" = "pjeoffice" ]; then
	if [ -f /opt/pjeoffice-pro/pjeoffice-pro.jar ]; then
		PACKTITLE="Remove or Reinstall Package"
		PACKTEXT="$LOCAL011 $LOCAL012"
		PACKBUTTONS="<a href="aptus://debremo_$1" class="buttonmenu">$LOCAL008</a>&nbsp;&nbsp; <a href="aptus://debrein_$1" class="buttonmenu">$LOCAL009</a>&nbsp;&nbsp; <a href="aptus://idzi_idzi" class="buttonmenu">$LOCAL001</a><br />"
	elif [ ! -f /opt/pjeoffice-pro/pjeoffice-pro.jar ]; then
		if [ "$PINGTEST" = "" ]; then
			PACKTITLE="Install Package"
			PACKTEXT="$LOCAL003 $LOCAL005"
			PACKBUTTONS="<a href="aptus://idzi_idzi" class="buttonmenu">$LOCAL001</a><br />"
		else
			PACKTITLE="Install Package"
			PACKTEXT="$LOCAL014"
			PACKBUTTONS="<a href="aptus://debinst_$1" class="buttonmenu">$LOCAL010</a>&nbsp;&nbsp; <a href="aptus://idzi_idzi" class="buttonmenu">$LOCAL001</a><br />"
		fi
	fi

'''
VARS = f'''SERVERPJEOFFICE="{URL}"
PACKPJEOFFICE="{FILE}"
SHAPJEOFFICE="{SHA}"
SIZEPJEOFFICE="{SIZE}"
'''
def install_block(verb_done, verb_fail):
    return f'''elif [ "$PACKAGE" = "pjeoffice" ]; then
	#kill -USR1 $YAD_PID
	rm -rf /tmp/sparky-appcenter
	mkdir -p $WORKDIR
	cd $WORKDIR
	# CNJ's ZIP from its own address, checked against the size and the SHA-256 of the file as reviewed on 2026-11-18 (the server keeps no checksum file)
	$SPARKYXTERM "wget $SERVERPJEOFFICE/$PACKPJEOFFICE"
	if [ -f $PACKPJEOFFICE ] && [ "`stat -c %s $PACKPJEOFFICE`" = "$SIZEPJEOFFICE" ] && echo "$SHAPJEOFFICE  $PACKPJEOFFICE" | sha256sum -c - >/dev/null 2>&1; then
		# tokens (OpenSC, pcscd, libccid), the unpacker and the libraries of the program's own Java
		$SPARKYXTERM "$INSTALL -y --no-remove unzip opensc pcscd libccid ffmpeg libgtk-3-0t64 libxtst6 libxi6 libxrender1 libxxf86vm1 libasound2t64 fontconfig fonts-dejavu-core && touch $WORKDIR/pjeoffice-dependencies-ready"
		if [ ! -f $WORKDIR/pjeoffice-dependencies-ready ] || ! command -v unzip >/dev/null 2>&1; then
			$SPARKYXTERM "echo 'PJeOffice Pro needs unzip, OpenSC, pcscd, libccid and the libraries of its Java, and a required package is NOT installed. Nothing has been {verb_fail}.' && echo 'Press <ENTER> to exit...' && read"
		else
			rm -rf $WORKDIR/unpacked && mkdir -p $WORKDIR/unpacked
			unzip -q $PACKPJEOFFICE -d $WORKDIR/unpacked
			if [ ! -f $WORKDIR/unpacked/pjeoffice-pro/pjeoffice-pro.jar ] || [ ! -f $WORKDIR/unpacked/pjeoffice-pro/jre/bin/java ]; then
				$SPARKYXTERM "echo 'The downloaded file does NOT hold the program as expected. Nothing has been {verb_fail}.' && echo 'Press <ENTER> to exit...' && read"
			else
				# CNJ's own updater would try to patch a folder only root can write: it is switched off, the entry updates the program
				sed -i 's|^update.url[[:space:]]*=.*|update.url=disabled|' $WORKDIR/unpacked/pjeoffice-pro/pjeoffice-update.properties
				chmod 755 $WORKDIR/unpacked/pjeoffice-pro/jre/bin/* $WORKDIR/unpacked/pjeoffice-pro/ffmpeg.exe $WORKDIR/unpacked/pjeoffice-pro/pjeoffice-pro.sh
				rm -rf /opt/pjeoffice-pro
				mv $WORKDIR/unpacked/pjeoffice-pro /opt/pjeoffice-pro || exit 1
				ln -sf /opt/pjeoffice-pro/pjeoffice-pro.sh /usr/bin/pjeoffice-pro
				printf '[Desktop Entry]\\nType=Application\\nName=PJeOffice Pro\\nComment=Signer of the court e-filing system (PJe)\\nExec=/opt/pjeoffice-pro/pjeoffice-pro.sh\\nIcon=application-certificate\\nTerminal=false\\nCategories=Office;Utility;\\n' > /usr/share/applications/pjeoffice-pro.desktop
				$SPARKYXTERM "echo 'PJeOffice Pro has been {verb_done} in /opt/pjeoffice-pro.' && echo 'Done, press <ENTER> to exit...' && read"
			fi
		fi
	elif [ -f $WORKDIR/$PACKPJEOFFICE ]; then
		$SPARKYXTERM "echo 'The downloaded file does NOT match the size and the SHA-256 reviewed for it. Nothing has been {verb_fail}.' && echo 'Press <ENTER> to exit...' && read"
	else
		$SPARKYXTERM "echo 'The download has failed. Nothing has been {verb_fail}.' && echo 'Check your internet connection and try again.' && echo 'Press <ENTER> to exit...' && read"
	fi
	rm -rf /tmp/sparky-appcenter

'''
REMOVE_BLOCK = '''elif [ "$PACKAGE" = "pjeoffice" ]; then
	# the program, its menu entry and its link, only; certificates, settings and files in the home folders stay with their users
	$SPARKYXTERM "rm -rfv /opt/pjeoffice-pro /usr/bin/pjeoffice-pro /usr/share/applications/pjeoffice-pro.desktop && echo 'Done, press <ENTER> to exit...' && read"

'''
CHECK_AFTER = '''if [ "$PACKAGE" = "pjeoffice" ] && [ -f /opt/pjeoffice-pro/pjeoffice-pro.jar ]; then
	CHECKPACKAGE0="pjeoffice"
fi
'''
for tree in ('8', '9'):
    base = tree + '/lib/sparky-aptus-appcenter/bin/'
    edit(base + 'aptus-app', [
        ('##### accessories devices #####\n', APP_CHECK + '##### accessories devices #####\n'),
        ('elif [ "$ERRORKAMLYNK" = "arch" ]; then\n', APP_ERR + 'elif [ "$ERRORKAMLYNK" = "arch" ]; then\n'),
        ('# kamlynk is not a deb package, so tell here what will be downloaded\n', APP_INFO + '# kamlynk is not a deb package, so tell here what will be downloaded\n'),
        ('# install, reinstall or remove vinci\n', APP_BUTTONS + '# install, reinstall or remove vinci\n'),
    ])
    for name, done, failed, check in (('aptus-package-install', 'installed', 'installed', True), ('aptus-package-reinstall', 'reinstalled', 'changed', False)):
        s = open(base + name, encoding='utf-8', newline='').read()
        anchor = 'elif [ "$PACKAGE" = "vinci" ]; then\n'
        assert s.count(anchor) == 1, (name, s.count(anchor))
        s = s.replace(anchor, install_block(done, failed) + anchor)
        assert s.count('SERVERVINCI=') == 1
        s = s.replace('SERVERVINCI=', VARS + 'SERVERVINCI=', 1)
        if check:
            guard = 'if [ "$PACKAGE" = "vinci" ] && [ -f /usr/bin/vinci ]; then'
            assert s.count(guard) == 1
            s = s.replace(guard, CHECK_AFTER + guard, 1)
        open(base + name, 'w', encoding='utf-8', newline='').write(s)
    edit(base + 'aptus-package-remove', [
        ('elif [ "$PACKAGE" = "vinci" ]; then\n', REMOVE_BLOCK + 'elif [ "$PACKAGE" = "vinci" ]; then\n'),
        ('if [ "$PACKAGE" = "vinci" ] && [ -f /usr/bin/vinci ]; then', CHECK_AFTER + 'if [ "$PACKAGE" = "vinci" ] && [ -f /usr/bin/vinci ]; then'),
    ])
for tree in ('8', '9'):
    p = tree + '/lib/sparky-aptus-appcenter/office-document.html'
    s = open(p, encoding='utf-8', newline='').read()
    old = '\t\t<td><a href="aptus://offdoc_qpdfview" class="button1"><img src="images/pdf.svg" class="appicon"><br />qpdfview</a>\r\n'
    new = '\t\t<td><a href="aptus://offdoc_pjeoffice" class="button1"><img src="images/keyring.svg" class="appicon"><br />PJeOffice Pro</a>\r\n\t\t</td>\r\n' + old
    assert s.count(old) == 1
    open(p, 'w', encoding='utf-8', newline='').write(s.replace(old, new))
print('ok')
