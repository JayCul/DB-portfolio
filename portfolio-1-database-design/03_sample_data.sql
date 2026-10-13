-- Deeva's Designs: reference data and a small worked example
--
--   psql -U postgres -d deevas_designs -f 03_sample_data.sql
--
-- All names and phone numbers are made up. Portfolio 2 generates the
-- large data set used for performance testing.

BEGIN;

-- ---------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------

INSERT INTO staff (full_name, role, phone) VALUES
    ('Justin Nnaka',  'manager',    '08000000001'),
    ('Chidimma Nwabulue',  'front_desk', '08000000002'),
    ('Kofi Mensah',  'cutter',     '08000000003'),
    ('Zainab Yusuf', 'tailor',     '08000000004'),
    ('Chidi Eze',    'tailor',     '08000000005');

INSERT INTO garment_type (name) VALUES
    ('Agbada'), ('Kaftan'), ('Senator suit'), ('Shirt'),
    ('Trouser'), ('Dress'), ('Skirt'), ('Blouse'), ('Jacket'), ('Shorts');

INSERT INTO measurement_type (code, name) VALUES
    ('NECK',        'Neck'),
    ('SHOULDER',    'Shoulder width'),
    ('CHEST',       'Chest'),
    ('BUST',        'Bust'),
    ('WAIST',       'Waist'),
    ('HIP',         'Hip'),
    ('SLEEVE',      'Sleeve length'),
    ('BICEP',       'Round sleeve'),
    ('WRIST',       'Wrist'),
    ('TOP_LEN',     'Top length'),
    ('TROUSER_LEN', 'Trouser length'),
    ('THIGH',       'Thigh'),
    ('ANKLE',       'Ankle'),
    ('DRESS_LEN',   'Dress length'),
    ('SKIRT_LEN',   'Skirt length'),
    ('JACKET_LEN',  'Jacket length'),
    ('SHORTS_LEN',  'Shorts length');

INSERT INTO garment_type_measurement (garment_type_id, measurement_type_id)
SELECT g.garment_type_id, m.measurement_type_id
  FROM (VALUES
        ('Agbada', 'NECK'), ('Agbada', 'SHOULDER'), ('Agbada', 'CHEST'),
        ('Agbada', 'SLEEVE'), ('Agbada', 'TOP_LEN'),
        ('Kaftan', 'NECK'), ('Kaftan', 'SHOULDER'), ('Kaftan', 'CHEST'),
        ('Kaftan', 'SLEEVE'), ('Kaftan', 'BICEP'), ('Kaftan', 'TOP_LEN'),
        ('Senator suit', 'NECK'), ('Senator suit', 'SHOULDER'), ('Senator suit', 'CHEST'),
        ('Senator suit', 'SLEEVE'), ('Senator suit', 'TOP_LEN'), ('Senator suit', 'WAIST'),
        ('Senator suit', 'TROUSER_LEN'), ('Senator suit', 'THIGH'),
        ('Shirt', 'NECK'), ('Shirt', 'SHOULDER'), ('Shirt', 'CHEST'),
        ('Shirt', 'SLEEVE'), ('Shirt', 'WRIST'), ('Shirt', 'TOP_LEN'),
        ('Trouser', 'WAIST'), ('Trouser', 'HIP'), ('Trouser', 'THIGH'),
        ('Trouser', 'TROUSER_LEN'), ('Trouser', 'ANKLE'),
        ('Dress', 'SHOULDER'), ('Dress', 'BUST'), ('Dress', 'WAIST'),
        ('Dress', 'HIP'), ('Dress', 'DRESS_LEN'),
        ('Skirt', 'WAIST'), ('Skirt', 'HIP'), ('Skirt', 'SKIRT_LEN'),
        ('Blouse', 'SHOULDER'), ('Blouse', 'BUST'), ('Blouse', 'WAIST'),
        ('Blouse', 'SLEEVE'), ('Blouse', 'TOP_LEN'),
        ('Jacket', 'NECK'), ('Jacket', 'SHOULDER'), ('Jacket', 'CHEST'),
        ('Jacket', 'SLEEVE'), ('Jacket', 'JACKET_LEN'),
        ('Shorts', 'WAIST'), ('Shorts', 'HIP'), ('Shorts', 'SHORTS_LEN')
       ) AS v (garment, code)
  JOIN garment_type     g ON g.name = v.garment
  JOIN measurement_type m ON m.code = v.code;

INSERT INTO account (code, name, account_type) VALUES
    ('1000', 'Cash',                      'asset'),
    ('1010', 'Bank',                      'asset'),
    ('1200', 'Inventory - materials',     'asset'),
    ('1210', 'Inventory - ready-to-wear', 'asset'),
    ('2000', 'Customer deposits',         'liability'),
    ('2100', 'Accounts payable',          'liability'),
    ('3000', 'Owner''s equity',           'equity'),
    ('4000', 'Tailoring revenue',         'revenue'),
    ('4010', 'Ready-to-wear sales',       'revenue'),
    ('4020', 'Material sales',            'revenue'),
    ('4030', 'Alteration revenue',        'revenue'),
    ('5000', 'Cost of goods sold',        'expense'),
    ('6000', 'Wages',                     'expense'),
    ('6100', 'Rent',                      'expense'),
    ('6200', 'Utilities',                 'expense');

