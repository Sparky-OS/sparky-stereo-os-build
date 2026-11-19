senseglove-api-dev
==================

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).

The headers and the example of SenseGlove's C++ API, with a CMake package, as a development package. See README.Debian for what is here and what is fetched.

Build:
-------------
OUT=/path/in/workspace/pack ./build.sh (inside a container with network, python3 and the Lean Code toolkit on PYTHONPATH)

The files come from github.com/Adjuvo/SenseGlove-API at the commit in build.sh; sources.tsv holds the size and SHA-256 of each, and a file that differs stops the build.
Credits: SenseGlove B.V.; the repository's records name Max Lammers and Mamadou Babaei.
