#!/usr/bin/python3 -I
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""lab.py [--matrix FILE] [--list] [--only ROW]... [--kind screens|audio|input|weak] [--evidence DIR] [--tree DIR]

The system test lab (ORDER 22): one command runs the matrix and writes one report.

Every row of the matrix proves one thing twice, in throwaway containers or guests:
  ours  the edition's components: the check must hold (exit 0), "green";
  stock the stock components (Debian's, upstream's): the same check must not hold (exit 1), "red".
The green side runs first. The red side runs only after a green one (a red control means nothing next to a green that
never ran). A row is
  PASS     ours held and stock did not;
  FAIL     ours did not hold, or stock held where it must be red, or a side ended in an error (exit not 0, 1 or 77);
  SKIPPED  a side could not run (a need is missing, or the check exited 77, or the row is a named skip); the reason is
           printed and written to the report, and a SKIPPED row is never PASS.
The exit status is 1 when any row is FAIL, 2 for a bad matrix or usage, else 0 (--strict also gives 3 for a SKIPPED row
that is not a named skip).

A side's check is an argument list run in a container of the row's image (docker run --name lab22-ROW-SIDE
--pull=never --ulimit core=0 --network none ...). It is removed by its literal name. DOCKER_HOST must be set: the lab never
talks to the default Docker. A check's own exit status says what it saw: 0 holds, 1 does not hold, 77 cannot run (its last
stdout line "SKIP: reason" says why). /evidence in the container is the side's own folder, kept in the report.
A time is reported, never a pass condition.

The matrix is JSON, see matrix.json and the contributor page (docs/guides/system-test-lab.en.md)."""
import argparse
import datetime
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time

KINDS = ("screens", "audio", "input", "weak")
SIDES = ("ours", "stock")
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,48}$")
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_TREE = "/var/tmp/sparky-repo-current"


class MatrixError(Exception):
    pass


def load_matrix(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError) as e:
        raise MatrixError("%s: %s" % (path, e))
    rows = data.get("rows") if isinstance(data, dict) else None
    if not isinstance(rows, list) or not rows:
        raise MatrixError("%s: no rows" % path)
    seen = {}
    for r in rows:
        if not isinstance(r, dict) or not ID_RE.match(str(r.get("id", ""))):
            raise MatrixError("a row has no valid id (a-z, 0-9, dash): %r" % (r.get("id") if isinstance(r, dict) else r))
        if r["id"] in seen:
            raise MatrixError("row id twice: " + r["id"])
        seen[r["id"]] = r
        if r.get("kind") not in KINDS:
            raise MatrixError("%s: kind must be one of %s" % (r["id"], "/".join(KINDS)))
    out = []
    for r in rows:
        out.append(resolve(r, seen))
    return data, out


def resolve(row, byid):
    """A row with "base" takes the base row's sides, image and needs; its own keys win (the weak rows)."""
    row = dict(row)
    if "base" in row:
        b = byid.get(row["base"])
        if b is None:
            raise MatrixError("%s: base %s is not a row" % (row["id"], row["base"]))
        if "base" in b:
            raise MatrixError("%s: base %s has a base itself" % (row["id"], row["base"]))
        merged = dict(b)
        merged.update({k: v for k, v in row.items() if k != "base"})
        merged["base"] = row["base"]
        row = merged
    if "skip" not in row:
        for s in SIDES:
            side = row.get("sides", {}).get(s)
            if not isinstance(side, dict) or not isinstance(side.get("cmd"), list) or not side["cmd"]:
                raise MatrixError("%s: side %s needs a cmd list" % (row["id"], s))
        for key in ("ours", "stock"):
            exp = row.get("expect", {}).get(key, "pass" if key == "ours" else "fail")
            if exp not in ("pass", "fail"):
                raise MatrixError("%s: expect %s must be pass or fail" % (row["id"], key))
    return row


def subst(obj, vars_):
    """{name} in any string of a row becomes the value of --var name=value, {lab}, {tree} or {evidence}; an unknown name stays
    as it is and the need that mentions it is then reported as unmet."""
    if isinstance(obj, str):
        return re.sub(r"\{([a-z][a-z0-9_]*)\}", lambda m: vars_.get(m.group(1), m.group(0)), obj)
    if isinstance(obj, list):
        return [subst(x, vars_) for x in obj]
    if isinstance(obj, dict):
        return {k: subst(v, vars_) for k, v in obj.items()}
    return obj


def expected(row, side):
    return row.get("expect", {}).get(side, "pass" if side == "ours" else "fail")


