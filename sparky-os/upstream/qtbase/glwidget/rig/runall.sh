# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtgl/rig
./proof.sh a qtgl-run:final apps tests mono
./proof.sh c qtgl-run:control mono
echo ALL_DONE
