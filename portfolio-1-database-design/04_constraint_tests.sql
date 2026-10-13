-- Deeva's Designs: constraint tests
--
--   psql -U postgres -d deevas_designs -f 04_constraint_tests.sql
--
-- Every statement below is meant to FAIL. Each one tries to store
-- something the business rules forbid, and the error message shows
-- which constraint stopped it. Run after 03_sample_data.sql.

\echo
\echo '1. Two customers with the same phone number (UNIQUE)'
INSERT INTO customer (full_name, phone) VALUES ('Duplicate Phone', '08000000201');

\echo
\echo '2. A customer listed as their own wearer twice (partial unique index)'
INSERT INTO wearer (customer_id, full_name, relationship)
SELECT customer_id, 'Ngozi Again', 'self' FROM customer WHERE phone = '08000000201';

\echo
\echo '3. An order due before it was placed (CHECK across two columns)'
INSERT INTO customer_order (customer_id, order_date, due_date, taken_by)
SELECT c.customer_id, DATE '2026-10-10', DATE '2026-10-01', s.staff_id
  FROM customer c, staff s
 WHERE c.phone = '08000000202' AND s.phone = '08000000002';

\echo
\echo '4. A ready-made line that names no product (CHECK on item kind)'
INSERT INTO order_item (order_id, item_kind, quantity, unit_price)
SELECT MIN(order_id), 'ready_made', 1, 40000 FROM customer_order;

\echo
\echo '5. Selling more fabric than is on the shelf (CHECK qty_on_hand >= 0)'
UPDATE material SET qty_on_hand = qty_on_hand - 1000 WHERE name = 'Indigo adire';

\echo
\echo '6. Cutting a garment for Ngozi from Femi''s measurements (composite foreign key)'
UPDATE garment_job
   SET measurement_set_id = (SELECT ms.measurement_set_id
                               FROM measurement_set ms
                               JOIN wearer w USING (wearer_id)
                              WHERE w.full_name = 'Femi Adeyemi')
 WHERE wearer_id = (SELECT wearer_id FROM wearer WHERE full_name = 'Ngozi Adeyemi');

\echo
\echo '7. The same tailor booked for two overlapping fittings (EXCLUDE)'
INSERT INTO fitting (job_id, staff_id, starts_at, ends_at)
SELECT job_id, staff_id, '2026-10-19 10:15+01', '2026-10-19 10:45+01'
  FROM fitting
 LIMIT 1;

\echo
\echo '8. A journal line that is both a debit and a credit (CHECK)'
INSERT INTO journal_line (entry_id, account_id, debit, credit)
SELECT MIN(e.entry_id), MIN(a.account_id), 100, 100
  FROM journal_entry e, account a;

\echo
\echo '9. A journal entry whose debits do not equal its credits'
\echo '   (deferred constraint trigger: the INSERTs succeed, the COMMIT fails)'
BEGIN;
WITH e AS (
    INSERT INTO journal_entry (description, posted_by)
    SELECT 'Unbalanced test entry', staff_id FROM staff WHERE phone = '08000000001'
    RETURNING entry_id
)
INSERT INTO journal_line (entry_id, account_id, debit, credit)
SELECT e.entry_id, a.account_id, v.debit, v.credit
  FROM e
  JOIN (VALUES ('1000', 5000.00, 0.00), ('4000', 0.00, 4000.00)) AS v (code, debit, credit) ON true
  JOIN account a ON a.code = v.code;
COMMIT;

\echo
\echo 'Nothing above was stored:'
SELECT (SELECT count(*) FROM customer)      AS customers,
       (SELECT count(*) FROM journal_entry) AS journal_entries,
       (SELECT qty_on_hand FROM material WHERE name = 'Indigo adire') AS adire_yards;
