# Advanced Database Portfolio

Continuous assessment portfolio for MIT 8103 Advanced Database Systems (2026/2027, first semester). One case study, Deeva's Designs, is carried through all five activities.

## Case study: Deeva's Designs

Deeva's Designs is a start-up tailoring business that is about to move from handwritten records to its first database. It makes clothing to each client's measurements, sells a small ready-to-wear range, alters garments clients already own, and supplies hard-to-source fabric and materials.

The full case study statement (users, data stored, key operations) is in [portfolio-1-database-design](portfolio-1-database-design/).

## The five activities

| Folder                                                                        | Activity                                                                  | Main result                                                                                                           |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| [portfolio-1-database-design](portfolio-1-database-design/)                   | ER diagram, 23-table schema, keys, constraints, normalisation             | Nine invalid writes rejected, including a double-booked tailor and an unbalanced journal entry                        |
| [portfolio-2-query-optimisation](portfolio-2-query-optimisation/)             | 100,000 projected orders, eight query plans before and after nine indexes | A rewrite that only works together with its indexes; a materialized view for the report indexes could not fix         |
| [portfolio-3-transactions-concurrency](portfolio-3-transactions-concurrency/) | Seven two-session scenarios                                               | A lost update with no error, two ways to prevent it, write skew stopped only at SERIALIZABLE, a deadlock and its cure |
| [portfolio-4-nosql](portfolio-4-nosql/)                                       | Orders, wearers and styles as MongoDB documents                           | Revenue matches the PostgreSQL ledger exactly; documents suit the catalogue and measurements, not the ledger          |
| [portfolio-5-distributed-cloud](portfolio-5-distributed-cloud/)               | PostgreSQL primary and streaming replica                                  | Stale reads, a write stalled by synchronous replication, failover with nothing lost                                   |

Each folder's README explains what was built, how to run it and what the results mean. Results captured on my machine are in each `results/` folder, and screenshots in each `evidence/` folder.

## Running everything

The activities build on one database, in this order:

1. Portfolio 1: create `deevas_designs` and load the schema, views and sample data.
2. Portfolio 2: run the data generator, then the benchmark.
3. Portfolio 3: run the scenarios. They work on two materials of their own and do not disturb the generated data.
4. Portfolio 4: start MongoDB in Docker, export from PostgreSQL and load.
5. Portfolio 5: run the demonstration. It builds its own two servers in Docker.

## Environment

- PostgreSQL 18.3 on Windows 11
- Docker Desktop, running MongoDB 8.0 (Portfolio 4) and PostgreSQL 18 (Portfolio 5)
- Python 3.13, standard library only, for the scenario and demonstration runners

## AI use declaration

Claude (Anthropic) was used to plan the work, draft the scripts and documentation, and diagnose errors. The case study, the business decisions, every run that produced the results and screenshots, and the individual reflection are my own. The full declaration, including how the output was checked, is in the LMS documentation.
