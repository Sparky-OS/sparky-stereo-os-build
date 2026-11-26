#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
"""The plan window in the person's language (ORDER 675, continuation 3): lib/detect.py's sentences and line kinds have
their messages in every language file, and plan_for_person (lib/actions.sh) shows them. Run in a container:
    plan-language.py PATH/TO/sparky-stereo-hardware-recipe
Checks: every sentence key of detect.py has a message number, and its English message is detect.py's English with %s
in place of {n}; every language has every number with as many %s as English; on every fixture the English window is
the plan itself without its "say" lines; the Brazilian Portuguese window holds none of detect.py's English sentences and
starts each line with a word of its own."""
import pathlib
import re
import subprocess
import sys

recipe = pathlib.Path(sys.argv[1]).resolve()
LANGS = ["en", "de", "es", "fr", "ja", "ko", "pl", "pt_BR", "zh_CN", "zh_TW"]
fails = 0


def check(name, ok, detail=""):
    global fails
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else f": {detail}"))
    fails += 0 if ok else 1


def lang(name):
    return dict(re.findall(r'^LOCAL(\d+)="(.*)"$', (recipe / "lang" / name).read_text(), re.M))


actions = (recipe / "lib/actions.sh").read_text()
say = dict(re.findall(r"\[([a-z0-9-]+)\]=(\d+)", re.search(r"PLAN_SAY=\((.*?)\)", actions, re.S).group(1)))
kinds = dict(re.findall(r"\[([a-z]+)\]=(\d+)", re.search(r"PLAN_KIND=\((.*?)\)", actions, re.S).group(1)))
source = (recipe / "lib/detect.py").read_text()
text = {}
exec(compile(re.search(r"^TEXT = \{.*?^\}", source, re.M | re.S).group(0), "detect.py TEXT", "exec"), {}, text)
text = text["TEXT"]
messages = {name: lang(name) for name in LANGS}

check("every sentence of detect.py has a message number", set(text) == set(say), sorted(set(text) ^ set(say)))
wrong = [k for k in text if messages["en"].get(say.get(k, "")) != re.sub(r"\{\d+\}", "%s", text[k])]
check("each English message is detect.py's English, %s in place of {n}", not wrong, wrong)
missing = [(name, n) for name in LANGS for n in [*say.values(), *kinds.values()] if n not in messages[name]]
check("every language has every message", not missing, missing[:10])
counts = [(name, n) for name in LANGS for n in say.values()
          if n in messages[name] and messages[name][n].count("%s") != messages["en"][n].count("%s")]
check("every message has as many %s as English", not counts, counts)


def window(plan, language):
    script = ('set -euo pipefail; source "$1/lib/actions.sh"; source "$1/lang/en"; source "$1/lang/$2"; '
              'plan_for_person "$3"')
    return subprocess.run(["bash", "-c", script, "_", str(recipe), language, plan], text=True, capture_output=True, check=True).stdout


# each English sentence whole, its arguments as wildcards (a brand at its start, "NVIDIA ", stays in every language)
english_sentences = [".+?".join(re.escape(part) for part in re.split(r"\{\d+\}", t)) for t in text.values()]
fixtures = sorted(d for d in (recipe / "tests/fixtures").iterdir() if (d / "laptop").exists())
work = pathlib.Path("/tmp/plan-language")
work.mkdir(exist_ok=True)
said = 0
for d in fixtures:
    plan = subprocess.run([sys.executable, "-I", str(recipe / "lib/detect.py"), str(d), str(recipe / "share")],
                          text=True, capture_output=True, check=True).stdout
    path = work / d.name
    path.write_text(plan)
    said += sum(1 for line in plan.splitlines() if line.startswith("say\t"))
    bare = "".join(line + "\n" for line in plan.splitlines() if not line.startswith("say\t"))
    check(f"{d.name}: the English window is the plan itself", window(str(path), "en") == bare)
    shown = window(str(path), "pt_BR")
    left = [s for s in english_sentences if re.search(s, shown)]
    check(f"{d.name}: no English sentence of the planner in the Portuguese window", not left, left)
    first = {line.split("\t")[0] for line in shown.splitlines()}
    check(f"{d.name}: every line starts with a Portuguese word", first <= set(lang("pt_BR")[n] for n in kinds.values()), first)
check("the fixtures give sentence keys to render", said > 0, said)
print("==", "ALL PASS" if fails == 0 else f"{fails} FAILED")
sys.exit(1 if fails else 0)
