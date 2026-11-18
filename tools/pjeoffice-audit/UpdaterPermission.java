// SPDX-License-Identifier: GPL-3.0-or-later
import java.lang.reflect.Method;

/** Executes the unmodified upstream updater's preliminary write check only. */
public class UpdaterPermission {
    public static void main(String[] args) throws Exception {
        Class<?> type = Class.forName("br.jus.cnj.pje.office.updater.imp.Updater");
        Object updater = type.getField("INSTANCE").get(null);
        Method check = type.getDeclaredMethod("checkWritingPermission");
        check.setAccessible(true);
        System.out.println("upstream checkWritingPermission=" + check.invoke(updater));
        System.out.println("upstream isDisabled=" + type.getMethod("isDisabled").invoke(updater));
    }
}
