#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtmm-lane/run
unset IMG DEV DEVDIR
./rtests.sh luma > ../tests-luma-run.log 2>&1
./rtests.sh final > ../tests-final-run.log 2>&1
./final-proof.sh > ../final-proof.log 2>&1
./proofs-fresh.sh > ../proofs-fresh.log 2>&1
echo done > ../chain-done
