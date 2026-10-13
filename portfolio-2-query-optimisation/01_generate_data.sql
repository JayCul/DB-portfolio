-- Deeva's Designs: generated data for performance testing
--
-- Run on a database that already has the Portfolio 1 schema, views and
-- sample data:
--   psql -U postgres -d deevas_designs -f 01_generate_data.sql
--
-- Deeva's Designs is a start-up, so it has no history of this size. The
-- data models about three years of projected trading, so that query
-- plans can be studied at a realistic scale. Every name is made up.
--
-- Method: for each kind of row, a staging table is built first with one
-- row per thing to create and its random numbers already drawn. The real
-- INSERT then reads the staging table. This keeps each random choice
-- fixed while several tables are filled from it.

\set ON_ERROR_STOP on
\set customers 20000
\set orders 100000
\set first_day '2023-10-01'
\set days 1105
\set asof '2026-10-12'

BEGIN;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM customer WHERE customer_id > 1000) THEN
        RAISE EXCEPTION 'generated data is already present; recreate the database first';
    END IF;
END;
$$;

SELECT setseed(0.42);

-- The balance trigger runs one query per journal line. That is right for
-- day-to-day postings but far too slow for a bulk load, so it is switched
-- off here and the same rule is checked once, in a single query, before
-- it is switched back on.
ALTER TABLE journal_line DISABLE TRIGGER journal_line_balanced;


-- ---------------------------------------------------------------------
-- A larger team and catalogue
-- ---------------------------------------------------------------------

INSERT INTO staff (full_name, role, phone, hired_on) VALUES
    ('Ifeoma Okeke',     'front_desk', '08090000001', :'first_day'),
    ('Yaw Boateng',      'front_desk', '08090000002', :'first_day'),
    ('Musa Danjuma',     'cutter',     '08090000003', :'first_day'),
    ('Efua Asante',      'cutter',     '08090000004', :'first_day'),
    ('Bola Akinwale',    'tailor',     '08090000005', :'first_day'),
    ('Kwame Owusu',      'tailor',     '08090000006', :'first_day'),
    ('Halima Sani',      'tailor',     '08090000007', :'first_day'),
    ('Emeka Obi',        'tailor',     '08090000008', :'first_day'),
    ('Abena Darko',      'tailor',     '08090000009', :'first_day'),
    ('Sola Ogunleye',    'tailor',     '08090000010', :'first_day'),
    ('Fatima Bello',     'finisher',   '08090000011', :'first_day'),
    ('Nana Agyeman',     'finisher',   '08090000012', :'first_day');

INSERT INTO style (garment_type_id, name, description, base_price)
SELECT g.garment_type_id, v.name, v.description, v.base_price
  FROM (VALUES
        ('Senator suit', 'Two-piece senator',   'Tunic and trouser, concealed placket', 65000.00),
        ('Trouser',      'Tapered trouser',     'Flat front, tapered leg',              22000.00),
        ('Skirt',        'Pencil skirt',        'Knee length, back vent',               20000.00),
        ('Blouse',       'Peplum blouse',       'Fitted bodice, flared hem',            24000.00),
        ('Kaftan',       'Embroidered kaftan',  'Chest embroidery, side slits',         60000.00),
        ('Dress',        'Wrap dress',          'Midi length, tie waist',               42000.00),
        ('Agbada',       'Grand agbada',        'Full embroidery, wide sleeves',       180000.00),
        ('Shirt',        'Short-sleeved shirt', 'Camp collar, straight hem',            18000.00)
       ) AS v (garment, name, description, base_price)
  JOIN garment_type g ON g.name = v.garment
    ON CONFLICT DO NOTHING;

INSERT INTO product_variant (style_id, sku, size_label, colour, unit_price, reorder_level)
SELECT s.style_id,
       'RTW-' || s.style_id || '-' || z.size_label || '-' || upper(left(c.colour, 3)),
       z.size_label, c.colour, round(s.base_price * 0.9, -2), 3
  FROM style s
 CROSS JOIN (VALUES ('S'), ('M'), ('L'), ('XL')) AS z (size_label)
 CROSS JOIN (VALUES ('Ivory'), ('Black'), ('Indigo')) AS c (colour)
    ON CONFLICT DO NOTHING;

