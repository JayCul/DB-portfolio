-- Deeva's Designs: views
--
-- Totals and balances are derived here instead of being stored, so they
-- can never disagree with the rows they are computed from.

-- What each order is worth, what has been paid, and what is still owed.
CREATE VIEW v_order_balance AS
SELECT o.order_id,
       o.customer_id,
       o.status,
       COALESCE(i.order_total, 0)                           AS order_total,
       COALESCE(p.amount_paid, 0)                           AS amount_paid,
       COALESCE(i.order_total, 0) - COALESCE(p.amount_paid, 0) AS balance_due
  FROM customer_order o
  LEFT JOIN (SELECT order_id,
                    ROUND(SUM(quantity * unit_price), 2) AS order_total
               FROM order_item
              GROUP BY order_id) i USING (order_id)
  LEFT JOIN (SELECT order_id,
                    SUM(CASE WHEN payment_kind = 'refund' THEN -amount ELSE amount END)
                        AS amount_paid
               FROM payment
              GROUP BY order_id) p USING (order_id);

-- The most recent measurement set for each wearer.
CREATE VIEW v_current_measurement AS
SELECT DISTINCT ON (ms.wearer_id)
       ms.wearer_id,
       ms.measurement_set_id,
       ms.taken_on
  FROM measurement_set ms
 ORDER BY ms.wearer_id, ms.taken_on DESC, ms.measurement_set_id DESC;

-- Trial balance: total debits and credits per account. The two grand
-- totals are equal whenever every journal entry is balanced.
CREATE VIEW v_trial_balance AS
SELECT a.code,
       a.name,
       a.account_type,
       COALESCE(SUM(jl.debit), 0)  AS total_debit,
       COALESCE(SUM(jl.credit), 0) AS total_credit
  FROM account a
  LEFT JOIN journal_line jl USING (account_id)
 GROUP BY a.account_id, a.code, a.name, a.account_type
 ORDER BY a.code;
