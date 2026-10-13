-- Deeva's Designs: remove the Portfolio 2 indexes
--
-- Puts the database back to its "before" state so the benchmark can be
-- repeated. Indexes that back primary keys and UNIQUE constraints stay.

DROP INDEX IF EXISTS customer_order_customer_idx;
DROP INDEX IF EXISTS order_item_order_cover_idx;
DROP INDEX IF EXISTS job_assignment_open_idx;
DROP INDEX IF EXISTS measurement_set_wearer_idx;
DROP INDEX IF EXISTS journal_entry_date_brin;
DROP INDEX IF EXISTS journal_entry_date_btree;
DROP INDEX IF EXISTS journal_line_entry_idx;
DROP INDEX IF EXISTS customer_order_open_idx;
DROP INDEX IF EXISTS payment_order_cover_idx;
DROP INDEX IF EXISTS customer_name_trgm_idx;
