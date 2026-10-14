#!/bin/sh
# Starts the replica. The container runs as the postgres user.
#
# The first time, its data directory is empty. pg_basebackup fills it with
# a copy of the primary, and -R writes the settings that make this server
# follow the primary from then on. -C -S creates a replication slot, so
# the primary keeps any changes the replica has not received yet.
set -e

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    mkdir -p "$PGDATA"
    chmod 700 "$PGDATA"
    until pg_isready -q -h primary -U postgres; do
        sleep 1
    done
    PGPASSWORD=replicator \
        pg_basebackup -h primary -U replicator -D "$PGDATA" -R -X stream -C -S replica1
fi

# cluster_name is the name the primary sees this replica under
exec docker-entrypoint.sh postgres -c cluster_name=replica1 -c hot_standby=on
