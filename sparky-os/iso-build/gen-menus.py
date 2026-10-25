#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
"""gen-menus.py OUT PROFILE ISOLINUX_CFG DISK_INFO : the ISO's boot menus, for sparkybackup-stereo's BOOTMENUS.

OUT gets a copy of PROFILE (the packer's Stereo profile folder, /usr/lib/sparkybackup/stereo: the splash pictures, the
GRUB theme) with the menus written here:
  OUT/boot/grub/grub.cfg       UEFI: shim, then Debian's signed GRUB, then the edition's kernel
  OUT/isolinux/isolinux.cfg    BIOS (ISOLINUX_CFG gives the header: colours, title, background)
  OUT/.disk/info               DISK_INFO, the line GRUB's EFI image searches for (and the label people see)
The ISO carries the edition's kernel and no other (Daniel, 2026-10-24). Under Secure Boot, shim checks that kernel
against its MOK list, so a machine that does not know the edition's key yet refuses it ("bad shim loader signature",
grub-core/kern/efi/sb.c). Every live entry then explains it in the nine required languages and opens the menu again
with "Secure Boot: enroll the Sparky Stereo OS key" selected (GRUB puts "default" back after an entry,
grub_menu_execute_entry in grub-core/normal/menu.c, so the menu is loaded again with configfile and sparky_default).
That entry shows MokManager's steps in the nine languages and starts Debian's signed MokManager (mmx64.efi, beside
shim on the EFI image) to enroll the certificate the EFI image carries. GRUB sets shim_lock=y when Secure Boot is on
and shim's protocol is there (grub_shim_lock_verifier_setup), so a kernel refused for another reason shows only
GRUB's error. GRUB's sleep --interruptible stops on Esc, F4 or Shift (grub_key_is_interrupt, grub-core/kern/term.c),
so the texts name Esc. The theme's terminal takes the whole screen (100 columns and 37 lines at 800x600) for them.
"""
import os
import shutil
import sys
import unicodedata

NAME = 'Sparky Stereo OS'
ENROLL = 'Secure Boot: enroll the Sparky Stereo OS key'
CERT = 'sparky-stereo-secureboot-2026.der'
COLUMNS = 98   # GRUB's gfxterm at 800x600 (config.cfg) with Unifont 16: 100 columns

