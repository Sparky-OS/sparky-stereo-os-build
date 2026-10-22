#!/usr/bin/env python3
"""Run selected, inventoried native source migrations in isolated containers.

Candidates stay outside the repository. Failures are checkpoints for review.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg
from build_slots import start_build

notes = cfg.path('SPARKY_RUN_RECORD')
base = cfg.path('SPARKY_MIGRATION_WORK')
repo = cfg.path('SPARKY_REPO_DIR')
toolkit = (cfg.TREE / 'sparky-os')
inventory = json.loads((notes / "source-migration-inventory.json").read_text())["jobs"]
requested = sys.argv[1:]
if not requested:
    raise SystemExit("Specify source names from the audited inventory")
jobs = {job["source"]: job for job in inventory}
overrides = notes / "source-migration-overrides.json"
if overrides.exists():
    jobs.update(json.loads(overrides.read_text()))
unknown = set(requested) - set(jobs)
if unknown:
    raise SystemExit(f"Not in the source inventory: {sorted(unknown)}")

recipe = r"""#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
dpkg-source -x "$TASK_DSC" source
if [ -f /work/build-inputs.json ]; then
    # These are isolated, checksum-verified build inputs, not a published repo.
    printf 'deb [trusted=yes] file:/work/dependency-packages ./\n' > /etc/apt/sources.list.d/build-inputs.list
    python3 - <<'BUILD_INPUTS'
from pathlib import Path
import hashlib, json, re, subprocess
inputs = json.loads(Path('/work/build-inputs.json').read_text())
p = Path('/work/source/debian/control')
s = p.read_text()
for item in inputs:
    archive = Path('/work/dependency-packages') / item['archive']
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == item['sha256']
    pattern = r'\b' + re.escape(item['package']) + r'\s*\([^)]*\)'
    matches = re.findall(pattern, s)
    if not matches:
        plain = r'(?m)^(\s*)' + re.escape(item['package']) + r'\s*,'
        if re.search(plain, s):
            s = re.sub(plain, lambda m: m[1] + item['package'] + ' (= ' + item['version'] + '),', s)
        else:
            assert item['package'] == 'libcapi20-3t64', 'Review unlisted transitive build input'
    for relation in matches:
        op, required = re.search(r'\(([^ ]+)\s+([^)]*)\)', relation).groups()
        assert subprocess.run(['dpkg', '--compare-versions', item['version'], op, required]).returncode == 0
    s = re.sub(pattern, item['package'] + ' (= ' + item['version'] + ')', s)
p.write_text(s)
Path('/work/source/debian/verified-build-inputs.json').write_text(json.dumps([
    {k: v for k, v in item.items() if k != 'source_job'} for item in inputs], indent=2) + '\n')
Path('/etc/apt/preferences.d/verified-build-inputs').write_text(''.join(
    f"Package: {item['package']}\nPin: version {item['version']}\nPin-Priority: 1002\n\n"
    for item in inputs))
BUILD_INPUTS
fi
if [ "$TASK_SOURCE" = plymouth ]; then
    # Its upstream version helper derives a release tarball's version from the
    # real directory name. Preserve that convention while keeping our work link.
    mv source plymouth-26.134.222
    ln -s plymouth-26.134.222 source
fi
extra=()
if [ "$TASK_SOURCE" = ums ]; then
    # Java has its own compiler-backed adapter. Keep an explicit plan in the
    # retained source; the build's declared JDK is installed before projection.
    printf '["c", "java"]\n' > /work/source/debian/sparky-lean-languages.json
    extra+=(--build-dependency ffmpeg --build-dependency libmediainfo0v5)
    python3 - <<'UMS_TESTS'
from pathlib import Path
import difflib, hashlib, json, shutil
inputs = Path('/work/test-inputs')
manifest = json.loads((inputs / 'provenance.json').read_text())
for name, expected in manifest['matching_java_sources'].items():
    assert hashlib.sha256((Path('/work/source') / name).read_bytes()).hexdigest() == expected
for name, expected in manifest['fixtures'].items():
    assert hashlib.sha256((inputs / name).read_bytes()).hexdigest() == expected
