set -e
bash /work/tsrc.sh > /work/tsrc.log 2>&1
bash /work/tbuild.sh
echo CHAIN_DONE >> /work/tbuild.log
