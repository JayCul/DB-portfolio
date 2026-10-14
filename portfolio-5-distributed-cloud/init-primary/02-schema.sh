#!/bin/sh
# Runs once on the primary, after 01-replication.sh. Loads the Portfolio 1
# schema, views and sample data, so both servers hold Deeva's database.
set -e

for file in 01_schema.sql 02_views.sql 03_sample_data.sql; do
    psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "/schema/$file"
done
