#!/bin/bash
# PeerTube's API test of transcoding, with PostgreSQL and Redis in the container
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --cpus 4 -e CI=1 -e NPM_CONFIG_LOGLEVEL=silent -e HOME=/home/tester -v ${SPARKY_WORKSPACES:?}/plasmatube/peertube:/pt -v ${SPARKY_WORKSPACES:?}/plasmatube/run:/r:ro -w /pt pt-node:2 bash /r/pt-api-inner.sh
