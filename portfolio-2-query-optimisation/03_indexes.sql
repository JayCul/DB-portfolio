-- Deeva's Designs: indexes added in Portfolio 2
--
-- Each index is listed under the query it was built for.

-- Trigram matching, needed for the name search in Q6.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Q1: find one customer's orders, already in date order.
CREATE INDEX customer_order_customer_idx
    ON customer_order (customer_id, order_date DESC);

-- Q1 and Q5b: find an order's lines. INCLUDE stores quantity and price in
-- the index itself, so the total can be computed without visiting the table.
CREATE INDEX order_item_order_cover_idx
    ON order_item (order_id) INCLUDE (quantity, unit_price);

-- Q2: a partial index holding only unfinished assignments. Finished ones
-- are the great majority and are never wanted by this query.
CREATE INDEX job_assignment_open_idx
    ON job_assignment (staff_id, task) WHERE completed_at IS NULL;

-- Q3: a wearer's measurement sets, newest first.
CREATE INDEX measurement_set_wearer_idx
    ON measurement_set (wearer_id, taken_on DESC);

-- Q4: journal entries are stored in date order, so a block-range index
-- can say which pages hold a month while staying very small.
CREATE INDEX journal_entry_date_brin
    ON journal_entry USING brin (entry_date) WITH (pages_per_range = 16);

-- Q4 and Q7: find the lines of a journal entry.
CREATE INDEX journal_line_entry_idx
    ON journal_line (entry_id);

-- Q5b: a partial index holding only open orders.
CREATE INDEX customer_order_open_idx
    ON customer_order (status)
 WHERE status IN ('confirmed', 'in_production', 'ready');

-- Q5b: find an order's payments, again without visiting the table.
CREATE INDEX payment_order_cover_idx
    ON payment (order_id) INCLUDE (amount, payment_kind);

-- Q6: a trigram index, which can answer ILIKE '%text%' searches.
CREATE INDEX customer_name_trgm_idx
    ON customer USING gin (full_name gin_trgm_ops);