shutil.copytree(inputs, '/work/source/debian/stereo-policy-vectors')
p = Path('/work/source/debian/rules')
s = p.read_text()
configure = 'override_dh_auto_configure:\n\n'
assert s.count(configure) == 1
s = s.replace(configure, 'override_dh_auto_configure:\n\tmkdir -p src/test/resources/stereo-policy\n\tcp debian/stereo-policy-vectors/*.tsv src/test/resources/stereo-policy/\n\n')
old = 'override_dh_auto_test:\n\n'
assert s.count(old) == 1
s = s.replace(old, 'override_dh_auto_test:\n\tmvn -B -Doffline=true -Dmaven.gitcommitid.skip=true test\n\n')
p.write_text(s)
pom = Path('/work/source/pom.xml')
original = pom.read_text()
marker = '\t\t</testResources>'
assert original.count(marker) == 1
entry = '''\t\t\t<testResource>
\t\t\t\t<directory>src/test/resources/stereo-policy</directory>
\t\t\t\t<includes><include>*.tsv</include></includes>
\t\t\t\t<targetPath>stereo-policy</targetPath>
\t\t\t\t<filtering>false</filtering>
\t\t\t</testResource>
'''
patched = original.replace(marker, entry + marker)
patches = Path('/work/source/debian/patches')
patches.mkdir(exist_ok=True)
filename = 'stereo-policy-test-resources.patch'
(patches / filename).write_text(
    'Description: Include the shared stereo vectors on the Maven test classpath\n'
    'Author: Daniel Ramos (Capitain Jack)\n'
    'Forwarded: no\n\n' + ''.join(difflib.unified_diff(
        original.splitlines(keepends=True), patched.splitlines(keepends=True),
        fromfile='a/pom.xml', tofile='b/pom.xml')))
with (patches / 'series').open('a') as stream:
    stream.write('\n' + filename + '\n')
UMS_TESTS
fi
if [ "$TASK_SOURCE" = kf6-kiconthemes ]; then
    # The stereo icon test reads SVG files through QImageReader.
    # qt6-svg-dev alone does not install that runtime image-format plugin.
    extra+=(--build-dependency 'qt6-svg-plugins <!nocheck>')
fi
if [ "$TASK_SOURCE" = partitionmanager ]; then
    extra+=(--build-dependency 'xvfb <!nocheck>' --build-dependency 'xauth <!nocheck>')
fi
if [ "$TASK_SOURCE" = spice-gtk ]; then
    extra+=(--build-dependency gi-docgen)
fi
if [ "$TASK_SOURCE" = sparky-stereo-cec ]; then
    # KF6Config's installed CMake configuration imports Qt6Qml, even though the
    # helper itself uses the Qt Core/DBus/Wayland interfaces.
    extra+=(--build-dependency qt6-declarative-dev)
fi
if [ "$TASK_SOURCE" = xscreensaver ]; then
    extra+=(--preserve-source 'hacks/*.c' 'check-configs.pl validates resources from C text and cannot consume inserted line directives')
fi
if [ "$TASK_SOURCE" = kf6-kio ]; then
    extra+=(--preserve-source 'templates/kioworker6/src/*' 'KAppTemplate substitutes %{APPNAME} placeholders before these templates become C++')
fi
case "$TASK_SOURCE" in
qt6-base|qt6-multimedia)
    extra+=(--preserve-source 'src/*_p.h' 'Qt syncqt reads the private-API warning comments, including We mean it.; retain its input headers exactly')
    ;;
esac
if [ "$TASK_SOURCE" = qt6-multimedia ]; then
    extra+=(--preserve-source 'src/3rdparty/eigen/*' 'Debian links system Eigen through /usr/include/eigen3; the unused vendored tree includes PowerPC target pragmas that cannot be qualified by the x86 compiler')
fi
if [ "$TASK_SOURCE" = qt6-base ]; then
    extra+=(--preserve-source 'tests/*' 'Qt test inputs include deliberate comment/splice and invalid-syntax fixtures consumed as text by qmake and moc; preserve the upstream test corpus while projecting production source')
    extra+=(--preserve-source 'src/corelib/global/qoperatingsystemversion.h' 'Qt syncqt generates a different public-header set after textual projection; retain this input exactly, verified by the authored/projected syncqt comparison')
fi
if [ "$TASK_SOURCE" = wine ]; then
    extra+=(--preserve-source '*.h' 'WIDL and WRC also preprocess shared headers and reject filename-less line directives; preserve their exact inputs')
fi
if [ "$TASK_SOURCE" = octave ]; then
    extra+=(--preserve-source 'libgnu/*.in.h' 'Gnulib header templates contain @INCLUDE_NEXT@ and other substitutions; Makefile rules generate the actual C headers from these exact inputs')
fi
if [ "$TASK_SOURCE" = blender ]; then
    extra+=(--preserve-source 'extern/Eigen3/Eigen/src/Core/arch/AltiVec/*' 'PowerPC AltiVec headers contain target-specific pragmas and builtins; the x86 checker cannot qualify those inactive target inputs')
    extra+=(--preserve-source 'source/blender/nodes/*.cc' 'discover_nodes.py uses namespace-closing comments to generate node registration symbols; these comments are build input')
