// SPDX-License-Identifier: GPL-3.0-or-later
import java.awt.SystemTray;
import java.lang.reflect.Method;

/** Compare the platform tray with the unchanged application's own platform policy. */
public class TrayProbe {
    public static void main(String[] args) throws Exception {
        System.out.println("AWT SystemTray.isSupported=" + SystemTray.isSupported());
        Class<?> type = Class.forName("br.jus.cnj.pje.office.imp.PjeOfficeFrontEnd");
        Method supports = type.getDeclaredMethod("supportsSystray");
        supports.setAccessible(true);
        System.out.println("PJeOfficeFrontEnd.supportsSystray=" + supports.invoke(null));
    }
}