INSERT INTO material (name, category, unit, sell_price, reorder_level)
SELECT c.colour || ' ' || f.fabric, 'fabric', 'yard', f.sell_price, 20
  FROM (VALUES
        ('wax print',  3500.00), ('aso-oke', 12000.00), ('lace',   9000.00),
        ('kente',     15000.00), ('linen',    4800.00), ('damask', 7000.00),
        ('wool blend', 14000.00), ('chiffon', 3000.00)
       ) AS f (fabric, sell_price)
 CROSS JOIN (VALUES ('Ivory'), ('Black'), ('Indigo'), ('Wine'), ('Emerald'), ('Gold')) AS c (colour)
    ON CONFLICT DO NOTHING;


-- ---------------------------------------------------------------------
-- Numbered lookups: "pick one at random" becomes a join on rn
-- ---------------------------------------------------------------------

CREATE TEMP TABLE _first ON COMMIT DROP AS
SELECT (row_number() OVER ())::int AS rn, name
  FROM unnest(ARRAY[
        'Ada', 'Bisi', 'Chika', 'Dayo', 'Ebere', 'Funke', 'Gbenga', 'Hauwa', 'Ife', 'Jide',
        'Kemi', 'Lanre', 'Mariam', 'Nkem', 'Obinna', 'Peju', 'Rahma', 'Segun', 'Temi', 'Uche',
        'Kwesi', 'Akosua', 'Kojo', 'Adwoa', 'Kwabena', 'Esi', 'Yaa', 'Kofi', 'Ama', 'Fiifi',
        'Aisha', 'Ibrahim', 'Zara', 'Sani', 'Amina', 'Tari', 'Ebi', 'Dami', 'Tolu', 'Wale'
       ]) AS name;

CREATE TEMP TABLE _last ON COMMIT DROP AS
SELECT (row_number() OVER ())::int AS rn, name
  FROM unnest(ARRAY[
        'Adeyemi', 'Okafor', 'Balogun', 'Nwosu', 'Eze', 'Bello', 'Okonkwo', 'Adebayo', 'Yusuf', 'Obi',
        'Mensah', 'Owusu', 'Boateng', 'Asante', 'Osei', 'Appiah', 'Agyeman', 'Darko', 'Ofori', 'Addo',
        'Ogunleye', 'Akinwale', 'Danjuma', 'Sani', 'Okeke', 'Nnamdi', 'Ibekwe', 'Lawal', 'Salami', 'Uzor',
        'Abubakar', 'Chukwu', 'Olawale', 'Ajayi', 'Onyeka', 'Etim', 'Bassey', 'Dike', 'Ojo', 'Amadi'
       ]) AS name;

CREATE TEMP TABLE _front    ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY staff_id))::int AS rn, staff_id FROM staff WHERE role = 'front_desk';
CREATE TEMP TABLE _cutter   ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY staff_id))::int AS rn, staff_id FROM staff WHERE role = 'cutter';
CREATE TEMP TABLE _tailor   ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY staff_id))::int AS rn, staff_id FROM staff WHERE role = 'tailor';
CREATE TEMP TABLE _style    ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY style_id))::int AS rn, style_id, garment_type_id, name, base_price FROM style;
CREATE TEMP TABLE _variant  ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY variant_id))::int AS rn, variant_id, unit_price FROM product_variant;
CREATE TEMP TABLE _material ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY material_id))::int AS rn, material_id, sell_price FROM material;
CREATE TEMP TABLE _supplier ON COMMIT DROP AS
SELECT (row_number() OVER (ORDER BY supplier_id))::int AS rn, supplier_id FROM supplier;


-- ---------------------------------------------------------------------
-- Customers and wearers
-- ---------------------------------------------------------------------