fi
if [ "$TASK_SOURCE" = mesa ]; then
    extra+=(--preserve-source 'src/compiler/glsl/glcpp/tests/*' 'GLSL preprocessor regression inputs deliberately exercise line continuations and malformed directives; they are test data rather than C translation units')
    extra+=(--preserve-source 'src/panfrost/lib/pan_afbc.c' 'Inactive ARM NEON target pragmas cannot be checked by the x86 GCC preprocessed lexer')
    extra+=(--preserve-source 'src/util/format/u_format_unpack_neon.c' 'ARM NEON target pragma requires its target compiler; preserve the shared multiarchitecture source')
    extra+=(--preserve-source 'src/*/shaders/*' 'Shader include files use GLSL rather than C preprocessing even when named .h; retain their exact input')
    extra+=(--preserve-source 'src/vulkan/runtime/bvh/*.h' 'Shared shader and C headers have a GLSL consumer; C-only equivalence does not qualify it')
fi
if [ "$TASK_SOURCE" = wiz3d ]; then
    extra+=(--preserve-source 'ThirdPartyLibs/*' 'Windows vendor headers contain MSVC-only preprocessing such as defined(and); preserve them until the Windows-target checker is qualified instead of applying the GCC checker')
    python3 - <<'WIZ_INPUT_PATH'
from pathlib import Path
p = Path('/work/source/tools/build-linux/gen_build.py')
s = p.read_text()
for old, new in (
    ('/Fo${out} ${in}', '/Fo${out} -- ${in}'),
    ('${ppflags} ${in} |', '${ppflags} -- ${in} |'),
):
    assert s.count(old) == 1
    s = s.replace(old, new)
p.write_text(s)
WIZ_INPUT_PATH
fi
case "$TASK_SOURCE" in
qemu)
    python3 /toolkit/packages/qemu-stereo/prepare-lean.py /work/source "$TASK_VERSION"
    ;;
sparky-stereo-memory-kcm|sparky-stereo-cec|sparky-stereo-cushion-swap)
    PYTHONPATH=/toolkit python3 -m lean.debian_custom /work/source "$TASK_VERSION" --toolkit /toolkit "${extra[@]}"
    ;;
*)
    PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/source "$TASK_VERSION" --toolkit /toolkit "${extra[@]}"
    ;;
esac
if [ "$TASK_SOURCE" = wine ]; then
    python3 /toolkit/packages/wine-stereo/sync-control.py /work/source
    python3 /toolkit/packages/wine-stereo/pin-vulkan-registry.py /work/source
fi
if [ "$TASK_SOURCE" = nvidia-kmod-open ]; then
    python3 - <<'DKMS'
from pathlib import Path
p = Path('/work/source/debian/rules')
s = p.read_text()
old = 'tar --exclude=./debian --exclude=./.pc -cf - .'
assert s.count(old) == 1
p.write_text(s.replace(old, 'tar --exclude=./debian --exclude=./.pc --exclude=./.sparky-lc -cf - .'))
DKMS
fi
if [ "$TASK_SOURCE" = spice-gtk ]; then
    python3 - <<'SPICE_DOCS'
from pathlib import Path
p = Path('/work/source/debian/libspice-client-glib-2.0-dev.install')
s = p.read_text()
assert s.count('usr/share/gtk-doc') == 1
p.write_text(s.replace('usr/share/gtk-doc', 'usr/share/doc/SpiceClientGLib-2.0'))
p = Path('/work/source/debian/libspice-client-gtk-3.0-dev.install')
with p.open('a') as f:
    f.write('usr/share/doc/SpiceClientGtk-3.0\n')
SPICE_DOCS
fi
if [ "$TASK_SOURCE" = partitionmanager ]; then
    # Its two GUI tests create dialogs. Keep tests enabled in an isolated X
    # server; preserve the environment in the rebuildable source package.
    cat >> /work/source/debian/rules <<'TEST_RULE'

override_dh_auto_test:
	xvfb-run -a --server-args='-screen 0 1280x1024x24 -noreset' dh_auto_test
TEST_RULE
fi
if [ "$TASK_SOURCE" = kf6-kfilemetadata ]; then
    # Parallel short-lived GUI tests must not race an X server reset when the
    # previous test disconnects. Keep the existing Xvfb test environment.
    python3 - <<'XSERVER'
