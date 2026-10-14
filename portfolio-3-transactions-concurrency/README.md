# Portfolio 3: Transactions and Concurrency

Seven scenarios from Deeva's Designs, each run in two database sessions at once. They cover commit, rollback, savepoints, three isolation levels, two concurrency problems and the mechanisms that prevent them.

## 1. Files

| File | Purpose |
|---|---|
| [scenarios/](scenarios/) | The seven scenarios, each a script for sessions A and B |
| [run_scenarios.py](run_scenarios.py) | Opens two psql connections and plays a scenario, statement by statement |
| [setup.sql](setup.sql) | Resets the two test materials before each scenario |
| [session_vars.sql](session_vars.sql) | Gives the test rows names such as `:velvet` |
| [results/](results/) | The log of each scenario, captured on my machine |
| [evidence/](evidence/) | Screenshots of scenarios worked by hand in two terminals |

## 2. The setting

All scenarios use two materials kept for this purpose: **Royal blue velvet**, with 20 yards on the shelf, and **Silver satin lining**, with 30. `setup.sql` puts them back to those figures before every scenario, so the scenarios do not disturb the Portfolio 2 data.

Stock is recorded twice, as in Portfolio 1: `material.qty_on_hand` is the shelf count, and `stock_movement` is the log it should add up to. Several scenarios show the two going out of step.

## 3. How to run

The runner starts psql without a password prompt, so the password is set in the terminal first (Command Prompt shown):

```bash
set PGPASSWORD=your-postgres-password
```

```bash
python run_scenarios.py
```

One scenario can be run on its own by giving the start of its file name, for example `python run_scenarios.py 07`.

The runner sends each statement to the session it is written for and waits for the reply. If no reply comes within 2.5 seconds, the session is waiting on a lock: the log records that and the script carries on in the other session, as a second person at a second terminal would.

### By hand

Any scenario can be followed in two terminals. Run `setup.sql` once, start psql in each terminal, and load the names:

```
\i session_vars.sql
```

Then type the `A:` statements in one terminal and the `B:` statements in the other, in the order they appear in the scenario file.

## 4. The scenarios

| # | Scenario | What happens | Concept |
|---|---|---|---|
| 1 | [A sale is committed](scenarios/01_commit.txt) | Six statements across five tables. Session B sees none of it until COMMIT, then all of it. | Atomicity, no dirty reads |
| 2 | [Rollback](scenarios/02_rollback.txt) | A failed stock update undoes the order written before it. A savepoint keeps one order line while undoing another. An unbalanced journal entry fails at COMMIT. | Rollback, savepoints, deferred constraints |
| 3 | [Lost update](scenarios/03_lost_update.txt) | Two sessions each sell 12 yards from a bolt of 20. Both succeed. The shelf says 8 and the log says -4. | The problem |
| 4 | [Row locks](scenarios/04_row_locks.txt) | With `SELECT ... FOR UPDATE` the second session waits and then reads 8. With `SET qty = qty - 6` the second session waits and is then stopped by the CHECK constraint. | Pessimistic locking, atomic update |
| 5 | [Isolation levels](scenarios/05_isolation_levels.txt) | At READ COMMITTED a report reads 20, then 15, in one transaction. At REPEATABLE READ it reads 15 both times. A REPEATABLE READ update on a row changed by someone else is refused. | Non-repeatable read, snapshots, serialization failure |
| 6 | [Write skew](scenarios/06_write_skew.txt) | Two sessions each check the log and insert a reservation for 15 yards. Both commit, leaving -10. At SERIALIZABLE the second commit is refused. | Write skew, serializable snapshot isolation |
| 7 | [Deadlock](scenarios/07_deadlock.txt) | Two sessions lock velvet and lining in opposite order. PostgreSQL cancels one. Locking in the same order avoids it. | Deadlock detection and prevention |

## 5. What the scenarios show

### Atomicity is what makes a sale one event

Recording a sale touches the order, its line, the movement log, the shelf count, the ledger and the payment. Scenario 1 shows these becoming visible together. Scenario 2 shows them disappearing together: when the stock update failed, the order and line that had already been inserted were removed too. Without a transaction, Deeva's would be left with an order for fabric it never handed over.

### An error ends the transaction, unless there is a savepoint

After the first error in scenario 2, PostgreSQL answered every further statement with `current transaction is aborted` and answered COMMIT with ROLLBACK. This is deliberate: it will not commit half of something. A savepoint marks a point to return to, so in part 2 the lining was sold even though the velvet line failed.

### Some rules can only be checked at COMMIT

The two lines of a journal entry are inserted one after the other, so between them the entry is always unbalanced. The trigger from Portfolio 1 is deferred to COMMIT for that reason. Part 3 of scenario 2 shows both inserts accepted and the COMMIT refused.

### The lost update gives no warning

In scenario 3 neither session received an error. Each read 20, and each wrote 8. The second write replaced the first. The damage only shows when the shelf count is compared with the log. This is the most likely concurrency fault at Deeva's, because it needs nothing unusual: two members of staff selling the same fabric at the same time.

### Two ways to prevent it

Scenario 4 fixes the same sale twice.

- `SELECT ... FOR UPDATE` locks the row when it is read. The second session waited, then read 8 in place of 20. This suits a program that must look at the value and decide what to do.
- `UPDATE ... SET qty_on_hand = qty_on_hand - 6` leaves the arithmetic to the database. The second session waited, ran against the new value, and was stopped by the CHECK constraint. No explicit lock is needed and there is no gap between reading and writing.

For Deeva's the second form is the default: it is shorter, and the constraint protects the stock even if a program forgets to check.

### Isolation levels trade consistency for retries

| Level | What a transaction sees | What can go wrong | Cost |
|---|---|---|---|
| READ COMMITTED (default) | Each statement sees what was committed when it started | Non-repeatable reads, lost updates, write skew | None |
| REPEATABLE READ | One snapshot for the whole transaction | Write skew | An update can fail and must be retried |
| SERIALIZABLE | As if transactions ran one at a time | None of these | More transactions fail and must be retried |

Scenario 5 shows the first two rows. The owner's report gave two different answers at READ COMMITTED and one answer at REPEATABLE READ, and the sale in session B was never blocked: PostgreSQL keeps old row versions, so readers do not wait for writers. The cost came in part 3, where a REPEATABLE READ update was refused with `could not serialize access due to concurrent update` and succeeded on the second attempt.

### Write skew needs SERIALIZABLE

In scenario 6 the two sessions never touched the same row. Each read the log and inserted a new row, so there was nothing for a row lock to wait on, and no CHECK constraint can look at a total. At READ COMMITTED both committed and 30 yards were reserved from 20. At SERIALIZABLE PostgreSQL noticed that each transaction had read data the other then changed, and refused the second commit. The program retried, read 5 yards, and could act on the truth.

### Deadlock is a design fault, not a database fault

In scenario 7 each session held one material and wanted the other. PostgreSQL waited one second, found the cycle and cancelled one transaction. It recovered, but one order had to be started again. In part 2 both sessions took the materials in the same order, lowest `material_id` first. The second session waited briefly and both orders went through. A fixed locking order makes a cycle impossible.

## 6. What this means for Deeva's

1. Every sale, payment and stock change runs inside one transaction.
2. Stock is changed with `qty_on_hand = qty_on_hand - n`, never by writing a value worked out in the program.
3. READ COMMITTED is kept as the default. Reports that combine several queries run at REPEATABLE READ.
4. Reservations made by adding log rows run at SERIALIZABLE, and the program retries when a commit is refused.
5. A transaction that needs several materials locks them in `material_id` order.
