#!/usr/bin/python3 -I
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""The lab's own tests (ORDER 22): a planted failing row turns the run red; a row green on stock where red is expected
turns it red; a row that cannot run is SKIPPED and named, never PASS. Run: python3 -I tests/test_lab.py

Rows with runner "local" run a shell line on the host and are allowed only by --allow-local, which only these tests use.
The Docker path is tested against a fake docker program that records its argument lists and answers from a table."""
import importlib.util
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LAB = os.path.join(os.path.dirname(HERE), "lab.py")
spec = importlib.util.spec_from_file_location("lab", LAB)
lab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lab)


def row(rid, ours, stock, kind="screens", **kw):
    r = {"id": rid, "kind": kind, "title": rid, "runner": "local",
         "sides": {"ours": {"cmd": ["sh", "-c", ours]}, "stock": {"cmd": ["sh", "-c", stock]}}}
    r.update(kw)
    return r


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lab-test-", dir=os.environ.get("LAB_TEST_TMP"))
        self.ev = os.path.join(self.tmp, "ev")
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def run_lab(self, rows, *args, env=None):
        m = os.path.join(self.tmp, "m.json")
        with open(m, "w") as f:
            json.dump({"rows": rows}, f)
        tree = os.path.join(self.tmp, "tree")
        os.makedirs(os.path.join(tree, "dists", "mashtabba"), exist_ok=True)
        with open(os.path.join(tree, "dists", "mashtabba", "Release"), "w") as f:
            f.write("Suite: testing\nDate: Tue, 17 Nov 2026 18:28:18 UTC\n")
        old = dict(os.environ)
        os.environ.update(env or {})
        out, err = io.StringIO(), io.StringIO()
        so, se = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            code = lab.main(["--matrix", m, "--evidence", self.ev, "--tree", tree, "--allow-local"] + list(args))
        finally:
            sys.stdout, sys.stderr = so, se
            os.environ.clear()
            os.environ.update(old)
        rep = None
        p = os.path.join(self.ev, "report.json")
        if os.path.exists(p):
            with open(p) as f:
                rep = json.load(f)
        return code, rep, out.getvalue(), err.getvalue()


class Verdicts(Base):
    def test_green_ours_red_stock_passes(self):
        code, rep, out, _ = self.run_lab([row("ok", "exit 0", "exit 1")])
        self.assertEqual(code, 0)
        self.assertEqual(rep["rows"][0]["verdict"], "PASS")
        self.assertIn("| ok | screens | **PASS**", out)

    def test_planted_failing_row_turns_the_run_red(self):
        code, rep, _, _ = self.run_lab([row("ok", "exit 0", "exit 1"), row("planted", "exit 1", "exit 1")])
        self.assertEqual(code, 1)
        v = {r["id"]: r for r in rep["rows"]}
        self.assertEqual(v["planted"]["verdict"], "FAIL")
        self.assertEqual(v["ok"]["verdict"], "PASS")
        self.assertEqual(rep["summary"]["FAIL"], 1)

    def test_stock_green_where_red_expected_turns_the_run_red(self):
        code, rep, _, _ = self.run_lab([row("proves-nothing", "exit 0", "exit 0")])
        self.assertEqual(code, 1)
        r = rep["rows"][0]
        self.assertEqual(r["verdict"], "FAIL")
        self.assertIn("stock holds", r["reason"])

    def test_red_run_is_after_the_green_one_and_only_after_it(self):
        log = os.path.join(self.tmp, "order.log")
        r1 = row("order", "echo ours >> %s; exit 0" % log, "echo stock >> %s; exit 1" % log)
        self.run_lab([r1])
        self.assertEqual(open(log).read().split(), ["ours", "stock"])
        os.remove(log)
        r2 = row("order", "echo ours >> %s; exit 1" % log, "echo stock >> %s; exit 1" % log)
        code, rep, _, _ = self.run_lab([r2])
        self.assertEqual(open(log).read().split(), ["ours"])
        self.assertEqual(rep["rows"][0]["sides"]["stock"]["outcome"], "not run")
        self.assertEqual(code, 1)

    def test_a_row_that_cannot_run_is_skipped_and_named_never_pass(self):
        r = row("cant", "echo 'SKIP: needs a guest kernel'; exit 77", "exit 1")
        code, rep, out, _ = self.run_lab([r])
        self.assertEqual(code, 0)
        x = rep["rows"][0]
        self.assertEqual(x["verdict"], "SKIPPED")
        self.assertIn("needs a guest kernel", x["reason"])
        self.assertNotIn("**PASS**", out)
        self.assertEqual(rep["summary"]["PASS"], 0)

    def test_a_missing_need_is_skipped_with_the_need(self):
        r = row("needy", "exit 0", "exit 1", needs=["path:/nonexistent/lab22"])
        code, rep, _, _ = self.run_lab([r])
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertIn("/nonexistent/lab22", rep["rows"][0]["reason"])

    def test_skipped_stock_side_is_skipped_not_pass(self):
        r = row("half", "exit 0", "echo 'SKIP: no stock image'; exit 77")
        code, rep, _, _ = self.run_lab([r])
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertEqual(rep["summary"]["PASS"], 0)

    def test_named_skip_rows_are_listed_with_their_order(self):
        r = {"id": "binaural", "kind": "audio", "title": "ORDER 21", "skip": "the binaural check belongs to ORDER 21", "tracks": "ORDER 21"}
        code, rep, out, _ = self.run_lab([r])
        self.assertEqual(code, 0)
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertTrue(rep["rows"][0]["named"])
        self.assertIn("named skip (ORDER 21)", out)

    def test_strict_fails_an_unnamed_skip_only(self):
        r = row("cant", "echo 'SKIP: x'; exit 77", "exit 1")
        self.assertEqual(self.run_lab([r], "--strict")[0], 3)
        n = {"id": "nm", "kind": "audio", "skip": "ORDER 23", "tracks": "ORDER 23"}
        self.assertEqual(self.run_lab([n], "--strict")[0], 0)

    def test_an_error_exit_is_a_fail_not_a_red(self):
        code, rep, _, _ = self.run_lab([row("boom", "exit 2", "exit 1")])
        self.assertEqual(code, 1)
        self.assertEqual(rep["rows"][0]["verdict"], "FAIL")
        self.assertEqual(rep["rows"][0]["sides"]["ours"]["outcome"], "error")

    def test_a_time_is_reported_never_a_condition(self):
        code, rep, _, _ = self.run_lab([row("slow", "sleep 1; exit 0", "exit 1")])
        self.assertEqual(code, 0)
        self.assertGreaterEqual(rep["rows"][0]["sides"]["ours"]["seconds"], 1.0)
        self.assertEqual(rep["rows"][0]["verdict"], "PASS")

    def test_expect_can_invert_a_control_row(self):
        r = row("control", "exit 0", "exit 0", expect={"ours": "pass", "stock": "pass"})
        self.assertEqual(self.run_lab([r])[0], 0)

    def test_report_names_the_tree(self):
        _, rep, out, _ = self.run_lab([row("ok", "exit 0", "exit 1")])
        self.assertIn("Tue, 17 Nov 2026", rep["tree"]["date"])
        self.assertIn("Tue, 17 Nov 2026", out)

    def test_evidence_folder_per_side(self):
        self.run_lab([row("ev", "echo hello; exit 0", "exit 1")])
        self.assertIn("hello", open(os.path.join(self.ev, "ev", "ours", "stdout.log")).read())
        self.assertTrue(os.path.isdir(os.path.join(self.ev, "ev", "stock")))


class Selection(Base):
    rows = None

    def mk(self):
        return [row("a1", "exit 0", "exit 1", kind="audio"), row("s1", "exit 0", "exit 1", kind="screens"),
                row("i1", "exit 0", "exit 1", kind="input")]

    def test_only(self):
        _, rep, _, _ = self.run_lab(self.mk(), "--only", "s1")
        self.assertEqual([r["id"] for r in rep["rows"]], ["s1"])

    def test_kind(self):
        _, rep, _, _ = self.run_lab(self.mk(), "--kind", "audio")
        self.assertEqual([r["id"] for r in rep["rows"]], ["a1"])

    def test_unknown_only_is_a_usage_error(self):
        self.assertEqual(self.run_lab(self.mk(), "--only", "nope")[0], 2)

    def test_list_runs_nothing(self):
        code, rep, out, _ = self.run_lab(self.mk(), "--list")
        self.assertEqual(code, 0)
        self.assertIsNone(rep)
        for i in ("a1", "s1", "i1"):
            self.assertIn(i, out)

    def test_bad_matrix_is_exit_2(self):
        bad = row("Bad Id", "exit 0", "exit 1")
        self.assertEqual(self.run_lab([bad])[0], 2)
        d = [row("x", "exit 0", "exit 1"), row("x", "exit 0", "exit 1")]
        self.assertEqual(self.run_lab(d)[0], 2)
        k = row("y", "exit 0", "exit 1", kind="video")
        self.assertEqual(self.run_lab([k])[0], 2)

    def test_weak_row_takes_its_base_and_its_limits(self):
        rows = [row("base", "exit 0", "exit 1", kind="audio"),
                {"id": "base-weak", "kind": "weak", "base": "base", "limits": {"cpus": 2, "memory": "2g"}}]
        code, rep, _, _ = self.run_lab(rows)
        w = [r for r in rep["rows"] if r["id"] == "base-weak"][0]
        self.assertEqual(w["verdict"], "PASS")
        self.assertEqual(w["limits"], {"cpus": 2, "memory": "2g"})


class Substitution(Base):
    def test_var_names_fill_mounts_and_needs(self):
        r = row("sub", "exit 0", "exit 1", needs=["path:{work}/there"])
        os.makedirs(os.path.join(self.tmp, "there"))
        code, rep, _, _ = self.run_lab([r], "--var", "work=" + self.tmp)
        self.assertEqual(rep["rows"][0]["verdict"], "PASS")

    def test_unset_var_is_reported_as_the_unmet_path(self):
        r = row("sub", "exit 0", "exit 1", needs=["path:{work}/there"])
        code, rep, _, _ = self.run_lab([r])
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertIn("{work}", rep["rows"][0]["reason"])

    def test_bad_var_is_a_usage_error(self):
        self.assertEqual(self.run_lab([row("a", "exit 0", "exit 1")], "--var", "oops")[0], 2)


FAKE_DOCKER = r'''#!/usr/bin/python3 -I
import json, os, sys
log = os.environ["FAKE_LOG"]
with open(log, "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\n")
a = sys.argv[1:]
table = json.load(open(os.environ["FAKE_TABLE"]))
if a[:2] == ["image", "inspect"]:
    sys.exit(0 if a[2] in table.get("images", []) else 1)
if a[0] == "run":
    name = a[a.index("--name") + 1]
    print(table.get("stdout", {}).get(name, ""))
    sys.exit(table.get("exit", {}).get(name, 0))
sys.exit(0)
'''


class DockerPath(Base):
    def setUp(self):
        super().setUp()
        self.fake = os.path.join(self.tmp, "docker")
        with open(self.fake, "w") as f:
            f.write(FAKE_DOCKER)
        os.chmod(self.fake, 0o755)
        self.log = os.path.join(self.tmp, "calls.log")
        self.table = os.path.join(self.tmp, "table.json")

    def go(self, rows, table, host="unix:///x/docker.sock"):
        with open(self.table, "w") as f:
            json.dump(table, f)
        env = {"FAKE_LOG": self.log, "FAKE_TABLE": self.table}
        if host:
            env["DOCKER_HOST"] = host
        else:
            os.environ.pop("DOCKER_HOST", None)
        return self.run_lab(rows, "--docker", self.fake, env=env)

    def drow(self, **kw):
        r = {"id": "dock", "kind": "audio", "title": "d", "image": "lab22-rig:1", "needs": ["docker", "image:lab22-rig:1"],
             "mounts": [["/etc/hostname", "/in/hostname"]], "limits": {"cpus": 2, "memory": "2g"},
             "sides": {"ours": {"cmd": ["check", "--ours"]}, "stock": {"cmd": ["check", "--stock"]}}}
        r.update(kw)
        return r

    def calls(self):
        return [json.loads(l) for l in open(self.log)]

    def test_container_flags_names_and_literal_removal(self):
        code, rep, _, _ = self.go([self.drow()], {"images": ["lab22-rig:1"], "exit": {"lab22-dock-stock": 1}})
        self.assertEqual(code, 0, rep)
        runs = [c for c in self.calls() if c[0] == "run"]
        self.assertEqual([c[c.index("--name") + 1] for c in runs], ["lab22-dock-ours", "lab22-dock-stock"])
        for c in runs:
            self.assertIn("--pull=never", c)
            self.assertEqual(c[c.index("--ulimit") + 1], "core=0")
            self.assertEqual(c[c.index("--network") + 1], "none")
            self.assertEqual(c[c.index("--cpus") + 1], "2")
            self.assertEqual(c[c.index("--memory") + 1], "2g")
            self.assertTrue(any(x.startswith("type=bind,src=/etc/hostname,dst=/in/hostname,readonly") for x in c))
        rms = [c for c in self.calls() if c[0] == "rm"]
        self.assertIn(["rm", "-f", "lab22-dock-ours"], rms)
        self.assertIn(["rm", "-f", "lab22-dock-stock"], rms)
        banned = [c for c in self.calls() if "prune" in c or c[0] in ("pull", "ps", "stop")]
        self.assertEqual(banned, [])

    def test_no_docker_host_is_a_skip_never_the_default_docker(self):
        code, rep, _, _ = self.go([self.drow()], {"images": ["lab22-rig:1"]}, host=None)
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertIn("DOCKER_HOST", rep["rows"][0]["reason"])
        self.assertEqual([c for c in self.calls() if c[0] == "run"] if os.path.exists(self.log) else [], [])

    def test_missing_image_is_skipped_with_how_to_build(self):
        code, rep, _, _ = self.go([self.drow(build="rig/build.sh")], {"images": []})
        self.assertEqual(rep["rows"][0]["verdict"], "SKIPPED")
        self.assertIn("lab22-rig:1 is not built", rep["rows"][0]["reason"])

    def test_container_stock_green_fails_the_run(self):
        code, rep, _, _ = self.go([self.drow()], {"images": ["lab22-rig:1"], "exit": {}})
        self.assertEqual(code, 1)
        self.assertEqual(rep["rows"][0]["verdict"], "FAIL")

    def test_a_device_brings_its_group_and_the_host_user_is_named(self):
        r = self.drow(devices=["/dev/null"], user="host")
        self.go([r], {"images": ["lab22-rig:1"], "exit": {"lab22-dock-stock": 1}})
        run = [c for c in self.calls() if c[0] == "run"][0]
        self.assertEqual(run[run.index("--device") + 1], "/dev/null")
        self.assertIn("--group-add", run)
        self.assertEqual(run[run.index("--user") + 1], "%d:%d" % (os.getuid(), os.getgid()))

    def test_a_timeout_is_an_error_and_the_container_is_killed_by_name(self):
        r = self.drow(timeout=1)
        r["sides"]["ours"]["cmd"] = ["sleep"]
        with open(self.fake, "w") as f:
            f.write(FAKE_DOCKER.replace('print(table', 'import time; time.sleep(3) if "ours" in a[a.index("--name")+1] and a[0]=="run" else None; print(table'))
        code, rep, _, _ = self.go([r], {"images": ["lab22-rig:1"]})
        self.assertEqual(rep["rows"][0]["verdict"], "FAIL")
        self.assertIn(["kill", "lab22-dock-ours"], self.calls())

    def test_uses_a_different_image_per_side(self):
        r = self.drow(needs=["docker"])
        r["sides"]["ours"]["image"] = "lab22-ours:1"
        r["sides"]["stock"]["image"] = "lab22-stock:1"
        self.go([r], {"images": [], "exit": {"lab22-dock-stock": 1}})
        runs = [c for c in self.calls() if c[0] == "run"]
        self.assertIn("lab22-ours:1", runs[0])
        self.assertIn("lab22-stock:1", runs[1])


class PreparedAgainst(Base):
    def test_the_report_says_which_tree_the_images_were_made_from(self):
        work = os.path.join(self.tmp, "work")
        os.makedirs(work)
        r = row("ok", "exit 0", "exit 1")
        with open(os.path.join(work, "tree.txt"), "w") as f:
            f.write("/x/tree (Tue, 17 Nov 2026 18:28:18 UTC)\n")
        _, rep, out, _ = self.run_lab([r], "--var", "work=" + work)
        self.assertIn("Images and roots prepared against: /x/tree (Tue, 17 Nov 2026 18:28:18 UTC)", out)
        self.assertNotIn("NOT the tree of this run", out)
        self.assertEqual(rep["images_prepared_against"], "/x/tree (Tue, 17 Nov 2026 18:28:18 UTC)")
        with open(os.path.join(work, "tree.txt"), "w") as f:
            f.write("/x/older (Fri, 06 Nov 2026 10:00:00 UTC)\n")
        _, _, out, _ = self.run_lab([r], "--var", "work=" + work)
        self.assertIn("NOT the tree of this run", out)

    def test_no_work_folder_no_line(self):
        _, rep, out, _ = self.run_lab([row("ok", "exit 0", "exit 1")])
        self.assertNotIn("prepared against", out)
        self.assertNotIn("images_prepared_against", rep)


class ShippedMatrix(unittest.TestCase):
    """The matrix this folder ships: every row is well formed, red on stock is the default for every runnable row, every named
    skip says whose it is, and the screens rows ask the guest only for phases, layouts and tags the guest scripts know."""
    PHASES = {"kwin": {"fp", "tab", "sbs-half", "sbs-full", "2d", "edid-no-3d", "no-3d-modes"},
              "deep": {"2d", "sbs-half"},
              "eyeorder": {"hdmi-sbs-half", "hdmi-tab", "hdmi-sbs-full", "hdmi-fp", "twin-sbs-half", "twin-tab", "anaglyph-modern",
                           "anaglyph-crt", "rows-left", "rows-right", "columns-left", "columns-right", "checkerboard-left",
                           "checkerboard-right", "fs-left", "fs-right"},
              "anaglyph": {"doctor", "file", "filemode", "plain"}}
    EDIDS = {"stereo-test", "stereo-test-2d", "stereo-eyeorder"}

    def setUp(self):
        self.data, self.rows = lab.load_matrix(os.path.join(os.path.dirname(HERE), "matrix.json"))

    def test_every_runnable_row_is_red_on_stock_and_green_on_ours(self):
        for r in self.rows:
            if "skip" in r:
                continue
            self.assertEqual(lab.expected(r, "stock"), "fail", r["id"] + ": a row that is green on stock proves nothing")
            if r["id"] != "audio-detect-headphones":
                self.assertEqual(lab.expected(r, "ours"), "pass", r["id"])

    def test_a_named_skip_says_whose_it_is_and_why(self):
        for r in self.rows:
            if "skip" in r:
                self.assertTrue(r.get("tracks"), r["id"] + " is a skip without a name")
                self.assertGreater(len(r["skip"]), 30, r["id"])

    def test_the_screens_guest_rows_ask_for_what_the_guest_knows(self):
        for r in self.rows:
            if r.get("kind") not in ("screens", "weak") or "skip" in r:
                continue
            cmd = r["sides"]["ours"]["cmd"]
            if "screens_guest.sh" not in " ".join(cmd):
                continue
            env = r.get("env", {})
            phase = env.get("LAB_PHASE", "kwin")
            self.assertIn(phase, self.PHASES, r["id"])
            self.assertIn(env.get("LAB_EDID", "stereo-test"), self.EDIDS, r["id"])
            args = cmd[cmd.index("ours") + 1:]
            self.assertTrue(args, r["id"])
            self.assertLessEqual(set(args), self.PHASES[phase], r["id"])
            self.assertEqual(cmd[cmd.index("ours")], "ours")
            self.assertEqual(r["sides"]["stock"]["cmd"][:3], cmd[:2] + ["stock"], r["id"])
            self.assertEqual(r["sides"]["stock"]["cmd"][3:], args, r["id"])

    def test_the_guest_scripts_named_by_the_phases_exist(self):
        base = os.path.dirname(HERE)
        for f in ("rows/screens_guest.sh", "rows/deep_judge.py", "rows/eyeorder_judge.py", "rows/anaglyph_judge.py",
                  "rows/page_judge.py", "rows/page_row.sh", "rows/page-steps.json", "rig/guest/deep-steps.sh",
                  "rig/guest/eyeorder-steps.sh", "rig/guest/anaglyph-steps.sh", "rig/guest/make-eyeorder-edid.py", "rig/build-page.sh"):
            self.assertTrue(os.path.exists(os.path.join(base, f)), f)

    def test_the_rows_use_images_that_prepare_builds(self):
        built = {"lab22-guest:1", "lab22-audio-ours:1", "lab22-audio-stock:1", "lab22-kwin-ours:1", "lab22-kwin-stock:1",
                 "lab22-page-ours:1", "lab22-page-stock:1"}
        for r in self.rows:
            if "skip" in r:
                continue
            for n in r.get("needs", []):
                if n.startswith("image:"):
                    self.assertIn(n[6:], built, r["id"])
            for s in ("ours", "stock"):
                img = r["sides"][s].get("image", r.get("image"))
                self.assertIn(img, built, r["id"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
