import json, sys
# steps: seek to frame f0 (25 fps), then n single frame steps with a capture after each (starting with one at the seek target)
f0, n = int(sys.argv[1]), int(sys.argv[2])
st = [['wait', 2.5], ['ipc', ['seek', f0 / 25.0, 'absolute+exact']], ['wait', 1.0], ['cap']]
for i in range(n): st += [['ipc', ['frame-step']], ['wait', 0.5], ['cap']]
print(json.dumps(st))
