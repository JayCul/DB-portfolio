# Portfolio 1: Database Design and Modelling

## 1. Case study

**Organisation.** Deeva's Designs is a start-up tailoring business. It makes clothing to each client's measurements, sells a small range of ready-to-wear pieces, alters garments clients already own, and supplies fabric and other materials that are hard to source.

**Nature of the system.** The business has no database yet. Orders, measurements and payments are kept by hand. This portfolio designs the first database for the business, so that it can be digitised.

**Users of the database.**

| User | What they do with it |
|---|---|
| Front desk | Register customers, take orders, record payments, book fittings |
| Tailors and cutters | Look up measurements, see the jobs assigned to them, update job status |
| Manager / owner | Track stock, record expenses, read the accounts |

**Major data stored.** Customers and the people they order for, body measurements, garment types and styles, ready-to-wear stock, materials and suppliers, orders and their lines, production jobs and fittings, payments, expenses and a double-entry ledger.

**Key operations.**

- Record a new set of measurements for a wearer and keep the old ones.
- Take an order that mixes made-to-measure garments, ready-to-wear items, alterations and fabric.
- Assign cutting and sewing to staff and book fittings without double-booking anyone.
- Take a deposit, then the balance, and post both to the ledger.
- Move stock in and out, and refuse a sale when there is not enough.
- Report what each customer owes and produce a trial balance.

## 2. Files

| File | Purpose |
|---|---|
| [er-diagram.md](er-diagram.md) | ER diagram (Mermaid, renders on GitHub) |
| [01_schema.sql](01_schema.sql) | The 23 tables, keys and constraints |
| [02_views.sql](02_views.sql) | Order balance, current measurements, trial balance |
| [03_sample_data.sql](03_sample_data.sql) | Reference data and one order worked from start to deposit |
| [04_constraint_tests.sql](04_constraint_tests.sql) | Nine inserts and updates that the constraints must reject |
| [evidence/](evidence/) | Screenshots and captured output |

## 3. How to run

```bash
createdb -U postgres deevas_designs
```

```bash
psql -U postgres -d deevas_designs -f 01_schema.sql -f 02_views.sql -f 03_sample_data.sql
```

```bash
psql -U postgres -d deevas_designs -f 04_constraint_tests.sql
```

Every statement in the last script is expected to fail. The final query shows that nothing was stored.

## 4. Design decisions

**The customer and the wearer are different entities.** The person who pays is often not the person who wears the garment: a parent orders for a child, or one person orders matching outfits for a group. `customer` holds who pays and `wearer` holds who is measured. A customer who orders for themselves has a wearer row with relationship `self`.

**Measurements are rows, not columns.** A trouser and a dress need different measurements, so a fixed column per measurement would leave most columns empty and would need a schema change for every new measurement. Instead `measurement_value` stores one row per measurement, grouped by `measurement_set`, which is one measuring session. Sets are never overwritten, so a job always points at the measurements it was cut from.

**One order, four kinds of line.** `order_item` carries what every line has (quantity and price). A CHECK constraint makes a ready-made line name a product, a material line name a material, and bespoke and alteration lines name neither. The workshop details of bespoke and alteration lines live in `garment_job`, one-to-one with the line.

**Totals are not stored.** An order's total and balance are computed by the view `v_order_balance`. Storing them would let them drift from the lines and payments.

**Accounting is double entry.** Every payment and expense points at a `journal_entry` whose `journal_line` rows must balance. Because `payment.journal_entry_id` is NOT NULL, a payment cannot be saved without its ledger posting.

## 5. Keys and constraints

| Rule in the business | How the database enforces it |
|---|---|
| No two customers share a phone number | `UNIQUE (phone)` |
| A customer is their own wearer at most once | Partial unique index on `wearer (customer_id) WHERE relationship = 'self'` |
| An order cannot be due before it was placed | `CHECK (due_date >= order_date)` |
| Each kind of order line carries the right reference | `CHECK` on `item_kind`, `variant_id`, `material_id` |
| Stock cannot go below zero | `CHECK (qty_on_hand >= 0)` |
| A stock movement is for a material or a product, never both | `CHECK (num_nonnulls(material_id, variant_id) = 1)` |
| A job is cut from its own wearer's measurements | Composite foreign key `(measurement_set_id, wearer_id)` |
| One task per job has one person responsible | Composite primary key `(job_id, task)` |
| Staff cannot hold two fittings at once | `EXCLUDE USING gist` on staff and time range |
| A journal line is a debit or a credit, not both | `CHECK ((debit = 0) <> (credit = 0))` |
| Debits equal credits in every journal entry | Deferred constraint trigger, checked at COMMIT |

All primary keys are identity columns. Natural keys that the business already uses (phone, SKU, account code, measurement code) are kept as UNIQUE constraints.

## 6. Normalisation

The starting point is a page of the order notebook, written as one wide record:

```
ORDER (order_no, order_date, customer_name, customer_phone,
       { wearer_name, garment, style, price,
         { measurement_name, inches },
         tailor_name },
       { payment_date, payment_amount },
       order_total, balance)
```

**First normal form.** The record has three repeating groups: garments per order, measurements per garment, and payments per order. Each becomes its own table with one value per column: `order_item`, `measurement_value` and `payment`.

**Second normal form.** In a table keyed by (order, line), the customer's name and phone depend on the order alone, not on the line. They move to `customer_order`. In `measurement_value`, keyed by (set, type), the date of measuring depends on the set alone, so it sits in `measurement_set`.

**Third normal form.** Some columns depend on a non-key column. The customer's name depends on the customer, not on the order, so it moves to `customer`. The measurement's display name depends on its code, so it moves to `measurement_type`. A style determines its garment type, so `style` holds that link. `order_total` and `balance` depend on other rows entirely, so they are removed and computed in a view.

**Where the design departs from this on purpose.**

- `material.qty_on_hand` and `product_variant.qty_on_hand` can be derived by summing `stock_movement`. They are stored so that a sale can lock and check one row. Portfolio 3 uses this for the concurrency exercise.
- `order_item.unit_price` repeats a price that also exists on the style or product. It is the price agreed on the day, and must not change when the catalogue price changes.
- `payment.amount` also appears in the journal lines. The payment is the source document and the journal is its posting.

## 7. Known limitations

- Nothing in the schema stops a `garment_job` being attached to a ready-made or material line. The application has to respect the item kind.
- A task can be assigned to any member of staff. The schema does not check that a cutter does the cutting.
- `qty_on_hand` is kept in step with `stock_movement` by doing both in one transaction, not by a trigger.

## 8. Evidence

Screenshots of the scripts running on my own PostgreSQL 18 server are in [evidence/](evidence/).