CREATE TEMP TABLE _cust ON COMMIT DROP AS
SELECT n, random() AS r_first, random() AS r_last, random() AS r_type,
       random() AS r_joined, random() AS r_extra
  FROM generate_series(1, :customers) AS n;

INSERT INTO customer (customer_id, full_name, phone, email, customer_type, created_at)
OVERRIDING SYSTEM VALUE
SELECT 1000 + c.n,
       f.name || ' ' || l.name,
       '0810' || lpad(c.n::text, 7, '0'),
       'customer' || c.n || '@example.com',
       CASE WHEN c.r_type < 0.05 THEN 'trade' ELSE 'individual' END,
       TIMESTAMPTZ :'first_day' + c.r_joined * :days * INTERVAL '1 day'
  FROM _cust c
  JOIN _first f ON f.rn = 1 + floor(c.r_first * (SELECT count(*) FROM _first))::int
  JOIN _last  l ON l.rn = 1 + floor(c.r_last  * (SELECT count(*) FROM _last))::int;

-- every customer can be measured themselves
INSERT INTO wearer (wearer_id, customer_id, full_name, relationship)
OVERRIDING SYSTEM VALUE
SELECT customer_id, customer_id, full_name, 'self'
  FROM customer
 WHERE customer_id > 1000;

-- and about half also order for one to three other people
CREATE TEMP TABLE _extra ON COMMIT DROP AS
SELECT c.n, g.k, random() AS r_first, random() AS r_rel
  FROM _cust c
 CROSS JOIN LATERAL generate_series(1, GREATEST(floor(c.r_extra * 6)::int - 2, 0)) AS g (k);

INSERT INTO wearer (wearer_id, customer_id, full_name, relationship)
OVERRIDING SYSTEM VALUE
SELECT 1000 + :customers + row_number() OVER (ORDER BY e.n, e.k),
       1000 + e.n,
       f.name || ' ' || split_part(c.full_name, ' ', 2),
       (ARRAY['spouse', 'child', 'child', 'relative', 'group_member', 'group_member'])
           [1 + floor(e.r_rel * 6)::int]
  FROM _extra e
  JOIN customer c ON c.customer_id = 1000 + e.n
  JOIN _first f   ON f.rn = 1 + floor(e.r_first * (SELECT count(*) FROM _first))::int;


-- ---------------------------------------------------------------------
-- Measurements: most wearers have one set, some have an older one too
-- ---------------------------------------------------------------------

CREATE TEMP TABLE _mset ON COMMIT DROP AS
SELECT (1000 + row_number() OVER (ORDER BY w.wearer_id, g.k))::int AS measurement_set_id,
       w.wearer_id, random() AS r_date, random() AS r_staff
  FROM wearer w
 CROSS JOIN LATERAL generate_series(
           1,
           CASE WHEN w.wearer_id % 10 >= 7 THEN 0      -- never measured
                WHEN w.wearer_id % 4 = 0   THEN 2
                ELSE 1 END) AS g (k)
 WHERE w.wearer_id > 1000;

INSERT INTO measurement_set (measurement_set_id, wearer_id, taken_on, taken_by)
OVERRIDING SYSTEM VALUE
SELECT s.measurement_set_id, s.wearer_id,
       DATE :'first_day' + floor(s.r_date * :days)::int,
       t.staff_id
  FROM _mset s
  JOIN _tailor t ON t.rn = 1 + floor(s.r_staff * (SELECT count(*) FROM _tailor))::int;

-- roughly half of the measurement types are recorded in each set
INSERT INTO measurement_value (measurement_set_id, measurement_type_id, value_in)
SELECT s.measurement_set_id, mt.measurement_type_id,
       round((10 + random() * 35)::numeric, 1)
  FROM _mset s
 CROSS JOIN measurement_type mt
 WHERE (s.measurement_set_id + mt.measurement_type_id) % 2 = 0;


-- ---------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------
-- Order numbers rise with the date, as they would in real use, and the
-- business grows: later months hold more orders than early ones. A few
-- customers order often and most order rarely. Orders older than 45 days
-- are finished; only recent ones are still open.

