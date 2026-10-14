# Portfolio 5: Distributed and Cloud Database Exercise

Deeva's Designs on two PostgreSQL 18 servers, a primary and a streaming replica, used to test replication, consistency, availability, partitioning and failover. The second half of this page applies the results to how Deeva's should deploy its database.

## 1. Files

| File | Purpose |
|---|---|
| [docker-compose.yml](docker-compose.yml) | The two servers |
| [init-primary/](init-primary/) | Runs once on the primary: creates the replication login and loads the Portfolio 1 data |
| [replica/start-replica.sh](replica/start-replica.sh) | Copies the primary with `pg_basebackup` the first time, then starts as a replica |
| [run_demo.py](run_demo.py) | Rebuilds both servers and runs the seven steps below |
| [results/demo.txt](results/demo.txt) | Everything the demonstration did and saw, on my machine |
| [evidence/](evidence/) | Screenshots |

## 2. How to run

Docker Desktop must be running. From this folder:

```bash
python run_demo.py
```

The script starts by deleting and rebuilding both servers, so it can be run any number of times. It takes under a minute once the image is downloaded. `docker compose down -v` stops and removes everything afterwards.

The two servers are also published on this machine only, for pgAdmin: the primary on port 5433 and the replica on port 5434, user `postgres`, password `portfolio5`.

## 3. How the replica is built

1. The primary starts with `wal_level=replica`. Every change it makes is first written to its write-ahead log (WAL).
2. An initialisation script creates a login, `replicator`, that may only be used for replication.
3. The replica's data directory starts empty. `pg_basebackup` copies the primary's data files into it, and `-R` writes the connection settings that make it a replica.
4. A replication slot, `replica1`, makes the primary keep any WAL the replica has not yet received, so a replica that goes offline can catch up instead of having to be rebuilt.
5. From then on the primary streams WAL to the replica, which replays it. The replica accepts reads but refuses writes.

This is physical replication: the replica is a byte-for-byte copy of the whole server, not of chosen tables.

## 4. The demonstration

| Step | What was done | What happened |
|---|---|---|
| 1 | Asked each server what it is | The primary reports `streaming`, `async`, with a replay lag of about 1 ms |
| 2 | Inserted a customer on the primary | The row was on the replica by the time it was checked. The server measured the replay lag at a few milliseconds |
| 3 | Inserted a customer on the replica | Refused: `cannot execute INSERT in a read-only transaction` |
| 4 | Paused replay on the replica, then renamed a customer on the primary | The primary and the replica gave different names for the same customer until replay resumed |
| 5 | Switched to synchronous replication, then stopped the replica | An insert on the primary stalled. A second session showed it waiting on `SyncRep`. It completed only when the replica came back |
| 6 | Split 100,000 orders into four partitions by `customer_id` | About 25,000 rows in each. A query for one customer read one partition; a query by date read all four |
| 7 | Killed the primary, then promoted the replica | Reads continued throughout. Writes failed until promotion, then succeeded. Every write that reached the replica before the crash was still there |

## 5. What the results show

### Asynchronous replication: fast, available, briefly inconsistent

By default the primary confirms a commit as soon as it is safe on its own disk, and sends it to the replica afterwards. Step 2 shows the gap is normally a few milliseconds. Step 4 widens it on purpose: during that window a reader of the replica sees the old name. The replica is **eventually consistent**: it always catches up, but not instantly.

For Deeva's this matters only if something reads from the replica and then acts on what it read. A tailor checking measurements on the replica a second after they were changed could see the old ones.

### Synchronous replication: consistent, but less available

Step 5 makes the primary wait for the replica to confirm every commit. While both servers were up, inserts returned as normal, and the data was guaranteed to be on both machines when they did.

When the replica stopped, the primary was still running, yet it could no longer finish any write. The insert had been written to the primary's disk, but no other session could see it and the person who typed it had not been told it was saved. It finished only when the replica came back.

This is the trade-off described by the CAP theorem. When the two servers cannot reach each other, a system must choose between staying consistent (synchronous: refuse to confirm writes) and staying available (asynchronous: confirm writes the replica may never receive). PostgreSQL lets the administrator choose. A common middle way is two replicas with `synchronous_standby_names = 'ANY 1 (replica1, replica2)'`, which waits for whichever confirms first, so one replica can fail without stopping writes.

### Partitioning and the choice of shard key

Sharding spreads one table across several servers, each holding the rows for some values of a key. Step 6 splits one table into four parts by a hash of `customer_id`, within one server, to show what the choice of key does.

- A question about one customer went to one partition. On a sharded cluster it would go to one server.
- A question about a range of dates went to all four. On a sharded cluster every server would have to answer and the results would be combined.

So the shard key should match the questions asked most often. For Deeva's, the front desk asks about one customer at a time, which favours `customer_id`. The owner's monthly reports ask about dates, which would then touch every shard.

### Failover

In step 7 the primary was killed without warning. The replica kept answering reads, which means staff could still look up a customer's measurements, but nobody could take an order. After `pg_promote()` the replica became the primary and writes worked again, with no data lost: everything the old primary had confirmed had already reached the replica.

With asynchronous replication that last point is not guaranteed. A write confirmed in the few milliseconds before a crash may not have been sent. How much data a business can afford to lose is its **recovery point objective** (RPO); how long it can be without writes is its **recovery time objective** (RTO). Synchronous replication gives an RPO of zero at the cost shown in step 5.

Two things the demonstration does by hand would need a tool in production:

- **Noticing the crash and promoting the replica.** A manager such as Patroni does this automatically and moves the application's connection to the new primary.
- **Keeping the old primary out.** If it restarted believing it was still the primary, both servers would accept writes and the data would split. It must be rebuilt as a replica of the new primary, for example with `pg_rewind`.

## 6. Recommendation for Deeva's Designs

Deeva's is a start-up. The projection in Portfolio 2 puts three years of trading at under 1 GB, far below what one server handles. The risks that matter are losing data and the workshop being unable to work, not running out of capacity.

| Decision | Recommendation | Reason |
|---|---|---|
| Where the database runs | A managed PostgreSQL service in the cloud, not a computer in the shop | Power cuts, theft and a failed disk in the shop would otherwise take the data with them |
| High availability | A standby replica in a second availability zone, kept by the provider | Step 7 shows a replica can take over within seconds and keep everything committed |
| Synchronous or asynchronous | The provider's synchronous standby for orders and payments | A lost payment is worse than a slow one, and step 5's stall only happens if the standby fails |
| Read replicas | Not yet | Reporting load is small. Add one if month-end reports start slowing down the front desk |
| Sharding | No | The data fits comfortably on one server, and sharding would split the monthly reports across servers |
| Backups | Daily backups with point-in-time recovery, kept for at least 30 days | Replication copies mistakes as faithfully as good data: a deleted table is deleted on the replica too |
| Region | The closest region with the managed service, after checking data-protection law | Customer names, phone numbers and body measurements are personal data, and Nigeria's Data Protection Act 2023 sets conditions on storing them abroad |
| Internet outages at the shop | A second internet connection, such as mobile data | A cloud database is unreachable when the shop's connection is down |

The point about backups is worth stating plainly. Replication protects against a server failing. It does not protect against a person or a program doing the wrong thing, because the replica faithfully repeats every change, including a mistaken `DELETE`.
