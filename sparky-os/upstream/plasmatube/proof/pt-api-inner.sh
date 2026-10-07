#!/bin/bash
sed -i 's/scram-sha-256/trust/;s/md5/trust/' /etc/postgresql/*/main/pg_hba.conf
service postgresql start; sleep 3
su postgres -c 'psql -c "CREATE ROLE tester SUPERUSER LOGIN CREATEDB"; psql -c "CREATE ROLE peertube SUPERUSER LOGIN CREATEDB"'
service redis-server start
chown -R tester /pt 2>/dev/null
su tester -c "cd /pt && npm run clean:server:test; npm run mocha -- --timeout 60000 --no-config -c --exit packages/tests/dist/api/transcoding/transcoder.js 2>&1 | tail -80"