CREATE TEMP TABLE _ord ON COMMIT DROP AS
SELECT n, random() AS r_cust, random() AS r_status, random() AS r_due,
       random() AS r_staff, random() AS r_lines
  FROM generate_series(1, :orders) AS n;

INSERT INTO customer_order (order_id, customer_id, order_date, due_date, status, taken_by)
OVERRIDING SYSTEM VALUE
SELECT 1000 + o.n,
       1001 + floor(power(o.r_cust, 2) * :customers)::int,
       d.order_date,
       d.order_date + 7 + floor(o.r_due * 22)::int,
       CASE WHEN d.order_date < DATE :'asof' - 45 THEN
                CASE WHEN o.r_status < 0.04 THEN 'cancelled' ELSE 'collected' END
            ELSE
                CASE WHEN o.r_status < 0.03 THEN 'cancelled'
                     WHEN o.r_status < 0.25 THEN 'confirmed'
                     WHEN o.r_status < 0.65 THEN 'in_production'
                     WHEN o.r_status < 0.85 THEN 'ready'
                     ELSE 'collected' END
       END,
       f.staff_id
  FROM _ord o
 CROSS JOIN LATERAL (
           SELECT DATE :'first_day'
                  + floor(power(o.n::float8 / :orders, 0.6) * :days)::int AS order_date
       ) d
  JOIN _front f ON f.rn = 1 + floor(o.r_staff * (SELECT count(*) FROM _front))::int;

-- a customer's record starts on the day of their first order
UPDATE customer c
   SET created_at = f.first_order + TIME '09:00'
  FROM (SELECT customer_id, min(order_date) AS first_order
          FROM customer_order
         GROUP BY customer_id) f
 WHERE f.customer_id = c.customer_id
   AND c.customer_id > 1000;


-- ---------------------------------------------------------------------
-- Order lines: one to four per order
-- ---------------------------------------------------------------------

CREATE TEMP TABLE _line ON COMMIT DROP AS
SELECT (1000 + row_number() OVER (ORDER BY o.n, g.k))::int AS order_item_id,
       1000 + o.n AS order_id,
       random() AS r_kind, random() AS r_pick, random() AS r_qty, random() AS r_price,
       random() AS r_wearer, random() AS r_stage, random() AS r_cutter, random() AS r_tailor,
       random() AS r_fit, random() AS r_fitday, random() AS r_outcome
  FROM _ord o
 CROSS JOIN LATERAL generate_series(1, 1 + floor(o.r_lines * o.r_lines * 4)::int) AS g (k);

CREATE TEMP TABLE _item ON COMMIT DROP AS
SELECT l.*, k.kind, s.style_id, s.garment_type_id, v.variant_id, m.material_id,
       CASE k.kind WHEN 'bespoke'    THEN s.name
                   WHEN 'alteration' THEN 'Alteration: ' || lower(s.name)
       END AS description,
       CASE k.kind WHEN 'material'   THEN 1 + floor(l.r_qty * 22) / 2.0
                   WHEN 'ready_made' THEN 1 + floor(power(l.r_qty, 3) * 3)
                   ELSE 1
       END::numeric(10,2) AS quantity,
       CASE k.kind WHEN 'bespoke'    THEN round(s.base_price * (0.9 + l.r_price * 0.4)::numeric, -2)
                   WHEN 'alteration' THEN 3000 + floor(l.r_price * 25) * 500
                   WHEN 'ready_made' THEN v.unit_price
                   ELSE m.sell_price
       END::numeric(12,2) AS unit_price
  FROM _line l
 CROSS JOIN LATERAL (
           SELECT CASE WHEN l.r_kind < 0.55 THEN 'bespoke'
                       WHEN l.r_kind < 0.65 THEN 'alteration'
                       WHEN l.r_kind < 0.85 THEN 'ready_made'
                       ELSE 'material' END AS kind
       ) k
  LEFT JOIN _style s
         ON k.kind IN ('bespoke', 'alteration')
        AND s.rn = 1 + floor(l.r_pick * (SELECT count(*) FROM _style))::int
  LEFT JOIN _variant v
         ON k.kind = 'ready_made'
        AND v.rn = 1 + floor(l.r_pick * (SELECT count(*) FROM _variant))::int
  LEFT JOIN _material m
         ON k.kind = 'material'
        AND m.rn = 1 + floor(l.r_pick * (SELECT count(*) FROM _material))::int;

