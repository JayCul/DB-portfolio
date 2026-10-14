# Portfolio 4: NoSQL and Advanced Data Models

The Deeva's Designs data from Portfolios 1 to 3, remodelled as documents in MongoDB 8 and compared with the relational design.

## 1. Files

| File | Purpose |
|---|---|
| [docker-compose.yml](docker-compose.yml) | Runs MongoDB 8 in a container |
| [01_export_from_postgres.sql](01_export_from_postgres.sql) | Reshapes the PostgreSQL rows into JSON documents |
| [02_load.cmd](02_load.cmd) | Loads the documents with `mongoimport` |
| [03_validation.js](03_validation.js) | Attaches a JSON Schema to orders and tests it |
| [04_queries.js](04_queries.js) | Sample documents, queries before and after indexes, and writes |
| [results/](results/) | Output of the two scripts on my machine |
| [evidence/](evidence/) | Screenshots |

## 2. Why a document model

The relational design answers "show me this order" by joining more than a dozen tables: the order, its customer, its lines, each line's job, wearer, garment type, style and measurements, the tasks and fittings of each job, and the payments. That is the screen the front desk opens most often.

A document database stores that screen as one record. The question for this portfolio is which parts of Deeva's data are better off that way, and which are not.

## 3. The model

Three collections take the place of fourteen of the twenty-three tables.

| Collection | One document is | Replaces |
|---|---|---|
| `orders` | An order with its lines, jobs, tasks, fittings and payments | `customer_order`, `order_item`, `garment_job`, `job_assignment`, `fitting`, `payment` |
| `wearers` | A person, with every measurement set taken | `wearer`, `measurement_set`, `measurement_value`, `measurement_type` |
| `styles` | A design, with the measurements it needs and the sizes in stock | `style`, `garment_type`, `garment_type_measurement`, `product_variant` |

Customers and staff appear inside these documents as copied names, described below. The ledger, materials and stock movements are left in PostgreSQL, for the reasons in section 8.

### Embed or reference

| Data | Decision | Reason |
|---|---|---|
| Order lines, payments | Embedded in the order | Always read with the order, never exist without it, and there are only a few |
| Tasks and fittings | Embedded in the order line | Belong to one garment and are shown with it |
| Measurement sets | Embedded in the wearer, newest first | A wearer has a handful, and the cutter wants the latest |
| Measurements a garment was cut from | Copied into the order line | Must stay as they were on the day, even after the wearer is measured again |
| Customer on an order | Id, name and phone copied in | Lists of orders can show the customer without a second lookup |
| Staff | Name copied in | Shown wherever the work is shown |

Copying the customer's name into every order is deliberate redundancy, and it has a price: a customer who changes their phone number must be updated in every one of their orders and wearers. The relational design stores it once.

### Different kinds of line

In PostgreSQL the four kinds of order line share one table, with columns that are empty for most rows and a CHECK constraint to keep them consistent. In a document each line carries only its own fields: a bespoke line has a wearer, measurements, tasks and fittings; a material line has a material and a unit. The sample order in [results/queries.txt](results/queries.txt) shows both in one order.

## 4. How to run

Start MongoDB, export from PostgreSQL, and load:

```bash
docker compose up -d
```

```bash
psql -U postgres -d deevas_designs -f 01_export_from_postgres.sql
```

```bash
02_load.cmd
```

Run the two scripts, saving their output:

```bash
docker compose exec -T mongo mongosh --quiet deevas /work/03_validation.js > results\validation.txt
```

```bash
docker compose exec -T mongo mongosh --quiet deevas /work/04_queries.js > results\queries.txt
```

`02_load.cmd` drops and reloads every collection, so it also resets the database after the scripts have changed it. The exported files in `data/` are about 150 MB and are not committed.

## 5. Keeping structure without tables

MongoDB does not require documents in a collection to look alike, but it can be told to. [03_validation.js](03_validation.js) attaches a JSON Schema to `orders`: required fields, the allowed statuses, money stored as exact decimals, and a `oneOf` rule that makes each kind of line carry its own reference. That last rule is the document form of the CHECK constraint on `order_item`.