-- ---------------------------------------------------------------------
-- Catalogue and stock
-- ---------------------------------------------------------------------

INSERT INTO style (garment_type_id, name, description, base_price)
SELECT g.garment_type_id, v.name, v.description, v.base_price
  FROM (VALUES
        ('Kaftan', 'Classic kaftan',     'Straight cut, plain placket',      45000.00),
        ('Agbada', 'Three-piece agbada', 'Robe, tunic and trouser',         120000.00),
        ('Jacket', 'Classic jacket',     'Fitted, full-sleeved',             85000.00),
        ('Shorts', 'Classic shorts',     'Straight cut, elastic waistband',  32000.00),
        ('Dress',  'A-line dress',       'Knee length, fitted at the waist', 38000.00),
        ('Shirt',  'Button-down shirt',  'Long-sleeved, button-down front',  25000.00)
       ) AS v (garment, name, description, base_price)
  JOIN garment_type g ON g.name = v.garment;

INSERT INTO product_variant (style_id, sku, size_label, colour, unit_price, qty_on_hand, reorder_level)
SELECT s.style_id, v.sku, v.size_label, v.colour, v.unit_price, v.qty, 2
  FROM (VALUES
        ('Classic kaftan', 'KAF-CLS-M-IVY', 'M', 'Ivory', 40000.00, 6),
        ('Classic kaftan', 'KAF-CLS-L-BLK', 'L', 'Black', 40000.00, 4)
       ) AS v (style, sku, size_label, colour, unit_price, qty)
  JOIN style s ON s.name = v.style;

INSERT INTO supplier (name, phone, location) VALUES
    ('Kano Textile Traders', '08000000101', 'Kano'),
    ('Accra Wax Prints',     '08000000102', 'Accra');
    

INSERT INTO material (name, category, unit, sell_price, qty_on_hand, reorder_level) VALUES
    ('Ivory cotton brocade',   'fabric', 'yard', 6500.00, 60, 15),
    ('Indigo adire',           'fabric', 'yard', 5200.00, 35, 10),
    ('Black polyester lining', 'lining', 'yard', 1200.00, 80, 20),
    ('Gold embroidery thread', 'thread', 'roll',  900.00, 40, 10);

-- Opening stock arrives as purchases, so qty_on_hand is backed by the log.
INSERT INTO stock_movement (material_id, movement_type, quantity, unit_cost, supplier_id, recorded_by)
SELECT m.material_id, 'purchase', m.qty_on_hand, v.unit_cost, s.supplier_id,
       (SELECT staff_id FROM staff WHERE phone = '08000000001')
  FROM (VALUES
        ('Ivory cotton brocade',   4200.00, 'Kano Textile Traders'),
        ('Indigo adire',           3400.00, 'Accra Wax Prints'),
        ('Black polyester lining',  700.00, 'Kano Textile Traders'),
        ('Gold embroidery thread',  500.00, 'Kano Textile Traders')
       ) AS v (material, unit_cost, supplier)
  JOIN material m ON m.name = v.material
  JOIN supplier s ON s.name = v.supplier;

-- ---------------------------------------------------------------------
-- Customers, wearers and measurements
-- ---------------------------------------------------------------------

INSERT INTO customer (full_name, phone, email, customer_type) VALUES
    ('Ngozi Adeyemi',       '08000000201', 'ngozi@example.com',  'individual'),
    ('Samuel Ofori',        '08000000202', 'samuel@example.com', 'individual'),
    ('Bright Stitches Ltd', '08000000203', 'orders@example.com', 'trade');

INSERT INTO wearer (customer_id, full_name, relationship)
SELECT c.customer_id, v.full_name, v.relationship
  FROM (VALUES
        ('08000000201', 'Ngozi Adeyemi', 'self'),
        ('08000000201', 'Femi Adeyemi',  'spouse'),
        ('08000000201', 'Tobi Adeyemi',  'child'),
        ('08000000202', 'Samuel Ofori',  'self')
       ) AS v (phone, full_name, relationship)
  JOIN customer c ON c.phone = v.phone;

INSERT INTO measurement_set (wearer_id, taken_on, taken_by)
SELECT w.wearer_id, DATE '2026-10-05',
       (SELECT staff_id FROM staff WHERE phone = '08000000004')
  FROM wearer w
 WHERE w.full_name IN ('Ngozi Adeyemi', 'Femi Adeyemi');

