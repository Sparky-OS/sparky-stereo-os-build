var ws = workspace.windowList();
for (var i = 0; i < ws.length; i++) { var w = ws[i];
  print("GEOM " + w.caption + " frame=" + w.frameGeometry.width + "x" + w.frameGeometry.height + " client=" + w.clientGeometry.width + "x" + w.clientGeometry.height + " buffer=" + w.bufferGeometry.width + "x" + w.bufferGeometry.height + " stereo=" + (w.stereoContent !== undefined ? w.stereoContent : "n/a"));
}
