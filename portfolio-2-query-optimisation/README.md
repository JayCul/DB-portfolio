# Portfolio 2: Query Processing and Optimisation

Eight query plans for Deeva's Designs, measured before and after optimisation on PostgreSQL 18. Three techniques are used: indexing, rewriting a query, and a materialized view.

## 1. Files

| File | Purpose |
|---|---|
| [01_generate_data.sql](01_generate_data.sql) | Generates about three years of projected trading |
| [02_queries.sql](02_queries.sql) | The queries under test, each wrapped in `EXPLAIN (ANALYZE, BUFFERS)` |
| [03_indexes.sql](03_indexes.sql) | The nine indexes, each listed under the query it serves |
| [04_drop_indexes.sql](04_drop_indexes.sql) | Removes them again, so the test can be repeated |
| [benchmark.sql](benchmark.sql) | Runs the queries without the indexes, then with them |
| [summarise.py](summarise.py) | Builds the results table from the two sets of plans |
| [05_brin_and_materialized_view.sql](05_brin_and_materialized_view.sql) | Three further experiments |
| [results/](results/) | Plans and timings captured on my machine |

## 2. Test data

Deeva's Designs is a start-up and has no history of this size, so the data is a projection: 20,000 customers and 100,000 orders spread over three years, with the jobs, payments and ledger entries that go with them. The generator uses a fixed random seed, so it produces the same rows every time.

Three properties of the data matter for the results:

- **Most orders are finished.** About 5% are still open. Queries about open work touch a small part of each table.
- **A few customers order often and most order rarely**, as in a real customer base.
- **Ledger entries are stored in date order**, because a ledger is filled one day after another.

## 3. Method

```bash
psql -U postgres -d deevas_designs -f benchmark.sql
```

```bash
python summarise.py
```

```bash
psql -U postgres -d deevas_designs -f 05_brin_and_materialized_view.sql
```

`benchmark.sql` removes the indexes, runs every query twice and keeps the second run, then creates the indexes and does the same again. The first run loads the tables into memory, so the second run measures the plan and not the disk.

Two measures are reported for each query. **Execution time** varies a little from run to run. **Pages read** (8 kB each) does not, so it is the more reliable of the two.

Parallel query is switched off for the benchmark session. Starting worker processes added a delay that changed from run to run and was larger than some of the effects being measured. Experiment C shows one query with it left on.

## 4. Results

The full table is in [results/summary.md](results/summary.md). The plans behind it are in [results/before.txt](results/before.txt) and [results/after.txt](results/after.txt), and index sizes are in [results/index_sizes.txt](results/index_sizes.txt).

## 5. Analysis

### Q1: one customer's orders

Without an index on `customer_id`, PostgreSQL reads all 100,001 orders to find this customer's 45, then reads all 191,919 order lines to total them. With `customer_order_customer_idx` it goes straight to the 45 orders. The order lines come from `order_item_order_cover_idx` as an index-only scan: quantity and price are stored in the index, so the table is not visited at all (`Heap Fetches: 0`).

### Q2: a tailor's unfinished sewing

The filter is on `job_assignment`, where 234,807 rows are scanned to find 213. The index `job_assignment_open_idx` is partial: it holds only assignments that are not completed. It is a few dozen kilobytes on a 13 MB table, because finished work is left out. The five joins after it were already using primary keys and did not change.

### Q3: a wearer's latest measurements

The query looks up the newest measurement set for one wearer. Before, all 35,802 sets are scanned and sorted. After, `measurement_set_wearer_idx` returns that wearer's sets already ordered by date. The gain is small in absolute terms because the table is small, but this lookup happens every time a garment is cut.

### Q4: revenue for one month

This is the query that indexing did not fix. The block-range index finds September's 8,883 journal entries by reading about 130 pages instead of 2,648. But the amounts are in `journal_line`, and PostgreSQL still reads all 591,146 lines and joins them by hash. It is right to do so: fetching the lines for 8,883 entries one at a time through an index would touch more pages than reading the table once. Pages read fall by about 40% and the time improves by about a third, far less than any other query. The fix is in experiment B.

### Q5: finished orders still owing money

Q5a asks the question through the view `v_order_balance`. The view totals every order's lines and every order's payments before the filter on status is applied, so 100,001 orders are totalled to report on 1,292. Indexes make each total cheaper to compute but do not reduce how many are computed.

Q5b is the same question rewritten. It starts from the 1,292 ready orders and totals only those, using two `LATERAL` subqueries.

The result is the main finding of this portfolio. **Without indexes the rewrite is far slower than the view**: each of the 1,292 orders triggers a full scan of `order_item` and of `payment`, which is over 4.8 million pages. **With indexes it is the fastest version by a wide margin**: each lookup becomes an index-only scan. A rewrite and its indexes have to be designed together. Either one alone is not an improvement.

### Q6: customer search by part of a name

`ILIKE '%kemi ade%'` cannot use a B-tree, because the pattern does not start at the beginning of the value. A trigram index (`pg_trgm`) breaks each name into three-letter pieces and can find the rows containing the pieces of the search text. The plan changes from a scan of all 20,003 customers to a bitmap scan that checks 44 candidates and keeps 36.

### Q7: the balance trigger's own query

The trigger from Portfolio 1 runs this query once for every journal line written. Without `journal_line_entry_idx` each run scans the whole table of 591,146 lines. That is why the data generator switches the trigger off during its bulk load: with the trigger on and no index, loading would mean one full scan per line inserted. A constraint that is enforced by a query needs an index as much as any report does.

## 6. Further experiments

Output is in [results/experiments.txt](results/experiments.txt).

**A. Block-range index against B-tree.** Both were built on `journal_entry.entry_date`. The B-tree stores one entry per row. The block-range index stores only the lowest and highest date in each group of 16 pages, so it is a tiny fraction of the size. It works here because the correlation between row position and date is 1: the rows are in date order on disk. The B-tree answers a count for one month from the index alone. The block-range index is less exact and has to read and recheck the pages it points at (`Rows Removed by Index Recheck`). For a table that only grows at the end, that is a good trade.

**B. Materialized view.** `mv_monthly_revenue` stores revenue per month and account. The September report is then a scan of a 148-row table instead of a join over the ledger, and the check in B2 confirms it returns the same figures as the live query. The cost is freshness: the view shows the ledger as it was at the last refresh. Past months do not change, so a refresh each night is enough, and B3 shows what one costs.

**C. Parallel query.** Q4 again, with parallel workers allowed. The plan gains `Gather Merge` and `Parallel Seq Scan` nodes and reads about the same number of pages.

## 7. What the indexes cost

Every index has to be updated on each insert, and takes space. The two covering indexes and `journal_line_entry_idx` are the largest, each roughly a third to a half the size of its table. The two partial indexes and the block-range index are the cheapest, at a few dozen kilobytes each. For a business that writes a few hundred rows a day and reads far more often, the cost is acceptable.

## 8. Evidence

Screenshots are in [evidence/](evidence/).
