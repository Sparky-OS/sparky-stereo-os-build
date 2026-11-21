// For each locale given, loads Jmol's Stereo3D bundle the way Stereo3D.tr() does (ResourceBundle.getBundle with that
// locale as the default) from the jar on the class path, and prints the bundle file that answered and its five sentences.
import java.util.Locale;
import java.util.ResourceBundle;

public class BundleCheck {
  public static void main(String[] args) {
    String[] keys = {"enable3D", "displaySettings3D", "flatNoArea", "flatNotX11", "settingsFailed"};
    for (String tag : args) {
      String[] p = tag.split("_");
      Locale.setDefault(p.length > 1 ? Locale.of(p[0], p[1]) : Locale.of(p[0]));
      ResourceBundle.clearCache();
      ResourceBundle b = ResourceBundle.getBundle("org.openscience.jmol.app.jmolpanel.Properties.Stereo3D");
      StringBuilder s = new StringBuilder(tag + "\tbundle=" + (b.getLocale().toString().isEmpty() ? "(base)" : b.getLocale()));
      for (String k : keys) s.append("\t").append(k).append("=").append(b.getString(k));
      System.out.println(s);
    }
  }
}