INSERT INTO order_item (order_item_id, order_id, item_kind, variant_id, material_id,
                        description, quantity, unit_price)
OVERRIDING SYSTEM VALUE
SELECT order_item_id, order_id, kind, variant_id, material_id, description, quantity, unit_price
  FROM _item;


-- ---------------------------------------------------------------------
-- Production: a job for every bespoke and alteration line
-- ---------------------------------------------------------------------

-- each customer's wearers, numbered, so a line can pick one of them
CREATE TEMP TABLE _cw ON COMMIT DROP AS
SELECT customer_id, wearer_id,
       (row_number() OVER (PARTITION BY customer_id ORDER BY wearer_id))::int AS rn,
       (count(*)     OVER (PARTITION BY customer_id))::int                    AS cnt
  FROM wearer;

CREATE TEMP TABLE _job ON COMMIT DROP AS
SELECT (1000 + row_number() OVER (ORDER BY i.order_item_id))::int AS job_id,
       i.order_item_id, i.kind, i.style_id, i.garment_type_id,
       cw.wearer_id, cm.measurement_set_id,
       o.order_date, o.due_date,
       CASE o.status WHEN 'collected' THEN 'done'
                     WHEN 'ready'     THEN 'done'
                     WHEN 'cancelled' THEN 'cancelled'
                     WHEN 'confirmed' THEN 'queued'
                     ELSE (ARRAY['cutting', 'sewing', 'sewing', 'fitting', 'finishing'])
                              [1 + floor(i.r_stage * 5)::int]
       END AS job_status,
       c.staff_id AS cutter_id, t.staff_id AS tailor_id,
       i.r_fit, i.r_fitday, i.r_outcome
  FROM _item i
  JOIN customer_order o USING (order_id)
  JOIN _cw cw ON cw.customer_id = o.customer_id
             AND cw.rn = 1 + floor(i.r_wearer * cw.cnt)::int
  LEFT JOIN v_current_measurement cm ON cm.wearer_id = cw.wearer_id
  JOIN _cutter c ON c.rn = 1 + floor(i.r_cutter * (SELECT count(*) FROM _cutter))::int
  JOIN _tailor t ON t.rn = 1 + floor(i.r_tailor * (SELECT count(*) FROM _tailor))::int
 WHERE i.kind IN ('bespoke', 'alteration');

INSERT INTO garment_job (job_id, order_item_id, wearer_id, garment_type_id, style_id,
                         measurement_set_id, job_status)
OVERRIDING SYSTEM VALUE
SELECT job_id, order_item_id, wearer_id, garment_type_id,
       CASE WHEN kind = 'bespoke' THEN style_id END,
       CASE WHEN kind = 'bespoke' THEN measurement_set_id END,
       job_status
  FROM _job;

INSERT INTO job_assignment (job_id, task, staff_id, assigned_at, completed_at)
SELECT job_id, 'cutting', cutter_id,
       order_date + TIME '09:00',
       CASE WHEN job_status <> 'cutting' THEN order_date + 2 + TIME '16:00' END
  FROM _job
 WHERE job_status NOT IN ('queued', 'cancelled')
UNION ALL
SELECT job_id, 'sewing', tailor_id,
       order_date + 2 + TIME '16:00',
       CASE WHEN job_status IN ('finishing', 'done') THEN due_date - 1 + TIME '15:00' END
  FROM _job
 WHERE job_status IN ('sewing', 'fitting', 'finishing', 'done');