INSERT INTO measurement_value (measurement_set_id, measurement_type_id, value_in)
SELECT ms.measurement_set_id, mt.measurement_type_id, v.value_in
  FROM (VALUES
        ('Ngozi Adeyemi', 'SHOULDER',  15.50),
        ('Ngozi Adeyemi', 'BUST',      37.00),
        ('Ngozi Adeyemi', 'WAIST',     31.00),
        ('Ngozi Adeyemi', 'HIP',       41.50),
        ('Ngozi Adeyemi', 'DRESS_LEN', 40.00),
        ('Femi Adeyemi',  'NECK',      16.50),
        ('Femi Adeyemi',  'SHOULDER',  19.00),
        ('Femi Adeyemi',  'CHEST',     42.00),
        ('Femi Adeyemi',  'SLEEVE',    25.50),
        ('Femi Adeyemi',  'BICEP',     15.00),
        ('Femi Adeyemi',  'TOP_LEN',   44.00)
       ) AS v (wearer, code, value_in)
  JOIN wearer           w  ON w.full_name = v.wearer
  JOIN measurement_set  ms ON ms.wearer_id = w.wearer_id
  JOIN measurement_type mt ON mt.code = v.code;

-- ---------------------------------------------------------------------
-- One order from start to deposit
-- ---------------------------------------------------------------------
-- Ngozi orders a kaftan for her husband, a dress for herself and three
-- yards of adire, and pays a 50,000 deposit by bank transfer.

DO $$
DECLARE
    v_front_desk integer := (SELECT staff_id FROM staff WHERE phone = '08000000002');
    v_cutter     integer := (SELECT staff_id FROM staff WHERE phone = '08000000003');
    v_tailor     integer := (SELECT staff_id FROM staff WHERE phone = '08000000004');
    v_ngozi      integer := (SELECT wearer_id FROM wearer WHERE full_name = 'Ngozi Adeyemi');
    v_femi       integer := (SELECT wearer_id FROM wearer WHERE full_name = 'Femi Adeyemi');
    v_adire      integer := (SELECT material_id FROM material WHERE name = 'Indigo adire');
    v_order      integer;
    v_item       integer;
    v_job        integer;
    v_entry      integer;
BEGIN
    INSERT INTO customer_order (customer_id, order_date, due_date, status, taken_by)
    SELECT customer_id, DATE '2026-10-05', DATE '2026-10-26', 'in_production', v_front_desk
      FROM customer WHERE phone = '08000000201'
    RETURNING order_id INTO v_order;

    -- bespoke kaftan for Femi
    INSERT INTO order_item (order_id, item_kind, description, quantity, unit_price)
    VALUES (v_order, 'bespoke', 'Classic kaftan in ivory brocade', 1, 45000.00)
    RETURNING order_item_id INTO v_item;

    INSERT INTO garment_job (order_item_id, wearer_id, garment_type_id, style_id,
                             measurement_set_id, job_status)
    SELECT v_item, v_femi, s.garment_type_id, s.style_id,
           (SELECT measurement_set_id FROM v_current_measurement WHERE wearer_id = v_femi),
           'cutting'
      FROM style s WHERE s.name = 'Classic kaftan'
    RETURNING job_id INTO v_job;

    INSERT INTO job_assignment (job_id, task, staff_id) VALUES
        (v_job, 'cutting', v_cutter),
        (v_job, 'sewing',  v_tailor);

    INSERT INTO fitting (job_id, staff_id, starts_at, ends_at)
    VALUES (v_job, v_tailor, '2026-10-19 10:00+01', '2026-10-19 10:30+01');

    -- bespoke dress for Ngozi
    INSERT INTO order_item (order_id, item_kind, description, quantity, unit_price)
    VALUES (v_order, 'bespoke', 'A-line dress in indigo adire', 1, 38000.00)
    RETURNING order_item_id INTO v_item;

    INSERT INTO garment_job (order_item_id, wearer_id, garment_type_id, style_id,
                             measurement_set_id)
    SELECT v_item, v_ngozi, s.garment_type_id, s.style_id,
           (SELECT measurement_set_id FROM v_current_measurement WHERE wearer_id = v_ngozi)
      FROM style s WHERE s.name = 'A-line dress';

    -- three yards of adire sold over the counter
    INSERT INTO order_item (order_id, item_kind, material_id, quantity, unit_price)
    VALUES (v_order, 'material', v_adire, 3, 5200.00)
    RETURNING order_item_id INTO v_item;

    INSERT INTO stock_movement (material_id, movement_type, quantity, order_item_id, recorded_by)
    VALUES (v_adire, 'sale', -3, v_item, v_front_desk);

    UPDATE material SET qty_on_hand = qty_on_hand - 3 WHERE material_id = v_adire;

    -- deposit: money in the bank, owed back to the customer as work
    -- until the garments are collected
    INSERT INTO journal_entry (entry_date, description, posted_by)
    VALUES (DATE '2026-10-05', 'Deposit on order ' || v_order, v_front_desk)
    RETURNING entry_id INTO v_entry;

    INSERT INTO journal_line (entry_id, account_id, debit, credit) VALUES
        (v_entry, (SELECT account_id FROM account WHERE code = '1010'), 50000.00, 0),
        (v_entry, (SELECT account_id FROM account WHERE code = '2000'), 0, 50000.00);

    INSERT INTO payment (order_id, paid_at, amount, method, payment_kind, reference,
                         received_by, journal_entry_id)
    VALUES (v_order, '2026-10-05 11:15+01', 50000.00, 'bank_transfer', 'deposit',
            'TRF-0001', v_front_desk, v_entry);
END;
$$;

COMMIT;
