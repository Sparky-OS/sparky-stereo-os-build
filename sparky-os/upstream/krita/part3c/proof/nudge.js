var ws = workspace.windowList();
print("nudge: windows " + ws.length);
for (var i = 0; i < ws.length; i++) {
    var w = ws[i];
    print("nudge: window " + w.caption + " normal=" + w.normalWindow + " max=" + w.maximizeMode);
    if (w.normalWindow) {
        if (w.maximizeMode === 3) { w.setMaximize(false, false); } else { w.setMaximize(true, true); }
    }
}