-- About half of the bespoke jobs that reached the fitting stage have a
-- fitting on record. Each tailor's fittings on a day are laid out in
-- half-hour slots from 08:30, so none can overlap, and any that would
-- clash with a fitting already in the table are left out.
INSERT INTO fitting (job_id, staff_id, starts_at, ends_at, outcome)
SELECT x.job_id, x.staff_id, x.starts_at, x.starts_at + INTERVAL '30 minutes',
       CASE WHEN x.fit_date >= DATE :'asof' THEN 'scheduled'
            WHEN x.r_outcome < 0.80 THEN 'approved'
            WHEN x.r_outcome < 0.95 THEN 'adjust'
            ELSE 'no_show' END
  FROM (SELECT j.job_id, j.tailor_id AS staff_id, d.fit_date, j.r_outcome,
               (d.fit_date + TIME '08:30'
                + (row_number() OVER (PARTITION BY j.tailor_id, d.fit_date ORDER BY j.job_id) - 1)
                  * INTERVAL '30 minutes') AT TIME ZONE 'Africa/Lagos' AS starts_at,
               row_number() OVER (PARTITION BY j.tailor_id, d.fit_date ORDER BY j.job_id) AS slot
          FROM _job j
         CROSS JOIN LATERAL (SELECT j.order_date + 5 + floor(j.r_fitday * 8)::int AS fit_date) d
         WHERE j.kind = 'bespoke'
           AND j.job_status IN ('fitting', 'finishing', 'done')
           AND j.r_fit < 0.5) x
 WHERE x.slot <= 18
   AND NOT EXISTS (SELECT 1
                     FROM fitting f
                    WHERE f.staff_id = x.staff_id
                      AND tstzrange(f.starts_at, f.ends_at)
                          && tstzrange(x.starts_at, x.starts_at + INTERVAL '30 minutes'));


-- ---------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------

INSERT INTO stock_movement (material_id, variant_id, movement_type, quantity,
                            order_item_id, recorded_by, moved_at)
SELECT i.material_id, i.variant_id, 'sale', -i.quantity, i.order_item_id,
       o.taken_by, o.order_date + TIME '12:00'
  FROM _item i
  JOIN customer_order o USING (order_id)
 WHERE i.kind IN ('ready_made', 'material')
   AND o.status <> 'cancelled';

-- opening stock large enough to cover everything sold, plus a remainder
INSERT INTO stock_movement (material_id, movement_type, quantity, unit_cost,
                            supplier_id, recorded_by, moved_at)
SELECT m.material_id, 'purchase',
       COALESCE(sold.qty, 0) + 20 + floor(random() * 60),
       round(m.sell_price * 0.6, 2),
       s.supplier_id,
       (SELECT min(staff_id) FROM staff WHERE role = 'manager'),
       TIMESTAMPTZ :'first_day'
  FROM material m
  LEFT JOIN (SELECT material_id, -sum(quantity) AS qty
               FROM stock_movement
              WHERE movement_type = 'sale' AND material_id IS NOT NULL
              GROUP BY material_id) sold USING (material_id)
  JOIN _supplier s ON s.rn = 1 + m.material_id % (SELECT count(*) FROM _supplier)::int;

INSERT INTO stock_movement (variant_id, movement_type, quantity, recorded_by, moved_at)
SELECT v.variant_id, 'production',
       COALESCE(sold.qty, 0) + 2 + floor(random() * 10),
       (SELECT min(staff_id) FROM staff WHERE role = 'manager'),
       TIMESTAMPTZ :'first_day'
  FROM product_variant v
  LEFT JOIN (SELECT variant_id, -sum(quantity) AS qty
               FROM stock_movement
              WHERE movement_type = 'sale' AND variant_id IS NOT NULL
              GROUP BY variant_id) sold USING (variant_id);

-- quantity on hand is whatever the movement log adds up to
UPDATE material m
   SET qty_on_hand = t.qty
  FROM (SELECT material_id, sum(quantity) AS qty
          FROM stock_movement WHERE material_id IS NOT NULL
         GROUP BY material_id) t
 WHERE t.material_id = m.material_id;