from pathlib import Path
p = Path('/work/source/debian/rules')
s = p.read_text()
old = 'xvfb-run -a dh_auto_test -Skf6'
assert s.count(old) == 1
p.write_text(s.replace(old, "xvfb-run -a --server-args='-screen 0 1280x1024x24 -noreset' dh_auto_test -Skf6"))
XSERVER
fi
apt-get -y update
apt-get -y --no-install-recommends build-dep /work/source
if [ -f /work/build-inputs.json ]; then
    python3 - <<'INSTALLED_INPUTS'
from pathlib import Path
import json, subprocess
for item in json.loads(Path('/work/build-inputs.json').read_text()):
    actual = subprocess.check_output(
        ['dpkg-query', '-W', '-f=${Version}', item['package']], text=True)
    assert actual == item['version'], (item['package'], actual, item['version'])
    print('Verified build input:', item['package'], actual)
INSTALLED_INPUTS
fi
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- dpkg-buildpackage -us -uc -j4
cp .sparky-lc/source.json ../native-source.json
tar -cJf ../native-authored-evidence.tar.xz .sparky-lc
python3 - <<'INNER'
from pathlib import Path
import os, subprocess
files = [str(p) for p in Path('/work').glob('*.deb') if '+lc1_' in p.name]
assert files
subprocess.run(['python3','-m','lean.release','check-debs',*sorted(files)],
               check=True,env=os.environ|{'PYTHONPATH':'/toolkit'})
