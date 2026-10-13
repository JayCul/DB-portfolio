-- Deeva's Designs: the queries under test
--
-- Each query answers a question someone at Deeva's would ask. EXPLAIN
-- (ANALYZE, BUFFERS) runs the query for real and reports the plan the
-- optimiser chose, the time taken and the number of 8 kB pages touched.
--
-- benchmark.sql runs this file before and after the indexes exist.
-- \qecho writes the headings into the same output file as the plans.

\qecho '-- Q1: Front desk - one customer''s orders and what each is worth'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, o.status,
       sum(oi.quantity * oi.unit_price) AS order_total
  FROM customer_order o
  JOIN order_item oi USING (order_id)
 WHERE o.customer_id = 1100
 GROUP BY o.order_id
 ORDER BY o.order_date DESC;

\qecho
\qecho '-- Q2: Workshop - a tailor''s unfinished sewing, most urgent first'
EXPLAIN (ANALYZE, BUFFERS)
SELECT j.job_id, j.job_status, o.due_date, w.full_name AS wearer, gt.name AS garment
  FROM job_assignment a
  JOIN garment_job j     USING (job_id)
  JOIN order_item oi     USING (order_item_id)
  JOIN customer_order o  USING (order_id)
  JOIN wearer w          USING (wearer_id)
  JOIN garment_type gt   USING (garment_type_id)
 WHERE a.staff_id = (SELECT staff_id FROM staff WHERE phone = '08090000005')
   AND a.task = 'sewing'
   AND a.completed_at IS NULL
 ORDER BY o.due_date
 LIMIT 20;

\qecho
\qecho '-- Q3: Cutting table - a wearer''s most recent measurements'
EXPLAIN (ANALYZE, BUFFERS)
SELECT mt.name, mv.value_in, ms.taken_on
  FROM measurement_set ms
  JOIN measurement_value mv USING (measurement_set_id)
  JOIN measurement_type mt  USING (measurement_type_id)
 WHERE ms.measurement_set_id = (SELECT measurement_set_id
                                  FROM measurement_set
                                 WHERE wearer_id = 5004
                                 ORDER BY taken_on DESC, measurement_set_id DESC
                                 LIMIT 1)
 ORDER BY mt.name;

\qecho
\qecho '-- Q4: Owner - revenue by account for one month'
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

\qecho
\qecho '-- Q5a: Front desk - finished orders still owing money (through the view)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.full_name, c.phone, b.order_id, b.balance_due
  FROM v_order_balance b
  JOIN customer c USING (customer_id)
 WHERE b.status = 'ready'
   AND b.balance_due > 0
 ORDER BY b.balance_due DESC
 LIMIT 20;

\qecho
\qecho '-- Q5b: The same question, rewritten to total only the orders that qualify'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.full_name, c.phone, o.order_id, i.order_total - p.amount_paid AS balance_due
  FROM customer_order o
  JOIN customer c USING (customer_id)
 CROSS JOIN LATERAL (SELECT COALESCE(sum(quantity * unit_price), 0) AS order_total
                       FROM order_item
                      WHERE order_id = o.order_id) i
 CROSS JOIN LATERAL (SELECT COALESCE(sum(CASE WHEN payment_kind = 'refund'
                                              THEN -amount ELSE amount END), 0) AS amount_paid
                       FROM payment
                      WHERE order_id = o.order_id) p
 WHERE o.status = 'ready'
   AND i.order_total - p.amount_paid > 0
 ORDER BY balance_due DESC
 LIMIT 20;

\qecho
\qecho '-- Q6: Front desk - find a customer from part of their name'
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, full_name, phone
  FROM customer
 WHERE full_name ILIKE '%kemi ade%';

\qecho
\qecho '-- Q7: Ledger - the check the balance trigger runs for every journal line'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COALESCE(sum(debit), 0) - COALESCE(sum(credit), 0)
  FROM journal_line
 WHERE entry_id = 150000;