UPDATE product_variant v
   SET qty_on_hand = t.qty
  FROM (SELECT variant_id, sum(quantity) AS qty
          FROM stock_movement WHERE variant_id IS NOT NULL
         GROUP BY variant_id) t
 WHERE t.variant_id = v.variant_id;


-- ---------------------------------------------------------------------
-- Payments, expenses and the ledger
-- ---------------------------------------------------------------------

-- revenue of each order, split by the account it belongs to
CREATE TEMP TABLE _rev ON COMMIT DROP AS
SELECT order_id,
       CASE kind WHEN 'bespoke'    THEN '4000'
                 WHEN 'ready_made' THEN '4010'
                 WHEN 'material'   THEN '4020'
                 ELSE '4030' END AS code,
       round(sum(quantity * unit_price), 2) AS amount
  FROM _item
 GROUP BY 1, 2;

CREATE TEMP TABLE _total ON COMMIT DROP AS
SELECT order_id, sum(amount) AS total FROM _rev GROUP BY order_id;

-- Every order that was not cancelled has a deposit: half the total, or
-- all of it when the order is small. Collected orders also have the
-- balance, paid on the due date.
CREATE TEMP TABLE _pay ON COMMIT DROP AS
SELECT p.*, random() AS r_method
  FROM (SELECT o.order_id, 'deposit' AS src, o.order_date AS entry_date,
               d.deposit AS amount, o.taken_by AS staff_id
          FROM customer_order o
          JOIN _total t USING (order_id)
         CROSS JOIN LATERAL (SELECT CASE WHEN t.total <= 10000 THEN t.total
                                         ELSE round(t.total * 0.5, -2) END AS deposit) d
         WHERE o.status <> 'cancelled'
        UNION ALL
        SELECT o.order_id, 'balance', LEAST(o.due_date, DATE :'asof'),
               t.total - d.deposit, o.taken_by
          FROM customer_order o
          JOIN _total t USING (order_id)
         CROSS JOIN LATERAL (SELECT CASE WHEN t.total <= 10000 THEN t.total
                                         ELSE round(t.total * 0.5, -2) END AS deposit) d
         WHERE o.status = 'collected'
           AND t.total - d.deposit > 0) p;

-- Every journal entry to be written, numbered in date order: payments,
-- the revenue recognised when an order is collected, and monthly costs.
CREATE TEMP TABLE _entry ON COMMIT DROP AS
SELECT (1000 + row_number() OVER (ORDER BY e.entry_date, e.src, e.order_id))::int AS entry_id, e.*
  FROM (SELECT src, order_id, entry_date, amount, staff_id,
               CASE WHEN r_method < 0.30 THEN 'cash'
                    WHEN r_method < 0.75 THEN 'bank_transfer'
                    WHEN r_method < 0.95 THEN 'pos'
                    ELSE 'mobile_money' END AS method
          FROM _pay
        UNION ALL
        SELECT 'revenue', o.order_id, LEAST(o.due_date, DATE :'asof'), t.total, o.taken_by, NULL
          FROM customer_order o
          JOIN _total t USING (order_id)
         WHERE o.status = 'collected'
        UNION ALL
        SELECT c.src, NULL, (m.month_start + INTERVAL '27 days')::date, c.amount,
               (SELECT min(staff_id) FROM staff WHERE role = 'manager'), NULL
          FROM generate_series(DATE :'first_day', DATE :'asof' - 30, INTERVAL '1 month') AS m (month_start)
         CROSS JOIN (VALUES ('rent', 250000.00), ('wages', 900000.00), ('utilities', 60000.00))
                    AS c (src, amount)) e;

-- Entries and their lines are written in entry order, which is date
-- order. A real ledger fills up the same way, one day after another, and
-- the block-range index in this portfolio depends on it.
INSERT INTO journal_entry (entry_id, entry_date, description, posted_by, created_at)
OVERRIDING SYSTEM VALUE
SELECT entry_id, entry_date,
       CASE src WHEN 'deposit' THEN 'Deposit on order ' || order_id
                WHEN 'balance' THEN 'Balance on order ' || order_id
                WHEN 'revenue' THEN 'Revenue recognised on order ' || order_id
                ELSE initcap(src) || ' for ' || to_char(entry_date, 'Mon YYYY') END,
       staff_id,
       entry_date + TIME '17:00'
  FROM _entry
 ORDER BY entry_id;

