#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Asks KRunner's missing program runner what KRunner asks it: org.kde.krunner1.Match on its bus name, which the session bus
# activates from /usr/share/dbus-1/services. Prints {query: [[id, text, relevance, subtext], ...]} as JSON.
import json, sys
import dbus

bus = dbus.SessionBus()
runner = dbus.Interface(bus.get_object('org.sparky.stereo.MissingProgram', '/runner'), 'org.kde.krunner1')
result = {}
for query in sys.argv[1:]:
    result[query] = [[str(m[0]), str(m[1]), float(m[4]), str(m[5].get('subtext', ''))]
                     for m in runner.Match(query, timeout=60)]
print(json.dumps(result, indent=1, ensure_ascii=False))