INNER
"""

for name in requested:
    if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", name):
        raise SystemExit("Invalid source name")
    job = jobs[name]
    work = base / "jobs" / (name + "-amd64")
    status = work / "status.json"
    if status.exists():
        print(f"{name}: existing checkpoint, review rather than overwrite", flush=True)
        continue
    if shutil.disk_usage(base).free < 14 * 1024**3:
        raise SystemExit("Root disk below 14 GiB start threshold")
    build_inputs = []
    if name == 'wine':
        archived = base / 'wine-build-inputs'
        records = json.loads((archived / 'verified-packages.json').read_text())
        assert {r['package'] for r in records} == {
            'unicode-data', 'unicode-idna', 'unicode-cldr-core', 'libldap2-dev',
            'libcapi20-dev', 'libcapi20-3t64'}
        for record in records:
            if record['architecture'] not in ('all', 'amd64'):
                continue
            archive = archived / record['filename']
            assert archive.stat().st_size == int(record['size'])
            assert hashlib.sha256(archive.read_bytes()).hexdigest() == record['sha256']
            build_inputs.append({'package': record['package'], 'version': record['version'],
                                 'archive': archive.name, 'sha256': record['sha256'],
                                 'architecture': record['architecture'],
                                 'source_job': str(archived)})
    if name == "flightgear":
        primary = base / "jobs/simgear-amd64"
        prior = json.loads((primary / "status.json").read_text())
        if prior["state"] != "candidate-needs-review":
            raise SystemExit("FlightGear requires the completed SimGear race repair")
        candidates = list(primary.glob("libsimgear-dev_*+lc1_amd64.deb"))
        if len(candidates) != 1:
            raise SystemExit("Expected one verified SimGear development package")
        archive = candidates[0]
        version = subprocess.check_output(
            ["dpkg-deb", "-f", str(archive), "Version"], text=True).strip()
        if version != "1:2024.1.5+dfsg-1+stereo3d6+lc1":
            raise SystemExit("Review the changed SimGear repair version")
        qualified_archives = sorted(primary.glob("*+lc1_*.deb"))
        subprocess.run(["python3", "-m", "lean.release", "check-debs",
                        *map(str, qualified_archives)],
                       check=True, env=os.environ | {"PYTHONPATH": str(toolkit)},
                       stdout=subprocess.DEVNULL)
        build_inputs.append({
            "package": "libsimgear-dev", "version": version, "archive": archive.name,
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "source_job": str(primary),
        })
        archived_data = base / "flightgear-data-inputs"
        data_records = json.loads((archived_data / "verified-packages.json").read_text())
        if {r["package"] for r in data_records} != {"flightgear-data-ai", "flightgear-data-base"}:
            raise SystemExit("Review changed FlightGear test-data inputs")
        for record in data_records:
            archive = archived_data / Path(record["filename"]).name
            with archive.open("rb") as stream:
                checksum = hashlib.file_digest(stream, "sha256").hexdigest()
            if checksum != record["sha256"] or archive.stat().st_size != int(record["size"]):
                raise SystemExit("Archived test-data integrity failure")
            build_inputs.append({
                "package": record["package"], "version": record["version"],
                "archive": archive.name, "sha256": checksum,
                "source_job": str(archived_data),
            })
    work.mkdir(parents=True, exist_ok=False)
    if name == 'ums':
        mirror = str(cfg.path('SPARKY_INPUTS_DIR') / 'players-shared-layer/src/ums')
        revision = '6bf4fe90bc38be65d9abc61afee1e73ade2b749a'
        inputs = work / 'test-inputs'
        inputs.mkdir()
        provenance = {'commit': revision, 'matching_java_sources': {}, 'fixtures': {}}
        for filename in ['StereoPolicy.java', 'StereoPolicyTest.java']:
            relative = ('src/main/java/net/pms/util/' if filename == 'StereoPolicy.java'
                        else 'src/test/java/net/pms/util/') + filename
            raw = subprocess.check_output(['git', '-C', mirror, 'show', revision + ':' + relative])
            provenance['matching_java_sources'][relative] = hashlib.sha256(raw).hexdigest()
        for filename in ['video-views.tsv', 'name-tags.tsv']:
            raw = subprocess.check_output(['git', '-C', mirror, 'show',
                                          revision + ':src/test/resources/stereo-policy/' + filename])
            (inputs / filename).write_bytes(raw)
            provenance['fixtures'][filename] = hashlib.sha256(raw).hexdigest()
        (inputs / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    if build_inputs:
        dependencies = work / "dependency-packages"
        dependencies.mkdir()
        for item in build_inputs:
            shutil.copy2(Path(item["source_job"]) / item["archive"],
                         dependencies / item["archive"])
        with (dependencies / "Packages").open("w") as index:
            subprocess.run(["dpkg-scanpackages", ".", "/dev/null"],
                           cwd=dependencies, stdout=index, check=True)
        (work / "build-inputs.json").write_text(json.dumps(build_inputs, indent=2) + "\n")
    records = [line.split() for line in job["files"].splitlines() if line.strip()]
    dsc = None
    for sha, size, filename in records:
        source = repo / job["directory"] / filename
        if source.stat().st_size != int(size):
            raise SystemExit(f"Source size changed: {source}")
        with source.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != sha:
            raise SystemExit(f"Source hash changed: {source}")
        shutil.copy2(source, work / filename)
        if filename.endswith(".dsc"):
            dsc = filename
    if not dsc:
        raise SystemExit(f"{name}: no source descriptor")
    (work / "run.sh").write_text(recipe)
    version = job["version"] + "+lc1"
    container = "sparky-lc-" + name.replace("+", "-").replace(".", "-") + "-amd64"
    command = [
        "docker", "run", "--rm", "--name", container, "--cpus", "4",
        "-e", f"TASK_DSC={dsc}", "-e", f"TASK_VERSION={version}",
        "-e", f"TASK_SOURCE={name}",
        "-v", f"{work}:/work", "-v", f"{repo}:/repo:ro",
        "-v", f"{toolkit}:/toolkit:ro",
        "-v", "/usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro",
        "sparky-lc-migration:20261020",
        "bash", "/work/run.sh",
    ]
    if name == 'ums':
        cache = base / 'ums-maven-cache'
        if cache.is_dir():
            at = command.index('sparky-lc-migration:20261020')
            command[at:at] = ['-v', str(cache) + ':/maven-cache',
                              '-e', 'MAVEN_OPTS=-Dmaven.repo.local=/maven-cache']
    start = time.time()
    status.write_text(json.dumps({
        "source": name, "version": version, "architecture": "amd64",
        "state": "building", "archives": [],
    }, indent=2) + "\n")
    print(f"{name}: building {version}", flush=True)
    stopped = False
    with (work / "build.log").open("wb") as log:
        process = start_build(command, container, log)
        while process.poll() is None:
            if shutil.disk_usage(base).free < 12 * 1024**3:
                subprocess.run(["docker", "stop", "-t", "20", container], check=False)
                stopped = True
                break
            time.sleep(5)
        result = process.wait()
    result_record = {
        "source": name, "version": version, "architecture": "amd64",
        "exit_code": result, "disk_floor_stop": stopped,
        "seconds": round(time.time() - start, 1),
        "state": "candidate-needs-review" if result == 0 else "needs-repair",
        "expected_binaries": [r["Package"] for r in job["binaries"]
                              if r["Architecture"] in ("amd64", "all")],
        "archives": sorted(p.name for p in work.glob("*+lc1_*.deb")),
    }
    status.write_text(json.dumps(result_record, indent=2) + "\n")
    print(f"{name}: {result_record['state']}, exit {result}", flush=True)
    if stopped:
        raise SystemExit("Stopped own container at disk floor")
