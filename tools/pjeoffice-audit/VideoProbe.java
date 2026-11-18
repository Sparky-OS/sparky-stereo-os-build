// SPDX-License-Identifier: GPL-3.0-or-later
import com.github.videohandler4j.imp.*;
import com.github.videohandler4j.IVideoFile;
import com.github.filehandler4j.IInputDescriptor;
import java.io.File;
import java.nio.file.Paths;
public class VideoProbe {
 public static void main(String[] args) throws Exception {
  System.out.println("ffmpeg=" + VideoTools.FFMPEG.fullPath());
  IVideoFile file=VideoTools.FFMPEG.create(new File(args[0]));
  System.out.println("duration="+file.getDuration());
  VideoDescriptor.Builder b=new VideoDescriptor.Builder(".mp4");
  b.add(file); b.output(Paths.get(args[1]));
  IInputDescriptor d=b.build();
  new BySliceVideoSplitter(new DefaultVideoSlice(1000,4000)).apply(d).blockingSubscribe(e->System.out.println(e), e->{e.printStackTrace();System.exit(2);});
 }
}
