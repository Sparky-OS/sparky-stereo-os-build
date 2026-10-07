#!/bin/bash
# PeerTube's API test of transcoding, with PostgreSQL and Redis in the container
docker run --rm --platform linux/amd64 --cpus 4 -e CI=1 -e NPM_CONFIG_LOGLEVEL=silent -e HOME=/home/tester -v /K3D/temp/partners/queue/plasmatube/peertube:/pt -v /K3D/temp/partners/queue/plasmatube/run:/r:ro -w /pt pt-node:2 bash /r/pt-api-inner.sh
