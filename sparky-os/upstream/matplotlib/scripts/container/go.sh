bash /pb/install.sh || exit 1
cp /pb/proof.sh /tmp/proof.sh
setpriv --reuid=1000 --regid=1000 --groups 125 bash /tmp/proof.sh "$@"
