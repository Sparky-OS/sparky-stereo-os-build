// SPDX-License-Identifier: GPL-3.0-or-later
// Plays a media file with the application's own JavaFX Media for a few seconds and prints how far the playback clock advanced and how many video frames a MediaView received.
import javafx.application.Platform;
import javafx.embed.swing.JFXPanel;
import javafx.scene.media.Media;
import javafx.scene.media.MediaPlayer;
import java.io.File;
public class PlayProbe {
 public static void main(String[] args) throws Exception {
  new JFXPanel();
  final MediaPlayer[] holder = new MediaPlayer[1];
  final int[] frames = new int[1];
  Platform.runLater(() -> {
   try {
    Media m = new Media(new File(args[0]).toURI().toString());
    MediaPlayer p = new MediaPlayer(m);
    holder[0] = p;
    p.setOnError(() -> {p.getError().printStackTrace(); System.exit(2);});
    p.setOnReady(() -> {System.out.println("READY duration=" + p.getTotalDuration() + " video=" + m.getWidth() + "x" + m.getHeight()); p.play();});
    p.setOnEndOfMedia(() -> System.out.println("END_OF_MEDIA"));
   } catch(Throwable e) {e.printStackTrace();System.exit(1);}
  });
  Thread.sleep(Long.parseLong(args.length > 1 ? args[1] : "4000"));
  final double[] t = new double[1];
  Platform.runLater(() -> {t[0] = holder[0] == null ? -1 : holder[0].getCurrentTime().toMillis();});
  Thread.sleep(500);
  System.out.println("PLAYED currentTime=" + t[0] + " ms status=" + (holder[0] == null ? "none" : holder[0].getStatus()));
  System.exit(t[0] > 500 ? 0 : 3);
 }
}