# The nine required languages (en, pl, pt_BR, fr, de, ja, ko, zh_CN, zh_TW). The live menu itself is English, with a
# language submenu; these texts are shown when a person needs them, every language at once, because the menu cannot
# know the person's language before the system starts. MokManager is English only, so its menu items stay English.
NO_KEY = [
    ('English', 'Secure Boot is on, and this computer does not know the Sparky Stereo OS key yet. Choose “' + ENROLL
     + '” (selected in the menu that follows) to enroll it once, or turn Secure Boot off in “uEFI firmware setup”. '
     'Esc: go on now.'),
    ('Polski', 'Secure Boot jest włączony, a ten komputer nie zna jeszcze klucza Sparky Stereo OS. Wybierz „' + ENROLL
     + '” (zaznaczone w następnym menu), aby jednorazowo zarejestrować klucz, albo wyłącz Secure Boot w „uEFI firmware '
     'setup”. Esc: dalej.'),
    ('Português', 'O Secure Boot está ligado e este computador ainda não conhece a chave do Sparky Stereo OS. Escolha “'
     + ENROLL + '” (selecionada no menu a seguir) para registrar a chave uma vez, ou desligue o Secure Boot em “uEFI '
     'firmware setup”. Esc: continuar agora.'),
    ('Français', 'Secure Boot est activé et cet ordinateur ne connaît pas encore la clé de Sparky Stereo OS. Choisissez « '
     + ENROLL + ' » (sélectionnée dans le menu suivant) pour l’enregistrer une fois, ou désactivez Secure Boot dans « uEFI '
     'firmware setup ». Échap : continuer.'),
    ('Deutsch', 'Secure Boot ist eingeschaltet, und dieser Computer kennt den Schlüssel von Sparky Stereo OS noch nicht. '
     'Wählen Sie „' + ENROLL + '“ (im folgenden Menü ausgewählt), um ihn einmalig einzutragen, oder schalten Sie Secure '
     'Boot unter „uEFI firmware setup“ aus. Esc: weiter.'),
    ('日本語', 'セキュアブートが有効ですが、このコンピューターはまだ Sparky Stereo OS の鍵を知りません。「' + ENROLL
     + '」(次のメニューで選択済み) を選んで鍵を一度だけ登録するか、「uEFI firmware setup」でセキュアブートを無効にして'
     'ください。Esc: すぐに続行。'),
    ('한국어', '보안 부팅이 켜져 있지만 이 컴퓨터는 아직 Sparky Stereo OS 키를 모릅니다. “' + ENROLL
     + '”(다음 메뉴에서 선택됨)을 골라 키를 한 번 등록하거나, “uEFI firmware setup”에서 보안 부팅을 끄세요. Esc: 바로 계속.'),
    ('简体中文', '安全启动已开启，但这台电脑还不认识 Sparky Stereo OS 的密钥。请选择“' + ENROLL
     + '”（在接下来的菜单中已选中）一次性注册密钥，或在“uEFI firmware setup”中关闭安全启动。Esc：立即继续。'),
    ('繁體中文', '安全開機已開啟，但這台電腦還不認得 Sparky Stereo OS 的金鑰。請選擇「' + ENROLL
     + '」（在接下來的選單中已選取）一次性註冊金鑰，或在「uEFI firmware setup」中關閉安全開機。Esc：立即繼續。'),
]
STEPS = 'Enroll key from disk, ?, EFI, boot, ' + CERT + ', Continue, Yes, Reboot'
MOKMANAGER = [
    ('English', 'MokManager starts now (English only). Press a key when it asks, then choose: '
     + STEPS.replace('?', 'the disk shown') + '. Then start Sparky Stereo OS again. Esc: start it now.'),
    ('Polski', 'Teraz uruchomi się MokManager (tylko po angielsku). Gdy poprosi, naciśnij klawisz, potem wybierz: '
     + STEPS.replace('?', 'pokazany dysk') + '. Potem uruchom ponownie Sparky Stereo OS. Esc: uruchom teraz.'),
    ('Português', 'O MokManager vai abrir agora (só em inglês). Aperte uma tecla quando ele pedir e escolha: '
     + STEPS.replace('?', 'o disco mostrado') + '. Depois inicie o Sparky Stereo OS de novo. Esc: abrir agora.'),
    ('Français', 'MokManager démarre maintenant (en anglais seulement). Appuyez sur une touche quand il le demande, puis '
     'choisissez : ' + STEPS.replace('?', 'le disque affiché') + '. Puis relancez Sparky Stereo OS. Échap : démarrer tout '
     'de suite.'),
    ('Deutsch', 'Jetzt startet MokManager (nur auf Englisch). Drücken Sie eine Taste, wenn er danach fragt, und wählen '
     'Sie dann: ' + STEPS.replace('?', 'das angezeigte Laufwerk') + '. Danach Sparky Stereo OS neu starten. Esc: sofort '
     'starten.'),
    ('日本語', 'これから MokManager (英語のみ) が起動します。求められたらキーを押し、次の順に選んでください: '
     + STEPS.replace('?', '表示されたディスク').replace(', ', '、') + '。その後 Sparky Stereo OS をもう一度起動します。'
     'Esc: すぐに起動。'),
    ('한국어', '이제 MokManager(영어 전용)가 시작됩니다. 요청하면 키를 누른 뒤 차례로 고르세요: '
     + STEPS.replace('?', '표시된 디스크') + '. 그다음 Sparky Stereo OS를 다시 시작하세요. Esc: 바로 시작.'),
    ('简体中文', '现在将启动 MokManager（仅英文）。提示时按任意键，然后依次选择：'
     + STEPS.replace('?', '显示的磁盘').replace(', ', '、') + '。之后重新启动 Sparky Stereo OS。Esc：立即启动。'),
    ('繁體中文', '現在將啟動 MokManager（僅英文）。提示時按任意鍵，然後依序選擇：'
     + STEPS.replace('?', '顯示的磁碟').replace(', ', '、') + '。之後重新啟動 Sparky Stereo OS。Esc：立即啟動。'),
]

LANGS = [('Arabic', 'ar_AE'), ('Bengali', 'bn_BD'), ('Bulgarian', 'bg_BG'), ('Chinese CN', 'zh_CN'),
         ('Chinese TW', 'zh_TW'), ('Croatian', 'hr_HR'), ('Czech', 'cs_CZ'), ('Danish', 'da_DK'),
         ('Dutch', 'nl_NL'), ('Finnish', 'fi_FI'), ('French', 'fr_FR'), ('German', 'de_DE'), ('Greek', 'el_GR'),
         ('Hebrew', 'he_IL'), ('Hindi', 'hi_IN'), ('Hungarian', 'hu_HU'), ('Indonesian', 'id_ID'),
         ('Italian', 'it_IT'), ('Japanese', 'ja_JP'), ('Korean', 'ko_KR'), ('Norwegian', 'no_NO'),
         ('Polish', 'pl_PL'), ('Portuguese BR', 'pt_BR'), ('Portuguese PT', 'pt_PT'), ('Romanian', 'ro_RO'),
         ('Russian', 'ru_RU'), ('Slovak', 'sk_SK'), ('Slovenian', 'sl_SI'), ('Spanish', 'es_ES'),
         ('Swedish', 'sv_SE'), ('Thai', 'th_TH'), ('Turkish', 'tr_TR'), ('UK English', 'en_GB'),
         ('Ukrainian', 'uk_UA'), ('Urdu', 'ur_PK')]
