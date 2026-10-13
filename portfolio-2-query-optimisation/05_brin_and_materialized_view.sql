-- Deeva's Designs: two further experiments
--
-- Run from this folder after benchmark.sql:
--   psql -U postgres -d deevas_designs -f 05_brin_and_materialized_view.sql
--
-- A. How small is a block-range index next to a B-tree on the same column?
-- B. Q4 stayed slow with indexes. Does a materialized view fix it?
-- C. What does Q4 look like with parallel query left on?
--
-- Output goes to results/experiments.txt.

\set ON_ERROR_STOP on
\pset pager off
\o results/experiments.txt

-- ---------------------------------------------------------------------
-- A. Block-range index against B-tree
-- ---------------------------------------------------------------------

\qecho '-- A1: how closely the order of rows on disk follows entry_date (1 = exactly)'
SELECT attname, correlation
  FROM pg_stats
 WHERE tablename = 'journal_entry' AND attname = 'entry_date';

CREATE INDEX IF NOT EXISTS journal_entry_date_btree ON journal_entry (entry_date);
VACUUM (ANALYZE) journal_entry;

\qecho
\qecho '-- A2: size of each index on the same 273,958 rows'
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
       pg_relation_size(indexrelid) / 8192          AS pages
  FROM pg_stat_user_indexes
 WHERE indexrelname IN ('journal_entry_date_brin', 'journal_entry_date_btree')
 ORDER BY indexrelname;

\qecho
\qecho '-- A3: one month of entries, with both indexes available'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
  FROM journal_entry
 WHERE entry_date >= DATE '2026-09-01' AND entry_date < DATE '2026-10-01';

DROP INDEX journal_entry_date_btree;

\qecho
\qecho '-- A4: the same query with only the block-range index'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*)
  FROM journal_entry
 WHERE entry_date >= DATE '2026-09-01' AND entry_date < DATE '2026-10-01';


-- ---------------------------------------------------------------------
-- B. Materialized view for the monthly revenue report
-- ---------------------------------------------------------------------
-- Past months do not change, so the report can be computed once and
-- stored. The cost is that the stored result is only as fresh as the
-- last refresh.

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_revenue;

CREATE MATERIALIZED VIEW mv_monthly_revenue AS
SELECT date_trunc('month', je.entry_date)::date AS month,
       a.code,
       a.name,
       sum(jl.credit - jl.debit) AS revenue
  FROM journal_entry je
  JOIN journal_line jl USING (entry_id)
  JOIN account a       USING (account_id)
 WHERE a.account_type = 'revenue'
 GROUP BY 1, 2, 3;

-- A unique index lets the view be refreshed without blocking readers.
CREATE UNIQUE INDEX mv_monthly_revenue_key ON mv_monthly_revenue (month, code);
ANALYZE mv_monthly_revenue;

\qecho
\qecho '-- B1: Q4 answered from the materialized view'
EXPLAIN (ANALYZE, BUFFERS)
SELECT code, name, revenue
  FROM mv_monthly_revenue
 WHERE month = DATE '2026-09-01'
 ORDER BY code;

\qecho
\qecho '-- B2: rows where the view and the live query disagree (expect 0)'
SELECT count(*) AS differences
  FROM ((SELECT code, name, revenue
           FROM mv_monthly_revenue
          WHERE month = DATE '2026-09-01')
        EXCEPT
        (SELECT a.code, a.name, sum(jl.credit - jl.debit)
           FROM journal_entry je
           JOIN journal_line jl USING (entry_id)
           JOIN account a       USING (account_id)
          WHERE je.entry_date >= DATE '2026-09-01'
            AND je.entry_date <  DATE '2026-10-01'
            AND a.account_type = 'revenue'
          GROUP BY a.code, a.name)) d;

\qecho
\qecho '-- B3: what a refresh costs'
SELECT clock_timestamp() AS started \gset
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_revenue;
SELECT round(extract(epoch FROM clock_timestamp() - :'started'::timestamptz) * 1000) AS refresh_ms;


-- ---------------------------------------------------------------------
-- C. Q4 with parallel query left on
-- ---------------------------------------------------------------------
-- benchmark.sql switches parallel query off. This is Q4 at the server
-- default, to compare with Q4 in results/after.txt.

\qecho
\qecho '-- C1: Q4 with parallel query at the server default'
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.code, a.name, sum(jl.credit - jl.debit) AS revenue
  FROM journal_entry je
  JOIN journal_line jl USING (entry_id)
  JOIN account a       USING (account_id)
 WHERE je.entry_date >= DATE '2026-09-01'
   AND je.entry_date <  DATE '2026-10-01'
   AND a.account_type = 'revenue'
 GROUP BY a.code, a.name
 ORDER BY a.code;

\o
\echo 'Done. Output is in results/experiments.txt'