INSERT INTO journal_line (entry_id, account_id, debit, credit)
SELECT l.entry_id, a.account_id, l.debit, l.credit
  FROM (-- money received: debit cash or bank, credit customer deposits
        SELECT entry_id, CASE WHEN method = 'cash' THEN '1000' ELSE '1010' END AS code,
               amount AS debit, 0 AS credit
          FROM _entry WHERE src IN ('deposit', 'balance')
        UNION ALL
        SELECT entry_id, '2000', 0, amount
          FROM _entry WHERE src IN ('deposit', 'balance')
        -- order collected: the deposit stops being owed and becomes revenue
        UNION ALL
        SELECT entry_id, '2000', amount, 0
          FROM _entry WHERE src = 'revenue'
        UNION ALL
        SELECT e.entry_id, r.code, 0, r.amount
          FROM _entry e JOIN _rev r USING (order_id) WHERE e.src = 'revenue'
        -- monthly costs: debit the expense, credit the bank
        UNION ALL
        SELECT entry_id, CASE src WHEN 'rent' THEN '6100' WHEN 'wages' THEN '6000' ELSE '6200' END,
               amount, 0
          FROM _entry WHERE src IN ('rent', 'wages', 'utilities')
        UNION ALL
        SELECT entry_id, '1010', 0, amount
          FROM _entry WHERE src IN ('rent', 'wages', 'utilities')) l
  JOIN account a ON a.code = l.code
 ORDER BY l.entry_id, l.debit DESC;

INSERT INTO payment (order_id, paid_at, amount, method, payment_kind, reference,
                     received_by, journal_entry_id)
SELECT order_id, entry_date + TIME '11:00', amount, method, src, 'GEN-' || entry_id,
       staff_id, entry_id
  FROM _entry
 WHERE src IN ('deposit', 'balance');

INSERT INTO expense (incurred_on, payee, description, amount, recorded_by, journal_entry_id)
SELECT entry_date,
       CASE src WHEN 'rent' THEN 'Landlord' WHEN 'wages' THEN 'Staff payroll' ELSE 'Power and water' END,
       initcap(src) || ' for ' || to_char(entry_date, 'Mon YYYY'),
       amount, staff_id, entry_id
  FROM _entry
 WHERE src IN ('rent', 'wages', 'utilities');


-- ---------------------------------------------------------------------
-- Finish
-- ---------------------------------------------------------------------

-- the rule the trigger enforces, checked for the whole load in one pass
DO $$
DECLARE
    v_unbalanced integer;
BEGIN
    SELECT count(*) INTO v_unbalanced
      FROM (SELECT entry_id
              FROM journal_line
             GROUP BY entry_id
            HAVING sum(debit) <> sum(credit)) u;
    IF v_unbalanced > 0 THEN
        RAISE EXCEPTION '% generated journal entries do not balance', v_unbalanced;
    END IF;
END;
$$;

ALTER TABLE journal_line ENABLE TRIGGER journal_line_balanced;

-- rows were inserted with explicit ids, so move every identity sequence
-- past the highest id in its table
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN SELECT table_name, column_name
               FROM information_schema.columns
              WHERE table_schema = 'public' AND is_identity = 'YES'
    LOOP
        EXECUTE format(
            'SELECT setval(pg_get_serial_sequence(%L, %L), (SELECT COALESCE(max(%I), 1) FROM %I))',
            r.table_name, r.column_name, r.column_name, r.table_name);
    END LOOP;
END;
$$;

COMMIT;

-- fresh statistics, so the planner knows the new table sizes
VACUUM (ANALYZE);

SELECT relname AS table_name, n_live_tup AS rows,
       pg_size_pretty(pg_total_relation_size(relid)) AS size_with_indexes
  FROM pg_stat_user_tables
 ORDER BY n_live_tup DESC;
