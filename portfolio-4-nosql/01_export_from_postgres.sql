-- Deeva's Designs: reshape PostgreSQL rows into MongoDB documents
--
-- Run from this folder:
--   psql -U postgres -d deevas_designs -f 01_export_from_postgres.sql
--
-- Writes one JSON document per line to data/wearers.json, data/orders.json
-- and data/styles.json. Each query gathers the rows that belong together
-- (an order with its lines, jobs, fittings and payments) into one document,
-- which is the work a join does at query time in the relational model.
--
-- Dates and money are written in MongoDB's Extended JSON, so that
-- mongoimport stores them as real dates and exact decimals, not strings.

\set ON_ERROR_STOP on
\encoding UTF8
\pset pager off

-- Helpers that exist only for this session. STRICT makes them return
-- NULL for NULL, and json_strip_nulls then leaves the field out.
CREATE FUNCTION pg_temp.mdate(d date) RETURNS json LANGUAGE sql IMMUTABLE STRICT AS
$$ SELECT json_build_object('$date', to_char(d, 'YYYY-MM-DD') || 'T00:00:00Z') $$;

CREATE FUNCTION pg_temp.mdate(t timestamptz) RETURNS json LANGUAGE sql IMMUTABLE STRICT AS
$$ SELECT json_build_object('$date', to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')) $$;

CREATE FUNCTION pg_temp.mmoney(n numeric) RETURNS json LANGUAGE sql IMMUTABLE STRICT AS
$$ SELECT json_build_object('$numberDecimal', n::text) $$;

\pset format unaligned
\pset tuples_only on


-- ---------------------------------------------------------------------
-- wearers: one document per person measured, with every measurement
-- set embedded, newest first
-- ---------------------------------------------------------------------
\echo 'Writing data/wearers.json'
\o data/wearers.json

WITH set_values AS (
    SELECT mv.measurement_set_id,
           json_object_agg(lower(mt.code), mv.value_in ORDER BY mt.code) AS vals
      FROM measurement_value mv
      JOIN measurement_type mt USING (measurement_type_id)
     GROUP BY mv.measurement_set_id
),
wearer_sets AS (
    SELECT ms.wearer_id,
           json_agg(json_build_object(
                        'takenOn', pg_temp.mdate(ms.taken_on),
                        'takenBy', s.full_name,
                        'values',  sv.vals)
                    ORDER BY ms.taken_on DESC, ms.measurement_set_id DESC) AS sets
      FROM measurement_set ms
      JOIN staff s ON s.staff_id = ms.taken_by
      LEFT JOIN set_values sv USING (measurement_set_id)
     GROUP BY ms.wearer_id
)
SELECT json_strip_nulls(json_build_object(
           '_id',          w.wearer_id,
           'name',         w.full_name,
           'relationship', w.relationship,
           'customer',     json_build_object('id', c.customer_id, 'name', c.full_name, 'phone', c.phone),
           'measurements', COALESCE(ws.sets, '[]'::json)))
  FROM wearer w
  JOIN customer c USING (customer_id)
  LEFT JOIN wearer_sets ws USING (wearer_id)
 ORDER BY w.wearer_id;


-- ---------------------------------------------------------------------
-- orders: one document per order. Lines are embedded, and each kind of
-- line carries only the fields that apply to it.
-- ---------------------------------------------------------------------
\o
\echo 'Writing data/orders.json'
\o data/orders.json

WITH set_values AS (
    SELECT mv.measurement_set_id,
           json_object_agg(lower(mt.code), mv.value_in ORDER BY mt.code) AS vals
      FROM measurement_value mv
      JOIN measurement_type mt USING (measurement_type_id)
     GROUP BY mv.measurement_set_id
),
tasks AS (
    SELECT ja.job_id,
           json_agg(json_build_object(
                        'task',        ja.task,
                        'staff',       s.full_name,
                        'assignedAt',  pg_temp.mdate(ja.assigned_at),
                        'completedAt', pg_temp.mdate(ja.completed_at))
                    ORDER BY ja.assigned_at) AS tasks
      FROM job_assignment ja
      JOIN staff s USING (staff_id)
     GROUP BY ja.job_id
),
fittings AS (
    SELECT f.job_id,
           json_agg(json_build_object(
                        'startsAt', pg_temp.mdate(f.starts_at),
                        'staff',    s.full_name,
                        'outcome',  f.outcome)
                    ORDER BY f.starts_at) AS fittings
      FROM fitting f
      JOIN staff s USING (staff_id)
     GROUP BY f.job_id
),
items AS (
    SELECT oi.order_id,
           json_agg(json_build_object(
                        'kind',        oi.item_kind,
                        'description', oi.description,
                        'quantity',    oi.quantity,
                        'unitPrice',   pg_temp.mmoney(oi.unit_price),
                        -- bespoke and alteration lines
                        'wearer',      CASE WHEN j.job_id IS NOT NULL
                                            THEN json_build_object('id', w.wearer_id, 'name', w.full_name) END,
                        'garment',     gt.name,
                        'style',       st.name,
                        'jobStatus',   j.job_status,
                        -- a copy of the measurements the garment was cut from
                        'measurements', sv.vals,
                        'tasks',       t.tasks,
                        'fittings',    f.fittings,
                        -- ready-to-wear lines
                        'sku',         pv.sku,
                        'size',        pv.size_label,
                        'colour',      pv.colour,
                        -- material lines
                        'material',    m.name,
                        'unit',        m.unit)
                    ORDER BY oi.order_item_id) AS items,
           round(sum(oi.quantity * oi.unit_price), 2) AS total
      FROM order_item oi
      LEFT JOIN garment_job j      USING (order_item_id)
      LEFT JOIN wearer w           ON w.wearer_id = j.wearer_id
      LEFT JOIN garment_type gt    ON gt.garment_type_id = j.garment_type_id
      LEFT JOIN style st           ON st.style_id = j.style_id
      LEFT JOIN set_values sv      ON sv.measurement_set_id = j.measurement_set_id
      LEFT JOIN tasks t            ON t.job_id = j.job_id
      LEFT JOIN fittings f         ON f.job_id = j.job_id
      LEFT JOIN product_variant pv ON pv.variant_id = oi.variant_id
      LEFT JOIN material m         ON m.material_id = oi.material_id
     GROUP BY oi.order_id
),
payments AS (
    SELECT p.order_id,
           json_agg(json_build_object(
                        'paidAt', pg_temp.mdate(p.paid_at),
                        'amount', pg_temp.mmoney(p.amount),
                        'method', p.method,
                        'kind',   p.payment_kind)
                    ORDER BY p.paid_at) AS payments,
           sum(CASE WHEN p.payment_kind = 'refund' THEN -p.amount ELSE p.amount END) AS paid
      FROM payment p
     GROUP BY p.order_id
)
SELECT json_strip_nulls(json_build_object(
           '_id',       o.order_id,
           'orderDate', pg_temp.mdate(o.order_date),
           'dueDate',   pg_temp.mdate(o.due_date),
           'status',    o.status,
           'customer',  json_build_object('id', c.customer_id, 'name', c.full_name, 'phone', c.phone),
           'takenBy',   s.full_name,
           'items',     COALESCE(i.items, '[]'::json),
           'payments',  COALESCE(p.payments, '[]'::json),
           -- totals are stored on the document and kept up to date by
           -- every write, because there is no view to compute them
           'total',     pg_temp.mmoney(COALESCE(i.total, 0)),
           'paid',      pg_temp.mmoney(COALESCE(p.paid, 0)),
           'balance',   pg_temp.mmoney(CASE WHEN o.status = 'cancelled' THEN 0
                                            ELSE COALESCE(i.total, 0) - COALESCE(p.paid, 0) END)))
  FROM customer_order o
  JOIN customer c USING (customer_id)
  JOIN staff s ON s.staff_id = o.taken_by
  LEFT JOIN items i    USING (order_id)
  LEFT JOIN payments p USING (order_id)
 ORDER BY o.order_id;


-- ---------------------------------------------------------------------
-- styles: the catalogue. Each style embeds the measurements its garment
-- needs and the ready-to-wear sizes held in stock.
-- ---------------------------------------------------------------------
\o
\echo 'Writing data/styles.json'
\o data/styles.json

SELECT json_strip_nulls(json_build_object(
           '_id',         st.style_id,
           'name',        st.name,
           'garmentType', gt.name,
           'description', st.description,
           'basePrice',   pg_temp.mmoney(st.base_price),
           'requiredMeasurements',
               (SELECT json_agg(lower(mt.code) ORDER BY mt.code)
                  FROM garment_type_measurement gm
                  JOIN measurement_type mt USING (measurement_type_id)
                 WHERE gm.garment_type_id = st.garment_type_id),
           'variants',
               (SELECT json_agg(json_build_object(
                                    'sku',    pv.sku,
                                    'size',   pv.size_label,
                                    'colour', pv.colour,
                                    'price',  pg_temp.mmoney(pv.unit_price),
                                    'stock',  pv.qty_on_hand)
                                ORDER BY pv.sku)
                  FROM product_variant pv
                 WHERE pv.style_id = st.style_id)))
  FROM style st
  JOIN garment_type gt USING (garment_type_id)
 ORDER BY st.style_id;

\o
\echo 'Done. Next: 02_load.cmd'
