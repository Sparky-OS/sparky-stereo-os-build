// SPDX-License-Identifier: GPL-3.0-or-later
import javafx.application.Platform;
import javafx.embed.swing.JFXPanel;
import javafx.scene.media.Media;
import javafx.scene.media.MediaPlayer;
import java.io.File;
public class MediaProbe {
 public static void main(String[] args) {
  new JFXPanel();
  Platform.runLater(() -> {
   try {
    MediaPlayer p = new MediaPlayer(new Media(new File(args[0]).toURI().toString()));
    p.setOnError(() -> {p.getError().printStackTrace(); System.exit(2);});
    p.setOnReady(() -> {System.out.println("READY duration=" + p.getTotalDuration());p.dispose();System.exit(0);});
   } catch(Throwable e) {e.printStackTrace();System.exit(1);}
  });
 }
}