class Lab:
    def __init__(self, evidence, tree, docker_bin="docker", allow_local=False, prefix="lab22", log=None):
        self.evidence = os.path.abspath(evidence)
        self.tree = tree
        self.docker = docker_bin
        self.allow_local = allow_local
        self.prefix = prefix
        self.log = log or (lambda m: print(m, file=sys.stderr, flush=True))
        self.calls = []

    # ---- needs ----
    def check_needs(self, row, side):
        """Returns a reason when a need of the row is not met, else None."""
        needs = list(row.get("needs", [])) + list(row.get("sides", {}).get(side, {}).get("needs", []))
        runner = row.get("runner", "docker")
        for n in needs:
            kind, _, arg = n.partition(":")
            if kind == "docker":
                if runner == "docker" and not os.environ.get("DOCKER_HOST"):
                    return "DOCKER_HOST is not set (the lab never uses the default Docker)"
                if runner == "docker" and shutil.which(self.docker) is None:
                    return "no docker program"
            elif kind == "image":
                if runner == "docker":
                    p = subprocess.run([self.docker, "image", "inspect", arg], capture_output=True, text=True)
                    if p.returncode != 0:
                        return "image %s is not built (%s)" % (arg, row.get("build", "see rig/README.md"))
            elif kind == "path":
                if not os.path.exists(arg):
                    return "path %s does not exist" % arg
            elif kind == "kvm":
                if not (os.access("/dev/kvm", os.R_OK | os.W_OK)):
                    return "/dev/kvm is not usable by this user"
            else:
                return "unknown need %r" % n
        if runner == "docker" and not os.environ.get("DOCKER_HOST"):
            return "DOCKER_HOST is not set (the lab never uses the default Docker)"
        if runner == "local" and not self.allow_local:
            return "a host program: the lab runs programs only in containers (--allow-local is for its own tests)"
        return None

    # ---- running ----
    def container_name(self, row, side, tag=""):
        return "%s-%s-%s%s" % (self.prefix, row["id"], side, tag)

    def docker_argv(self, row, side, outdir, name, cmd=None):
        s = row["sides"][side]
        lim = row.get("limits", {})
        a = [self.docker, "run", "--name", name, "--pull=never", "--ulimit", "core=0"]
        a += ["--network", row.get("network", "none")]
        if lim.get("cpus"):
            a += ["--cpus", str(lim["cpus"])]
        if lim.get("memory"):
            a += ["--memory", str(lim["memory"])]
            a += ["--memory-swap", str(lim["memory"])]
        user = row.get("user")
        if user == "host":
            user = "%d:%d" % (os.getuid(), os.getgid())
        if user:
            a += ["--user", user]
        for d in row.get("devices", []):
            a += ["--device", d]
            try:
                a += ["--group-add", str(os.stat(d).st_gid)]
            except OSError:
                pass
        a += ["--mount", "type=bind,src=%s,dst=/evidence" % outdir]
        for m in row.get("mounts", []) + s.get("mounts", []):
            src, dst = m[0], m[1]
            ro = len(m) < 3 or m[2] != "rw"
            a += ["--mount", "type=bind,src=%s,dst=%s%s" % (src, dst, ",readonly" if ro else "")]
        env = dict(row.get("env", {}))
        env.update(s.get("env", {}))
        env["LAB_SIDE"] = side
        env["LAB_ROW"] = row["id"]
        if lim.get("cpus"):
            env["LAB_CPUS"] = str(lim["cpus"])
        if lim.get("memory"):
            env["LAB_MEMORY"] = str(lim["memory"])
        for k in sorted(env):
            a += ["-e", "%s=%s" % (k, env[k])]
        a += [s.get("image", row.get("image"))]
        a += list(cmd if cmd is not None else s["cmd"])
        return a

    def _rm(self, name):
        subprocess.run([self.docker, "rm", "-f", name], capture_output=True, text=True)

    def run_side(self, row, side):
        """Runs one side. Returns a dict: outcome (holds|absent|skip|error), exit, seconds, reason, evidence."""
        outdir = os.path.join(self.evidence, row["id"], side)
        shutil.rmtree(outdir, ignore_errors=True)
        os.makedirs(outdir)
        os.chmod(outdir, 0o777)
        res = {"expected": expected(row, side), "evidence": os.path.relpath(outdir, self.evidence)}
        reason = self.check_needs(row, side)
        if reason:
            res.update(outcome="skip", exit=None, seconds=0.0, reason=reason)
            return res
        runner = row.get("runner", "docker")
        timeout = row.get("timeout", 1800)
        t0 = time.monotonic()
        name = self.container_name(row, side)
        if runner == "docker":
            self._rm(name)
            argv = self.docker_argv(row, side, outdir, name)
            vers = row.get("sides", {}).get(side, {}).get("versions")
            if vers:
                vname = self.container_name(row, side, "-v")
                self._rm(vname)
                va = self.docker_argv(row, side, outdir, vname, cmd=vers)
                p = subprocess.run(va, capture_output=True, text=True)
                with open(os.path.join(outdir, "versions.txt"), "w") as f:
                    f.write(p.stdout + p.stderr)
                self._rm(vname)
        else:
            argv = list(row["sides"][side]["cmd"])
        self.calls.append(argv)
        try:
            p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                               env=dict(os.environ, LAB_EVIDENCE=outdir, LAB_SIDE=side, LAB_ROW=row["id"]))
            code, out, err = p.returncode, p.stdout, p.stderr
        except subprocess.TimeoutExpired as e:
            code, out, err = None, (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"
            if runner == "docker":
                subprocess.run([self.docker, "kill", name], capture_output=True, text=True)
        finally:
            if runner == "docker":
                self._rm(name)
        res["seconds"] = round(time.monotonic() - t0, 2)
        res["exit"] = code
        with open(os.path.join(outdir, "stdout.log"), "w") as f:
            f.write(out)
        with open(os.path.join(outdir, "stderr.log"), "w") as f:
            f.write(err)
        last = ""
        for line in out.splitlines():
            if line.startswith("SKIP:"):
                last = line[5:].strip()
        if code == 0:
            res["outcome"] = "holds"
        elif code == 1:
            res["outcome"] = "absent"
        elif code == 77:
            res.update(outcome="skip", reason=last or "the check cannot run here (exit 77, no reason given)")
        else:
            res.update(outcome="error", reason="the check ended with %s (not 0, 1 or 77)%s" % (
                "a timeout" if code is None else "exit %s" % code, ("; " + err.strip().splitlines()[-1]) if err.strip() else ""))
        return res

    def run_row(self, row):
        r = {"id": row["id"], "kind": row["kind"], "title": row.get("title", ""), "sides": {}}
        for k in ("limits", "tracks", "proves", "not_proven"):
            if k in row:
                r[k] = row[k]
        if "skip" in row:
            r.update(verdict="SKIPPED", reason=row["skip"], named=True)
            return r
        t0 = time.monotonic()
        ours = self.run_side(row, "ours")
        r["sides"]["ours"] = ours
        if ours["outcome"] == "skip":
            r.update(verdict="SKIPPED", reason="ours: " + ours["reason"], named=False)
            r["sides"]["stock"] = {"outcome": "not run", "expected": expected(row, "stock"), "reason": "ours did not run"}
        elif ours["outcome"] == "error":
            r.update(verdict="FAIL", reason="ours: " + ours["reason"])
            r["sides"]["stock"] = {"outcome": "not run", "expected": expected(row, "stock"), "reason": "ours ended in an error"}
        else:
            ok = (ours["outcome"] == "holds") == (ours["expected"] == "pass")
            if not ok:
                r.update(verdict="FAIL", reason="ours: expected to %s, it %s" % (
                    "hold" if ours["expected"] == "pass" else "be absent", ours["outcome"]))
                r["sides"]["stock"] = {"outcome": "not run", "expected": expected(row, "stock"),
                                       "reason": "ours did not match, so the red control means nothing"}
            else:
                stock = self.run_side(row, "stock")
                r["sides"]["stock"] = stock
                if stock["outcome"] == "skip":
                    r.update(verdict="SKIPPED", reason="stock: " + stock["reason"], named=False)
                elif stock["outcome"] == "error":
                    r.update(verdict="FAIL", reason="stock: " + stock["reason"])
                else:
                    sok = (stock["outcome"] == "holds") == (stock["expected"] == "pass")
                    if sok:
                        r.update(verdict="PASS", reason="")
                    elif stock["expected"] == "fail":
                        r.update(verdict="FAIL", reason="stock holds where the row must be red on stock (the check proves nothing)")
                    else:
                        r.update(verdict="FAIL", reason="stock did not hold where it should")
        r["seconds"] = round(time.monotonic() - t0, 2)
        return r


def tree_info(tree):
    info = {"path": tree}
    try:
        real = os.path.realpath(tree)
        info["resolved"] = real
        with open(os.path.join(real, "dists", "mashtabba", "Release"), encoding="utf-8") as f:
            for line in f:
                if line.startswith(("Date:", "Suite:", "Codename:")):
                    k, _, v = line.partition(":")
                    info[k.lower()] = v.strip()
    except OSError as e:
        info["error"] = str(e)
    return info


def select(rows, only, kind):
    out = []
    for r in rows:
        if only and r["id"] not in only:
            continue
        if kind and r["kind"] != kind:
            continue
        out.append(r)
    return out


def write_report(evidence, rows, tree, matrix_path, started, finished, extra):
    counts = {"PASS": 0, "FAIL": 0, "SKIPPED": 0}
    for r in rows:
        counts[r["verdict"]] += 1
    doc = {"lab": "ORDER 22", "matrix": matrix_path, "tree": tree, "started": started, "finished": finished,
           "summary": counts, "rows": rows}
    doc.update(extra)
    with open(os.path.join(evidence, "report.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    lines = ["# System test lab report", "",
             "Tree: `%s` (%s)" % (tree.get("resolved", tree.get("path")), tree.get("date", "no Release date read")),
             "Run: %s to %s" % (started, finished),
             "Rows: %d PASS, %d FAIL, %d SKIPPED" % (counts["PASS"], counts["FAIL"], counts["SKIPPED"]), "",
             "| Row | Kind | Verdict | Ours | Stock | Seconds | Why |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        def cell(s):
            d = r["sides"].get(s)
            if not d:
                return "-"
            return "%s (expected %s)" % (d["outcome"], d["expected"]) if "expected" in d else d["outcome"]
        why = r.get("reason", "")
        if r.get("named"):
            why = "named skip" + (" (%s)" % r["tracks"] if r.get("tracks") else "") + ": " + why
        lines.append("| %s | %s | **%s** | %s | %s | %s | %s |" % (
            r["id"], r["kind"], r["verdict"], cell("ours"), cell("stock"), r.get("seconds", ""), why.replace("|", "/")))
    lines += ["", "A PASS means the check held on ours and did not hold on stock. A time is reported, never a pass condition.", ""]
    with open(os.path.join(evidence, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    return counts


def main(argv=None):
    ap = argparse.ArgumentParser(description="the system test lab (ORDER 22)")
    ap.add_argument("--matrix", default=os.path.join(HERE, "matrix.json"))
    ap.add_argument("--list", action="store_true", help="list the rows and what each needs")
    ap.add_argument("--only", action="append", default=[], metavar="ROW")
    ap.add_argument("--kind", choices=KINDS)
    ap.add_argument("--evidence", default=os.path.join(os.getcwd(), "lab-evidence"))
    ap.add_argument("--tree", default=DEFAULT_TREE, help="the published tree the run is against (read only)")
    ap.add_argument("--docker", default=os.environ.get("LAB_DOCKER", "docker"))
    ap.add_argument("--allow-local", action="store_true", help="rows with runner local (the lab's own tests only)")
    ap.add_argument("--var", action="append", default=[], metavar="NAME=VALUE",
                    help="a value for {name} in the matrix (for example skills=/path/to/sparky-stereo-os)")
    ap.add_argument("--strict", action="store_true", help="exit 3 when a row is SKIPPED without being a named skip")
    a = ap.parse_args(argv)
    try:
        data, rows = load_matrix(a.matrix)
    except MatrixError as e:
        print("lab: %s" % e, file=sys.stderr)
        return 2
    vars_ = {"lab": HERE, "tree": os.path.realpath(a.tree)}
    for v in a.var:
        k, _, val = v.partition("=")
        if not k or not _:
            print("lab: --var wants NAME=VALUE", file=sys.stderr)
            return 2
        vars_[k] = val
    rows = [subst(r, vars_) for r in rows]
    ids = {r["id"] for r in rows}
    for o in a.only:
        if o not in ids:
            print("lab: no row %s (see --list)" % o, file=sys.stderr)
            return 2
    sel = select(rows, a.only, a.kind)
    lab = Lab(a.evidence, a.tree, a.docker, a.allow_local, data.get("prefix", "lab22"))
    if a.list:
        for r in sel:
            note = "SKIP: " + r["skip"] if "skip" in r else ""
            if not note:
                for s in SIDES:
                    n = lab.check_needs(r, s)
                    if n:
                        note = "would be SKIPPED: " + n
                        break
            print("%-28s %-8s %s%s" % (r["id"], r["kind"], r.get("title", ""), ("   [%s]" % note) if note else ""))
        return 0
    if not sel:
        print("lab: nothing selected", file=sys.stderr)
        return 2
    os.makedirs(a.evidence, exist_ok=True)
    started = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    done = []
    for r in sel:
        lab.log("== %s (%s)" % (r["id"], r["kind"]))
        res = lab.run_row(r)
        lab.log("   %s %s" % (res["verdict"], res.get("reason", "")))
        done.append(res)
    finished = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    counts = write_report(a.evidence, done, tree_info(a.tree), os.path.abspath(a.matrix), started, finished, {})
    print(open(os.path.join(a.evidence, "report.md"), encoding="utf-8").read())
    if counts["FAIL"]:
        return 1
    if a.strict and any(r["verdict"] == "SKIPPED" and not r.get("named") for r in done):
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