KEYMAP = {'de_DE': 'de', 'fr_FR': 'fr', 'pl_PL': 'pl', 'pt_BR': 'br', 'pt_PT': 'pt', 'es_ES': 'es',
          'it_IT': 'it', 'cs_CZ': 'cz', 'hu_HU': 'hu', 'en_GB': 'gb', 'ru_RU': 'ru', 'uk_UA': 'ua',
          'sv_SE': 'se', 'da_DK': 'dk', 'fi_FI': 'fi', 'no_NO': 'no', 'nl_NL': 'nl', 'tr_TR': 'tr',
          'sk_SK': 'sk', 'sl_SI': 'si', 'hr_HR': 'hr', 'ro_RO': 'ro', 'bg_BG': 'bg', 'el_GR': 'gr',
          'ja_JP': 'jp', 'ko_KR': 'kr'}


def width(text):
    return sum(2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in text)


def wrap(text, columns):
    """Breaks TEXT into lines of at most COLUMNS display columns: at spaces, or anywhere in CJK text."""
    lines, line = [], ''
    for word in text.replace('、', '、\0').replace('，', '，\0').replace('。', '。\0').split(' '):
        for piece in word.split('\0'):
            sep = '' if not line or line.endswith(('、', '，', '。')) or not piece else ' '
            if width(line + sep + piece) <= columns:
                line += sep + piece
                continue
            if line:
                lines.append(line)
            line = ''
            for c in piece:   # a piece longer than a line (CJK runs have no spaces)
                if width(line + c) > columns:
                    lines.append(line)
                    line = ''
                line += c
        # the next word follows a space
    if line:
        lines.append(line)
    return lines


def grub_text(texts, indent):
    """echo lines for GRUB: each language's name, then its text, wrapped for the screen. GRUB's double-quoted
    strings expand $ and \\, so the texts must not contain them."""
    out = []
    for lang, text in texts:
        assert not set('$"\\') & set(text), text
        for n, line in enumerate(wrap(lang + ': ' + text, COLUMNS)):
            out.append(f'{indent}echo "{line}"')
    return out


def lang_args(loc):
    a = f'locales={loc}.UTF-8'
    if loc in KEYMAP:
        a += f' keyboard-layouts={KEYMAP[loc]}'
    return a


def grub_entry(title, args, indent=''):
    i = indent
    return (f'{i}menuentry "{title}" {{\n'
            f'{i}    if linux /live/vmlinuz {args}; then\n'
            f'{i}        initrd /live/initrd.img\n'
            f'{i}    else\n'
            f'{i}        sparky_no_key\n'
            f'{i}    fi\n'
            f'{i}}}\n')


def grub_cfg():
    live, find = 'boot=live components', 'findiso=${iso_path}'
    g = ['source /boot/grub/config.cfg',
         'if [ -n "$sparky_default" ]; then',
         '    set default="$sparky_default"',
         'fi', '',
         '# The edition\'s kernel is the only one on this medium. Under Secure Boot shim refuses it until the',
         '# Sparky Stereo OS key is in the MOK list: then the entry says so in the nine required languages and opens',
         '# the menu again with the entry that enrolls the key with MokManager selected.',
         'function sparky_no_key {',
         '    if [ "$shim_lock" = y ]; then',
         *grub_text(NO_KEY, '        '),
         '        sleep --interruptible --verbose 60',
         '        set sparky_default=sparky-enroll',
         '        export sparky_default',
         '        configfile /boot/grub/grub.cfg',
         '    fi',
         '}', '']
    g.append(grub_entry(f'{NAME} (live)', f'{live} quiet splash {find}'))
    g.append(grub_entry(f'{NAME} (live, Deutsch)', f'{live} {lang_args("de_DE")} quiet splash {find}'))
    # MokManager is a 64-bit program: only on 64-bit UEFI (GRUB's script has no &&: one if inside the other)
    g.append('\n'.join([
        'if [ "$grub_platform" = efi ]; then',
        '    if [ "$grub_cpu" = x86_64 ]; then',
        f'        menuentry "{ENROLL}" --id sparky-enroll {{',
        *grub_text(MOKMANAGER, '            '),
        '            sleep --interruptible --verbose 60',
        '            terminal_output console',
        '            chainloader /EFI/boot/mmx64.efi',
        '        }',
        '    fi',
        'fi']) + '\n')
    g.append(grub_entry('Safe graphics (nomodeset)', f'{live} nomodeset nosplash {find}'))
    g.append(grub_entry('NoSplash', f'{live} nosplash {find}'))
    g.append(grub_entry('Failsafe mode', f'{live} memtest noapic noapm nodma nomce nolapic nosmp nosplash vga=788 {find}'))
    g.append(grub_entry('Copy ToRAM', f'{live} toram quiet splash {find}'))
    g.append(grub_entry('Text mode', f'{live} quiet nosplash systemd.unit=multi-user.target {find}'))
    g.append('menuentry "Memory Test x64.efi" {\n    linux   /boot/memtest86+x64.efi\n}\n')
    g.append('menuentry "uEFI firmware setup" {\n    fwsetup\n}\n')
    g.append("submenu --hotkey=m 'More Languages...' {\n    set color_normal=light-gray/black\n"
             "    set color_highlight=white/black\n")
    for name, loc in LANGS:
        g.append(grub_entry(f'{NAME} {name}', f'{live} {lang_args(loc)} quiet splash {find}', '    '))
    g.append('}\n')
    return '\n'.join(g)


