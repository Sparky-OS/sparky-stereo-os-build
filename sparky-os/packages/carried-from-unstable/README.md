# Carried from Debian unstable

Source preparation for HPLIP and QXL packages missing from Debian testing.
The source versions, hashes and migration blockers are explicit in prepare.sh and lists/carried-from-unstable.tsv.
Run prepare.sh as the build user inside a disposable testing container with the edition toolkit at /toolkit and Debian source downloads at /work/SOURCE.
SOURCE_DATE_EPOCH and SOURCE_DATE_RFC2822 come from repo/build-provenance.sh.

HPLIP carries the runtime and build-input changes in HP's signed 3.26.6 release over Debian's 3.26.4 packaging, retaining Debian's existing fixes, printer models and distribution table.
Debian's safer shell pstotiff, the wget HEAD option, check-plugin installation and exclusion of the proprietary ImageProcessor are retained.
HP's security release removes the privileged D-Bus plugin installation service.
The Debian version stays based on 3.26.4 so the next Debian revision can supersede this backport.
QXL carries Frank Heckenbach's patch from Debian bug 1137518.
Qualify the prepared sources with the build, release gates and installed proofs; source preparation alone does not establish runtime behavior.

VMware needs separate treatment: upstream issue 12 links the breakage to removal of Mesa XA, and Ian Forbes's open merge request 21 proposes deprecating this driver for Linux.
A successful module load would not prove that missing KMS and 3D support had been restored.

`build.sh SOURCE WORK IMAGE PUBLISHED_TREE ARCHIVE_DIR` combines the source preparation and binary build.
Set DOCKER_HOST to the lane's socket and SPARKY_CONTAINER_PREFIX to its owned prefix.
Use an empty work directory with the pinned Debian source files in WORK/SOURCE and a freshly updated testing image containing Debian's build dependencies plus gcc, node-acorn, nodejs, perl, python3, python3-yaml and bubblewrap.
The signed archive configuration and public keys live in ARCHIVE_DIR; its edition source refers to file:/repo.
The launcher supplies the host build facts, resolves the published-tree alias, runs as the invoking user, and refuses to overwrite earlier outputs.
Inspect the build record, archive checks and installed proof before staging anything.
