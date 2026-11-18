// SPDX-License-Identifier: GPL-3.0-or-later
import com.github.cutplayer4j.imp.*;
import com.github.cutplayer4j.event.*;
import javax.swing.SwingUtilities;
public class CutterTaskProbe {
 public static void main(String[] a) throws Exception {
  CutPlayer4JApp.main(a);
  Thread.sleep(2500);
  SwingUtilities.invokeLater(()->{
   CutPlayer4J.application().post(new CutStartEvent(1000));
   CutPlayer4J.application().post(new CutEndEvent(4000));
  });
 }
}