def isolinux_cfg(head):
    def entry(label, title, args):
        return f'label {label}\n\tmenu label {title}\n\tkernel /live/vmlinuz\n\tappend initrd=/live/initrd.img {args}\n'
    cfg = 'boot=live config'
    il = [head, '',
          entry('live', '__LIVELABEL__ (live)', f'{cfg} quiet splash'),
          entry('livede', '__LIVELABEL__ (live, Deutsch)', f'{cfg} {lang_args("de_DE")} quiet splash'),
          entry('livenosplash', 'NoSplash', f'{cfg} quiet nosplash'),
          entry('livefailsafe', 'Failsafe', f'{cfg} noapic noapm nodma nomce nolapic pci=nomsi nomodeset radeon.modeset=0 '
                'nouveau.modeset=0 nosmp vga=normal nosplash'),
          entry('livetoram', 'Copy ToRAM', f'{cfg} toram nosplash'),
          entry('livetext', 'Text mode', f'{cfg} systemd.unit=multi-user.target nosplash'),
          'label hd\n\tmenu label Boot the first hard disk\n\tCOM32 chain.c32\n\tAPPEND hd0\n',
          'menu begin More Languages...\n']
    for name, loc in LANGS:
        il.append(entry('live', f'__LIVELABEL__ {name}', f'{cfg} quiet splash {lang_args(loc)}'))
    il += ['menu end\n', 'label memtest\n\tmenu label Memory Test\n\tkernel /isolinux/memtest\n\tappend -\n',
           'label hdt\n\tmenu label Hardware Detection\n\tkernel /isolinux/hdt.c32\n\tappend -\n']
    return '\n'.join(il)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    out, profile, head_cfg, info = sys.argv[1:]
    if os.path.exists(out):
        shutil.rmtree(out)
    shutil.copytree(profile, out, symlinks=True)
    shutil.rmtree(os.path.join(out, 'secureboot'), ignore_errors=True)   # the certificate goes on the EFI image only
    theme = os.path.join(out, 'boot/grub/live-theme/theme.txt')
    if os.path.exists(theme):
        text = open(theme, encoding='utf-8').read()
        with open(theme, 'w', encoding='utf-8') as f:
            f.write('# the terminal (a running entry, the editor, the command line) takes the whole screen: the Secure Boot\n'
                    '# texts in the nine required languages need its 100 columns and 37 lines at 800x600\n'
                    'terminal-left: "0"\nterminal-top: "0"\nterminal-width: "100%"\nterminal-height: "100%"\n'
                    'terminal-border: "0"\n' + text)
    os.makedirs(os.path.join(out, 'boot/grub'), exist_ok=True)
    os.makedirs(os.path.join(out, 'isolinux'), exist_ok=True)
    os.makedirs(os.path.join(out, '.disk'), exist_ok=True)
    with open(os.path.join(out, 'boot/grub/grub.cfg'), 'w', encoding='utf-8') as f:
        f.write(grub_cfg())
    head = open(head_cfg, encoding='utf-8').read().split('\nlabel live\n')[0].rstrip('\n')
    with open(os.path.join(out, 'isolinux/isolinux.cfg'), 'w', encoding='utf-8') as f:
        f.write(isolinux_cfg(head))
    with open(os.path.join(out, '.disk/info'), 'w', encoding='utf-8') as f:
        f.write(info.rstrip('\n') + '\n')


if __name__ == '__main__':
    main()
