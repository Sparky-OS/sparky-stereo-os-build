import json, sys
case = sys.argv[1]
W = lambda t: ['wait', t]; C = ['cap']
def caps(n, gap=0.13): return [x for _ in range(n) for x in (C, W(gap))]
if case == 'steady': st = [W(3.0)] + caps(16, 0.15)
elif case == 'seek': st = [W(3.0)] + caps(4) + [['ipc', ['seek', 2.0, 'absolute+exact']], W(0.25)] + caps(6) + [['ipc', ['seek', 5.5, 'absolute']], W(0.2)] + caps(6)
elif case == 'pause': st = [W(3.0)] + caps(3) + [['ipc', ['set_property', 'pause', True]], W(0.6)] + caps(3) + [['ipc', ['set_property', 'pause', False]], W(0.15)] + caps(8)
elif case == 'change': st = [W(3.0)] + caps(4) + [['ipc', ['playlist-next']], W(1.5)] + caps(5) + [['ipc', ['playlist-next']], W(1.5)] + caps(5)
elif case == 'layout': st = [W(3.0)] + caps(4) + [['ipc', ['playlist-next']], W(1.5)] + caps(6)
print(json.dumps(st))
