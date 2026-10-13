-- Deeva's Designs: before-and-after benchmark
--
-- Run from this folder, in one psql session:
--   psql -U postgres -d deevas_designs -f benchmark.sql
--
-- Every set of queries is run twice and only the second run is kept.
-- The first run loads the tables into memory, so the timings compare
-- query plans and not whether the data happened to be cached.

\set ON_ERROR_STOP on
\pset pager off

-- Parallel query is switched off for this session only. Starting worker
-- processes adds a delay that varies from run to run and is larger than
-- some of the effects being measured. 05_brin_and_materialized_view.sql
-- shows one query with it left on.
SET max_parallel_workers_per_gather = 0;

\echo 'Step 1 of 4: removing the Portfolio 2 indexes'
\i 04_drop_indexes.sql
VACUUM (ANALYZE);

\echo 'Step 2 of 4: running the queries without the indexes'
\o results/warmup.txt
\i 02_queries.sql
\o results/before.txt
\i 02_queries.sql
\o

\echo 'Step 3 of 4: creating the indexes'
\i 03_indexes.sql
-- VACUUM marks pages as all-visible, which index-only scans rely on.
VACUUM (ANALYZE);

\echo 'Step 4 of 4: running the queries with the indexes'
\o results/warmup.txt
\i 02_queries.sql
\o results/after.txt
\i 02_queries.sql

\o results/index_sizes.txt
SELECT i.indexrelname                               AS index_name,
       i.relname                                    AS table_name,
       pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
       pg_size_pretty(pg_relation_size(i.relid))      AS table_size
  FROM pg_stat_user_indexes i
 WHERE i.indexrelname IN ('customer_order_customer_idx', 'order_item_order_cover_idx',
                          'job_assignment_open_idx', 'measurement_set_wearer_idx',
                          'journal_entry_date_brin', 'journal_line_entry_idx',
                          'customer_order_open_idx', 'payment_order_cover_idx',
                          'customer_name_trgm_idx')
 ORDER BY pg_relation_size(i.indexrelid) DESC;
\o

\echo 'Done. Plans are in results/before.txt and results/after.txt'
\echo 'Next: python summarise.py'
