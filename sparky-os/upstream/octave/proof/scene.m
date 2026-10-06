% stereo proof scene: markers nearer, at and farther than the camera target
mode = getenv ("OCT_STEREO");
args = {"position", [50 50 900 560], "color", "white", "menubar", "none", "toolbar", "none"};
late = strcmp (getenv ("OCT_LATE"), "1");
if (strcmp (mode, "on") && ! late)
  args = [args, {"stereo", "on"}];
endif
f = figure (1, args{:});
ax = axes ("position", [0.04 0.08 0.62 0.88], "color", "white");
hold (ax, "on");
h(1) = plot3 (ax, -1, -1.5,  1, "s", "markersize", 22, "markerfacecolor", [1 0 0], "markeredgecolor", [1 0 0]);
h(2) = plot3 (ax,  0,  0.0,  0, "s", "markersize", 22, "markerfacecolor", [0 0.7 0], "markeredgecolor", [0 0.7 0]);
h(3) = plot3 (ax,  1,  1.5, -1, "s", "markersize", 22, "markerfacecolor", [0 0 1], "markeredgecolor", [0 0 1]);
text (ax, -1, -1.5, -1, "near", "color", [1 0 1], "fontsize", 20);
text (ax,  0,  0.0, -1.5, "mid", "color", [0 0.8 0.8], "fontsize", 20);
text (ax,  1,  1.5,  1.5, "far", "color", [1 0.5 0], "fontsize", 20);
axis (ax, [-2 2 -2 2 -2 2]);
set (ax, "xcolor", [0.5 0.5 0.5], "ycolor", [0.5 0.5 0.5], "zcolor", [0.5 0.5 0.5], "cameratarget", [0 0 0]);
view (ax, [0 0]);
hl = legend (ax, h, {"one", "two", "three"});
set (hl, "position", [0.70 0.55 0.27 0.35]);
ax2 = axes ("position", [0.72 0.08 0.25 0.35], "color", "white");
plot (ax2, 0.5, 0.5, "d", "markersize", 18, "markerfacecolor", [1 0.9 0], "markeredgecolor", [1 0.9 0]);
text (ax2, 0.15, 0.85, "flat", "color", [1 0.9 0], "fontsize", 20);
axis (ax2, [0 1 0 1]);
drawnow ();
if (late && strcmp (mode, "on"))
  pause (1.5);
  set (f, "stereo", "on");
endif
pause (4);
refresh (f);
drawnow ();
pause (str2double (getenv ("OCT_HOLD")));
if (strcmp (getenv ("OCT_PRINT"), "1"))
  print (f, "-dpng", [getenv("OCT_OUT") "/print.png"]);
endif
disp ("scene-done");