Every loaded order satisfies the schema. Four writes that break it are refused, and the output names the rule each one broke.

What the schema cannot do is look outside the document. Nothing stops an order naming a customer id that does not exist, because MongoDB has no foreign keys.

## 6. The Portfolio 2 questions again

Full output is in [results/queries.txt](results/queries.txt).

| Question | PostgreSQL | MongoDB |
|---|---|---|
| Q1: one customer's orders | Join of two tables, two indexes | One index on `customer.id`; 45 documents read, nothing else |
| Q2: a tailor's unfinished sewing | Five joins from `job_assignment` | One multikey index over the tasks inside the lines inside the orders |
| Q3: a wearer's latest measurements | Three tables and an index on wearer and date | One document fetched by `_id`, with no extra index |
| Q4: revenue for one month | Join of ledger tables, or a materialized view | Aggregation pipeline over order lines |
| Q5: finished orders owing money | Totals computed per order through indexes | The balance is stored on the order; one index returns the top 20 directly |

Three points stand out.

**Q3 needs nothing.** The measurements live in the wearer's document, so the primary key is the only index involved. This is the clearest gain of the document model for Deeva's.

**Q2 shows a multikey index.** `items.tasks.staff` is a path through two levels of arrays. MongoDB creates one index entry for every task of every line. The index is also partial: it covers only orders in production, so it is 44 kB against about 1 MB for each of the others.

**Q4 gives the same answer as the ledger.** Revenue for September 2026 by kind of line, computed here from order documents, equals the figures PostgreSQL computes from journal lines for the four revenue accounts. The two databases hold the same facts in different shapes.

Without indexes every query except Q3 reads every order document (`COLLSCAN`). An index matters as much here as it did in Portfolio 2.

## 7. Writing

**One document is one atomic write.** Taking the balance on an order adds a payment, changes `paid` and `balance` and moves the status, in a single update. In PostgreSQL the same event needed a transaction across several tables (Portfolio 3, scenario 1). Here no transaction is needed, because everything that changes is in one document.

**A guarded update replaces a lock.** Selling ready-to-wear stock puts the test `stock >= quantity` in the update's filter. If there is not enough, no document matches and nothing changes. This is the same idea as `SET qty_on_hand = qty_on_hand - n` with a CHECK constraint in Portfolio 3, scenario 4.

**Fields can be added to some documents only.** Two styles were given an `attributes` object with different fields in each, and a list of tags, while the other twelve were left alone. In PostgreSQL this would be new nullable columns or another table.

## 8. Suitability for Deeva's Designs

| Data | Suits documents? | Why |
|---|---|---|
| Catalogue of styles | Yes | Every garment type has different attributes, and the catalogue is read far more than it is written |
| Wearers and measurements | Yes | Read as a unit, by key, and different garments need different measurements |
| Orders | For reading, yes | The whole order is one read. But totals are stored and must be kept right by every write |
| Customers | No gain | Their details are copied into orders, so a change has to be applied in many places |
| Fittings | No | Double-booking a tailor is a rule across orders. PostgreSQL enforces it with one exclusion constraint. Fittings buried in separate order documents cannot be checked against each other |
| Material stock | No | A sale changes an order and a material together, which are two documents and so need a multi-document transaction |
| The ledger | No | Its rules span rows and tables: every line must name a real account, and reports join entries to accounts |

The document model is strongest where Deeva's reads a self-contained record by its key, and weakest where a rule has to hold across records. That lines up with what each database gave up to gain: MongoDB dropped joins and cross-document constraints in exchange for one-read access and a flexible shape.

For a business of this size the recommendation is to keep PostgreSQL as the system of record, because the accounting and the stock rules matter most and it enforces them. A document store earns its place if a customer-facing catalogue or order-tracking page is added later, fed from PostgreSQL by an export like the one in this portfolio.
