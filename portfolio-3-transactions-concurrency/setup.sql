-- Deeva's Designs: starting state for the Portfolio 3 scenarios
--
-- run_scenarios.py runs this before every scenario. It can also be run by
-- hand before working through a scenario in two terminals:
--   psql -U postgres -d deevas_designs -f setup.sql
--
-- Two materials are kept for these exercises, so the scenarios never
-- disturb the data used in Portfolio 2: a bolt of velvet with 20 yards
-- left and a lining with 30. Anything earlier runs left behind is removed.

BEGIN;

DELETE FROM payment
 WHERE order_id IN (SELECT order_id FROM customer_order WHERE notes = 'Portfolio 3 exercise');

DELETE FROM journal_entry
 WHERE description LIKE 'P3 exercise:%';

DELETE FROM stock_movement
 WHERE material_id IN (SELECT material_id FROM material
                        WHERE name IN ('Royal blue velvet', 'Silver satin lining'));

DELETE FROM customer_order
 WHERE notes = 'Portfolio 3 exercise';

INSERT INTO material (name, category, unit, sell_price, qty_on_hand, reorder_level) VALUES
    ('Royal blue velvet',   'fabric', 'yard', 8000.00, 20, 5),
    ('Silver satin lining', 'lining', 'yard', 1500.00, 30, 5)
ON CONFLICT (name) DO UPDATE SET qty_on_hand = EXCLUDED.qty_on_hand;

INSERT INTO stock_movement (material_id, movement_type, quantity, unit_cost, supplier_id, recorded_by)
SELECT m.material_id, 'purchase', m.qty_on_hand, round(m.sell_price * 0.6, 2),
       (SELECT min(supplier_id) FROM supplier),
       (SELECT staff_id FROM staff WHERE phone = '08000000001')
  FROM material m
 WHERE m.name IN ('Royal blue velvet', 'Silver satin lining');

COMMIT;
